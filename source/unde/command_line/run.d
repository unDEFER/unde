module unde.command_line.run;

import unde.global_state;
import unde.lsblk;
import unde.path_mnt;
import unde.slash;
import unde.command_line.db;

import std.stdio;
import std.conv;
import core.stdc.stdlib;
import std.math;
import berkeleydb.all;
import std.stdint;
import core.stdc.stdlib;
import std.string;
import std.algorithm.sorting;
import std.algorithm.searching;
import std.utf;
import std.concurrency;
import core.time;
import core.exception;
import core.sys.posix.sys.select;
import core.sys.posix.fcntl;
import core.sys.posix.unistd;
import core.stdc.string;
import core.stdc.errno;
import core.thread;
import std.process;
import std.regex;
import std.datetime;

import unde.lib;

import std.file;

version(Windows)
{
import core.sys.windows.windows;
import core.stdc.time;
alias ulong ulong_t;
}

private void
set_non_block_mode(int fd)
{
    int flags;
    if (-1 == (flags = fcntl(fd, F_GETFL, 0)))
        flags = 0;
    int res = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    if (res < 0)
    {
        throw new Exception("fcntl() error: " ~ fromStringz(strerror(errno)).idup());
    }
}


private ulong
get_max_id_of_cwd(CMDGlobalState cgs, string cwd)
{
    Dbc cursor = cgs.db_commands.cursor(cgs.txn, 0);
    scope(exit) cursor.close();

    Dbt key, data;
    ulong id = find_prev_command(cursor, cwd, 0, key, data);

    if (id != 0)
    {
        string key_string = key.to!(string);
        command_key cmd_key;
        parse_key_for_command(key_string, cmd_key);
        if (cwd != cmd_key.cwd)
        {
            id = 0;
        }
        else
        {
            id = cmd_key.id;
        }
    }

    return id;
}

private ulong
find_command_in_cwd(CMDGlobalState cgs, string cwd, string command)
{
    Dbc cursor = cgs.db_commands.cursor(cgs.txn, 0);
    scope(exit) cursor.close();

    Dbt key, data;
    ulong id = 0;
    string ks = get_key_for_command(command_key(cwd, 0));
    key = ks;
    auto res = cursor.get(&key, &data, DB_SET_RANGE);
    if (res == DB_NOTFOUND)
    {
        return 0;
    }

    do
    {
        string key_string = key.to!(string);
        command_key cmd_key;
        parse_key_for_command(key_string, cmd_key);

        string data_string = data.to!(string);
        command_data cmd_data;
        parse_data_for_command(data_string, cmd_data);

        if (cmd_key.cwd != cwd) break;
        if (cmd_data.command == command)
        {
            id = cmd_key.id;
            break;
        }

    } while (cursor.get(&key, &data, DB_NEXT) == 0);

    return id;
}

private void
delete_command_out(CMDGlobalState cgs, string cwd, ulong cmd_id)
{
    Dbc cursor = cgs.db_command_output.cursor(cgs.txn, 0);
    scope(exit) cursor.close();

    Dbt key, data;
    ulong id = 0;
    string ks = get_key_for_command_out(command_out_key(cwd, cmd_id, 0));
    key = ks;
    auto res = cursor.get(&key, &data, DB_SET_RANGE);
    if (res == DB_NOTFOUND)
    {
        return;
    }

    do
    {
        string key_string = key.to!(string);
        command_out_key cmd_out_key;
        parse_key_for_command_out(key_string, cmd_out_key);

        if (cmd_out_key.cwd == cwd && cmd_out_key.cmd_id == cmd_id)
        {
            cursor.del();
            cgs.OIT++;
        }
        else
        {
            break;
        }

    } while (cursor.get(&key, &data, DB_NEXT) == 0);

}

