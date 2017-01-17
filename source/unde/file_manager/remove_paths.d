module unde.file_manager.remove_paths;

import unde.global_state;
import unde.lsblk;
import unde.lib;
import unde.scan;
import unde.path_mnt;
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
import std.utf;
import std.concurrency;
import core.time;
import core.thread;
import std.datetime;

import derelict.sdl2.sdl;

import std.file;

immutable DRect drect_zero = DRect(0, 0, 0, 0);

private void
save_errors(FMGlobalState rgs, PathMnt path, Exception e)
{
    Dbt key, data;
    string path0 = path.get_key(rgs.lsblk);
    key = path0;
    auto res = rgs.db_map.get(rgs.txn, &key, &data);

    RectSize rectsize;
    if (res == 0)
        rectsize = data.to!(RectSize);

    ulong curr_time = Clock.currTime().toUnixTime();
    rectsize.msg = to_char_array!80(strip_error(e.msg));
    rectsize.msg_time = curr_time;
    rectsize.msg_color = 0x80FF8080; // ARGB

    data = rectsize;
    //writefln("WRITE - %s - %s", path0, rectsize);
    res = rgs.db_map.put(rgs.txn, &key, &data);
    if (res != 0)
        throw new Exception("Path info to map-db not written");
    rgs.OIT++;

    ssize_t first, last;
    first = path0.indexOf("\0");
    while (first != last)
    {
        last = path0.lastIndexOf("\0");
        if (last > first)
            path0 = path0[0..last];
        else
            path0 = path0[0..first+1];
        key = path0;
        res = rgs.db_map.get(rgs.txn, &key, &data);
        if (res == 0)
        {
            rectsize = data.to!(RectSize);

            if (curr_time > rectsize.newest_msg_time)
            {
                rectsize.newest_msg_time = curr_time;

                data = rectsize;
                //writefln("WRITE - %s - %s", path0, rectsize);
                res = rgs.db_map.put(rgs.txn, &key, &data);
                if (res != 0)
                    throw new Exception("Path info to map-db not written");
                rgs.OIT++;
            }
        }
    }
}

private void
remove_and_save_errors(FMGlobalState rgs, PathMnt path, bool dir=false)
{
    try
    {
        if (dir)
            rmdir(path);
        else
            remove(path);


    }
    catch (FileException e)
    {
        save_errors(rgs, path, e);
    }
}