private int
fork_command(CMDGlobalState cgs, string cwd, string command)
{
    cgs.recommit();

/*db_commands
cwd, id
    command, start, end, status*/

    ulong id = get_max_id_of_cwd(cgs, cwd);
    ulong new_id = id+1;
    if (id > 0)
    {
        new_id = id + 1000 - id%1000;
        writefln("last_id=%s (%%1000=%s), new_id=%s", id, id%1000, new_id);
    }

    if (command[0] != '*' && command[0] != '+')
    {
        ulong replace_id = find_command_in_cwd(cgs, cwd, command);

        string ks = get_key_for_command(command_key(cwd, replace_id));
        Dbt key = ks;
        auto res = cgs.db_commands.del(cgs.txn, &key);

        delete_command_out(cgs, cwd, replace_id);
    }

    Dbt key, data;
    string ks = get_key_for_command(command_key(cwd, new_id));
    key = ks;
    command_data cmd_data = command_data(command, 0, 0, -1);
    string ds = get_data_for_command(cmd_data);
    data = ds;

    auto res = cgs.db_commands.put(cgs.txn, &key, &data);
    if (res != 0)
    {
        throw new Exception("DB command not written");
    }

    Dbt key2, data2;
    string ks2 = get_key_for_command(command_key(cwd, id));
    key2 = ks;

    if (command[0] == '+' && id > 0)
    {
        do
        {
            res = cgs.db_commands.get(cgs.txn, &key2, &data2);
            if (res == 0)
            {
                string data2_string = data.to!(string);
                command_data cmd_data2;
                parse_data_for_command(data2_string, cmd_data2);
                if (cmd_data2.end > 0)
                {
                    if (cmd_data2.status != 0)
                    {
                        cmd_data.end = Clock.currTime().stdTime();
                        ds = get_data_for_command(cmd_data);
                        data = ds;

                        res = cgs.db_commands.put(cgs.txn, &key, &data);
                        if (res != 0)
                        {
                            throw new Exception("DB command not written");
                        }
                        cgs.OIT++;

                        return cmd_data2.status;
                    }
                    else
                    {
                        break;
                    }
                }
            }
            else
            {
                throw new Exception(format("Command with id %d not found", id));
            }

            cgs.commit;
            Thread.sleep( 200.msecs() );
            cgs.recommit;
        }
        while (true);
    }

/*db_command_output
cwd, command_id, out_id,
    time, stderr/stdout, output*/

    chdir(cwd);
    auto cmd_pipes = pipeProcess(["bash", "-c", command], Redirect.stdout | Redirect.stderr);
    scope(exit) wait(cmd_pipes.pid);

    cmd_data.start = Clock.currTime().stdTime();
    ds = get_data_for_command(cmd_data);
    data = ds;

    res = cgs.db_commands.put(cgs.txn, &key, &data);
    if (res != 0)
    {
        throw new Exception("DB command not written");
    }

    cgs.commit();
    cgs.recommit();

    auto fdstdout = cmd_pipes.stdout.fileno;
    auto fdstderr = cmd_pipes.stderr.fileno;
    auto fdmax = (fdstderr>fdstdout?fdstderr:fdstdout);

    /*Make file descriptions NON_BLOCKING */
    set_non_block_mode(fdstdout);
    set_non_block_mode(fdstderr);

    fd_set rfds;
    timeval tv;
    int retval;

    /* Wait up to 100ms seconds. */
    tv.tv_sec = 0;
    tv.tv_usec = 100_000;

    int buffer_full = 0;
    bool terminated;
    int result = -1;
    ulong out_id = 0;
    char[4096] buf1;
    char[4096] buf2;
    size_t buf1_r;
    size_t buf2_r;
    ulong out_id1 = 0;
    ulong out_id2 = 0;
    while(!cgs.finish)
    {
        cgs.recommit();
        if (buffer_full <= 0)
        {
            auto dmd = tryWait(cmd_pipes.pid);
            if (dmd.terminated)
            {
                terminated =true;
                if (buffer_full < 0)
                {
                    cgs.commit();
                    cgs.recommit();
                    cmd_data.end = Clock.currTime().stdTime();
                    cmd_data.status = dmd.status;
                    result = dmd.status;
                    ds = get_data_for_command(cmd_data);
                    data = ds;

                    res = cgs.db_commands.put(cgs.txn, &key, &data);
                    if (res != 0)
                    {
                        throw new Exception("DB command not written");
                    }
                    cgs.OIT++;
                    break;
                }
            }
        }

        buffer_full = 0;

        FD_ZERO(&rfds);
        FD_SET(fdstdout, &rfds);
        FD_SET(fdstderr, &rfds);

        retval = select(fdmax+1, &rfds, null, null, &tv);
        if (retval < 0)
        {
            throw new Exception("select() error: " ~ fromStringz(strerror(errno)).idup());
        }
        else if (retval > 0)
        {
            if (FD_ISSET(fdstdout, &rfds))
            {
                ssize_t r;
                r = read(fdstdout, buf1[buf1_r..$].ptr, buf1[buf1_r..$].length);
                if (r > 0)
                {
                    r += buf1_r;
                    buffer_full |= (r >= buf1.length);
                    Dbt key3, data3;
                    if (out_id1 == 0)
                    {
                        out_id++;
                        out_id1 = out_id;
                    }
                    //writefln("OUT: new_id=%s out_id=%s", new_id, out_id1);
                    ks = get_key_for_command_out(command_out_key(cwd, new_id, out_id1));
                    key3 = ks;

                    ssize_t split_r;
                    if (r < buf1.length) split_r = r;
                    else
                    {
                        ssize_t sym = buf1[r/2..$].lastIndexOf("\n");
                        if (sym >= 0) split_r = r/2+sym+1;
                        else
                        {
                            sym = buf1[r/2..$].lastIndexOf(".");
                            if (sym >= 0) split_r = r/2+sym+1;
                            else
                            {
                                sym = buf1[r/2..$].lastIndexOf(" ");
                                if (sym >= 0) split_r = r/2+sym+1;
                                else
                                {
                                    for (auto i = r-1; i >= 0; i--)
                                    {
                                        if ((buf1[i] & 0b1000_0000) == 0 ||
                                                (buf1[i] & 0b1100_0000) == 0b1100_0000)
                                        {
                                            split_r = i;
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    writefln("OUT: buf=%s r=%s", buf1[0..split_r], split_r);
                    /*ssize_t a = ((split_r-25 >= 0) ? split_r-25 : 0);
                    ssize_t b = ((split_r+25 <= r) ? split_r+25 : r);
                    writefln("OUT: split \"%s\"~\"%s\" r=%s", 
                            buf1[a..split_r], 
                            buf1[split_r..b], 
                            split_r);*/
                    ds = get_data_for_command_out(command_out_data(Clock.currTime().stdTime(), OutPipe.STDOUT, buf1[0..split_r].idup()));
                    data3 = ds;
                    res = cgs.db_command_output.put(cgs.txn, &key3, &data3);
                    if (res != 0)
                    {
                        throw new Exception("DB command out not written");
                    }
                    cgs.OIT++;

                    bool no_n = false;
                    if (split_r < r)
                    {
                        buf1[0..r - split_r] = buf1[split_r..r];
                        /*ssize_t c = ((50 < r - split_r) ? 50 : r - split_r);
                        writefln("buf: \"%s\"", buf1[0..c]);*/
                    }
                    else
                    {
                        if (r < buf1.length/2)
                        {
                            if (buf1[r-1] != '\n')
                            {
                                r += r;
                                no_n = true;

                                writefln("Not ended with \\n line found");
                            }
                        }
                    }
                    if (!no_n) out_id1 = 0;
                    buf1_r = r - split_r;
                }
                if (r < 0 && errno != EWOULDBLOCK)
                {
                    throw new Exception("read() error: " ~ fromStringz(strerror(errno)).idup());
                }
            }
            if (FD_ISSET(fdstderr, &rfds))
            {
                ssize_t r;
                r = read(fdstderr, buf2[buf2_r..$].ptr, buf2[buf2_r..$].length);
                if (r > 0)
                {
                    r += buf2_r;
                    buffer_full |= (r >= buf2.length);
                    Dbt key3, data3;
                    if (out_id2 == 0)
                    {
                        out_id++;
                        out_id2 = out_id;
                    }
                    ks = get_key_for_command_out(command_out_key(cwd, new_id, out_id2));
                    key3 = ks;

                    ssize_t split_r;
                    if (r < buf2.length) split_r = r;
                    else
                    {
                        ssize_t sym = buf2[r/2..$].lastIndexOf("\n");
                        if (sym >= 0) split_r = r/2+sym+1;
                        else
                        {
                            sym = buf2[r/2..$].lastIndexOf(".");
                            if (sym >= 0) split_r = r/2+sym+1;
                            else
                            {
                                sym = buf2[r/2..$].lastIndexOf(" ");
                                if (sym >= 0) split_r = r/2+sym+1;
                                else
                                {
                                    for (auto i = r-1; i >= 0; i--)
                                    {
                                        if ((buf2[i] & 0b1000_0000) == 0 ||
                                                (buf2[i] & 0b1100_0000) == 0b1100_0000)
                                        {
                                            split_r = i;
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    writefln("ERR: buf=%s r=%s", buf1[0..split_r], split_r);
                    ds = get_data_for_command_out(command_out_data(Clock.currTime().stdTime(), OutPipe.STDERR, buf2[0..split_r].idup()));
                    data3 = ds;
                    res = cgs.db_command_output.put(cgs.txn, &key3, &data3);
                    if (res != 0)
                    {
                        throw new Exception("DB command out not written");
                    }
                    cgs.OIT++;

                    bool no_n = false;
                    if (split_r < r)
                    {
                        buf2[0..r - split_r] = buf2[split_r..r];
                    }
                    else
                    {
                        if (r < buf2.length/2)
                        {
                            if (buf2[r-1] != '\n')
                            {
                                r += r;
                                no_n = true;

                                writefln("Not ended with \\n line found");
                            }
                        }
                    }
                    if (!no_n) out_id2 = 0;
                    buf2_r = r - split_r;
                }
                if (r < 0 && errno != EWOULDBLOCK)
                {
                    throw new Exception("read() error: " ~ fromStringz(strerror(errno)).idup());
                }
            }
        }

        if (buffer_full == 0 && terminated) buffer_full = -1;

        receiveTimeout( 0.seconds, 
                (OwnerTerminated ot) {
                    writefln("Abort command due stopping parent");
                    kill(cmd_pipes.pid);
                    cgs.finish = true;

                    cmd_data.end = Clock.currTime().stdTime();
                    cmd_data.status = -1;
                    string ds = get_data_for_command(cmd_data);
                    data = ds;

                    auto res = cgs.db_commands.put(cgs.txn, &key, &data);
                    if (res != 0)
                    {
                        throw new Exception("DB command not written");
                    }
                } );
    }
    return result;
}

private void
command(string cwd, string command, Tid tid)
{
    CMDGlobalState cgs = new CMDGlobalState();
    try {
        scope(exit)
        {
            destroy(cgs);
        }
        fork_command(cgs, cwd, command);
        cgs.commit();
    } catch (shared(Throwable) exc) {
        send(tid, exc);
    }

    writefln("Finish command %s", command);
    send(tid, thisTid);
}

public int
run_command(GlobalState gs, string command)
{
    shared LsblkInfo[string] lsblk = to!(shared LsblkInfo[string])(gs.lsblk);
    shared CopyMapInfo[string] copy_map = cast(shared CopyMapInfo[string])(gs.copy_map);

    writefln("Start command %s", command);
    auto tid = spawn(&.command, gs.full_current_path, command, thisTid);
    gs.commands[tid] = command;
    return 0;
}