package long
remove_path(FMGlobalState rgs, PathMnt path, bool root = true)
{
    rgs.recommit();
    //writefln("remove_path(%s)", path);
    // exits on exits of parent
    receiveTimeout( 0.seconds, 
            (OwnerTerminated ot) {
                writefln("Abort removing due stopping parent");
                rgs.finish = true;
            } );

    if (rgs.finish)
        return 0;

    DirEntry de;
    try
    {
        path.update(rgs.lsblk);
        de = DirEntry(path);
    }
    catch (Exception e)
    {
        writefln("%s", e);
        save_errors(rgs, path, e);
        return 0;
    }

    if (root)
    {
        string path0 = path.get_key(rgs.lsblk);
        foreach (char c; "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        {
            string m = "" ~ c;
            Dbt key, data;
            key = m;
            auto res = rgs.db_marks.get(null, &key, &data);
            if (res == 0)
            {
                Mark mark = data.to!(Mark);
                string mpath = from_char_array(mark.path);
                if (mpath.startsWith(path0))
                {
                    res = rgs.db_marks.del(null, &key);
                    if (res != 0)
                        throw new Exception("Mark info to marks-db not deleted");
                }
            }
        }
    }

    if (de.isSymlink)
    {
        remove(path);
        return 1;
    }
    else if (de.isDir)
    {
        string[] paths;
        try
        {
            foreach (string name; dirEntries(path, SpanMode.shallow))
            {
                paths ~= name;
            }
        }
        catch (Exception e)
        {
            return 0;
        }

        sort!("a < b")(paths);

        long files = 0;
        foreach (string name; paths)
        {
            if (name != path)
            {
                long f = remove_path(rgs, path.next(name), false);
                files += f;

            }
        }

        remove_and_save_errors(rgs, path, true);

        if (exists(path))
        {
            Dbt key, data;
            string path0 = path.get_key(rgs.lsblk);
            key = path0;
            //writefln("GET %s", info.uuid ~ subpath);
            auto res = rgs.db_map.get(rgs.txn, &key, &data);
            if (res == 0)
            {
                RectSize rectsize = data.to!(RectSize);
                if ( rectsize.files >= files )
                {
                    rectsize.files -= files;

                    data = rectsize;
                    //writefln("WRITE - %s - %s", path0, rectsize);
                    res = rgs.db_map.put(rgs.txn, &key, &data);
                    if (res != 0)
                        throw new Exception("Path info to map-db not written");
                    rgs.OIT++;
                }
            }
        }
        else
        {
            string path0 = path.get_key(rgs.lsblk);

            writefln("path0=%s", path0);
            Dbc cursor2;
            cursor2 = rgs.db_command_output.cursor(rgs.txn, 0);
            scope(exit) cursor2.close();

            Dbt key2, data2;
            string ks = get_key_for_command_out(command_out_key(path0, 0, 0));
            key2 = ks;
            auto res = cursor2.get(&key2, &data2, DB_SET_RANGE);
            if (res == 0)
            {
                do
                {
                    string key_string = key2.to!(string);
                    command_out_key cmd_out_key;
                    parse_key_for_command_out(key_string, cmd_out_key);

                    writefln("OUTPUT %s - %s", cmd_out_key.cwd, path0);
                    if (cmd_out_key.cwd == path0)
                    {
                        rgs.OIT++;
                        if (rgs.is_time_to_recommit())
                        {
                            cursor2.close();
                            rgs.recommit();
                            cursor2 = rgs.db_command_output.cursor(rgs.txn, 0);
                            res = cursor2.get(&key2, &data2, DB_SET_RANGE);
                            if (res == DB_NOTFOUND)
                            {
                                goto out1;
                            }
                        }

                        cursor2.del();
                    }
                    else
                    {
                        break;
                    }

                } while (cursor2.get(&key2, &data2, DB_NEXT) == 0);
            }
out1:

            Dbc cursor3;
            cursor3 = rgs.db_commands.cursor(rgs.txn, 0);
            scope(exit) cursor3.close();

            Dbt key3, data3;
            string ks3 = get_key_for_command(command_key(path0, 0));
            key3 = ks3;
            res = cursor3.get(&key3, &data3, DB_SET_RANGE);
            if (res == 0)
            {
                do
                {
                    string key_string = key3.to!(string);
                    command_key cmd_key;
                    parse_key_for_command(key_string, cmd_key);

                    if (cmd_key.cwd == path0)
                    {
                        rgs.OIT++;
                        if (rgs.is_time_to_recommit())
                        {
                            cursor3.close();
                            rgs.recommit();
                            cursor3 = rgs.db_commands.cursor(rgs.txn, 0);
                            res = cursor3.get(&key3, &data3, DB_SET_RANGE);
                            if (res == DB_NOTFOUND)
                            {
                                goto out2;
                            }
                        }

                        cursor3.del();
                    }
                    else
                    {
                        break;
                    }

                } while (cursor3.get(&key3, &data3, DB_NEXT) == 0);
            }

out2:
            Dbt key;
            key = path0;
            res = rgs.db_map.del(rgs.txn, &key);
            if (res != 0)
            {
                throw new Exception("Path info from map-db not removed");
            }
            rgs.OIT++;
        }
        return files;
    }
    else if (de.isFile)
    {
        remove_and_save_errors(rgs, path);
        return 1;
    }
    else 
    {
        remove_and_save_errors(rgs, path);
        return 1;
    }
}

private void
start_remove_paths(shared LsblkInfo[string] lsblk, immutable string[] paths, Tid tid)
{
    writefln("Start removing %s", paths);

    try {
        FMGlobalState rgs = new FMGlobalState();
        scope(exit)
        {
            destroy(rgs);
        }

        rgs.lsblk = to!(LsblkInfo[string])(lsblk);

        foreach(path; paths)
        {
            remove_path(rgs, PathMnt(rgs.lsblk, path));
            rgs.commit();
        }
    } catch (shared(Throwable) exc) {
        send(tid, exc);
    }

    writefln("Finish removing %s", paths);
    send(tid, thisTid);
}

int remove_paths(GlobalState gs, immutable string[] paths)
{
    foreach(tid, paths2; gs.removers)
    {
        if (paths2 == paths)
        {
            writefln("Remove Paths already in work");
            return 0;
        }
    }

    shared LsblkInfo[string] lsblk = to!(shared LsblkInfo[string])(gs.lsblk);
    auto tid = spawn(&start_remove_paths, lsblk, paths, thisTid);
    gs.removers[tid] = paths.dup();
    return 0;
}

void check_removers(GlobalState gs)
{
    // Look check_scanners
}

