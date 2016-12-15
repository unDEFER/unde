module unde.file_manager.change_rights;

import unde.global_state;
import unde.lsblk;
import unde.lib;
import unde.scan;
import unde.path_mnt;

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
import std.process;
import std.concurrency;
import core.time;
import core.thread;
import core.stdc.errno;
import core.stdc.string;
import std.datetime;
import std.regex;
import std.algorithm.sorting;

import derelict.sdl2.sdl;

import std.file;
import core.sys.posix.sys.stat;

version(Posix)
{
enum DirOrFile
{
    All,
    Dir,
    File
}

private void
save_errors(FMGlobalState cgs, PathMnt path, string e)
{
    DbTxn txn = null;
    Dbt key, data;
    string path0 = path.get_key(cgs.lsblk);
    key = path0;
    auto res = cgs.db_map.get(txn, &key, &data);

    RectSize rectsize;
    if (res == 0)
        rectsize = data.to!(RectSize);

    ulong curr_time = Clock.currTime().toUnixTime();
    rectsize.msg = to_char_array!80(strip_error(e));
    rectsize.msg_time = curr_time;
    rectsize.msg_color = 0x80FF8080; // ARGB

    data = rectsize;
    //writefln("WRITE - %s - %s", path0, rectsize);
    res = cgs.db_map.put(txn, &key, &data);
    if (res != 0)
        throw new Exception("Path info to map-db not written");

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
        res = cgs.db_map.get(txn, &key, &data);
        if (res == 0)
        {
            rectsize = data.to!(RectSize);

            if (curr_time > rectsize.newest_msg_time)
            {
                rectsize.newest_msg_time = curr_time;

                data = rectsize;
                //writefln("WRITE - %s - %s", path0, rectsize);
                res = cgs.db_map.put(txn, &key, &data);
                if (res != 0)
                    throw new Exception("Path info to map-db not written");
            }
        }
    }
}

private void
change_rights_ang_save_errors(FMGlobalState cgs, PathMnt path, mode_t mode)
{
    //writefln("%s: %s", path, mode_to_string(mode));
    int res = chmod(toStringz(path), mode);
    if (res < 0)
    {
        save_errors(cgs, path, fromStringz(strerror(errno)).idup());
    }
}

private void
change_rights(FMGlobalState cgs, PathMnt path, bool set, int bit, DirOrFile dof, bool recursive)
{
    //writefln("remove_path(%s)", path);
    // exits on exits of parent
    receiveTimeout( 0.seconds, 
            (OwnerTerminated ot) {
                writefln("Abort removing due stopping parent");
                cgs.finish = true;
            } );

    if (cgs.finish)
        return;

    DirEntry de;
    mode_t mode;
    try
    {
        path.update(cgs.lsblk);
        de = DirEntry(path);

        mode = de.statBuf.st_mode;
        final switch(dof)
        {
            case DirOrFile.Dir:
                if (!de.isSymlink && de.isDir)
                {
                    goto case DirOrFile.All;
                }
                break;
            case DirOrFile.File:
                if (de.isSymlink || de.isFile)
                {
                    goto case DirOrFile.All;
                }
                break;
            case DirOrFile.All:
                if (set)
                    mode |= 1 << (11-bit);
                else
                    mode &= ~(1 << (11-bit));
                break;
        }
    }
    catch (Exception e)
    {
        save_errors(cgs, path, e.msg);
    }

    try
    {
        if (de.isSymlink)
        {
            change_rights_ang_save_errors(cgs, path, mode);
            return;
        }
        else if (de.isDir)
        {
            if (recursive)
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
                    return;
                }

                sort!("a < b")(paths);

                foreach (string name; paths)
                {
                    if (name != path)
                    {
                        change_rights(cgs, path.next(name), set, bit, dof, recursive);
                    }
                }
            }

            change_rights_ang_save_errors(cgs, path, mode);
            return;
        }
        else if (de.isFile)
        {
            change_rights_ang_save_errors(cgs, path, mode);
            return;
        }
        else 
        {
            change_rights_ang_save_errors(cgs, path, mode);
            return;
        }
    }
    catch (Exception e)
    {
        save_errors(cgs, path, e.msg);
    }
}

private void
start_change_rights(shared LsblkInfo[string] lsblk, immutable string[] paths, 
        bool set, int bit, DirOrFile dof, bool recursive, Tid tid)
{
    writefln("Start change rights %s", paths);

    try {
        FMGlobalState cgs = new FMGlobalState();
        scope(exit)
        {
            destroy(cgs);
        }

        cgs.lsblk = to!(LsblkInfo[string])(lsblk);

        DbTxn txn = null;//dbenv.txn_begin(null);
        string[] paths_dup = paths.dup;
        sort!("a < b")(paths_dup);
        foreach(path; paths_dup)
        {
            change_rights(cgs, PathMnt(cgs.lsblk, path), set, bit, dof, recursive);
        }
        //txn.commit();
    } catch (shared(Throwable) exc) {
        send(tid, exc);
    }

    writefln("Finish change rights %s", paths);
    send(tid, thisTid);
}

int change_rights(GlobalState gs, immutable string[] paths, bool set, int bit, 
        DirOrFile dof, bool recursive)
{
    foreach(tid, paths2; gs.changers_rights)
    {
        if (paths2 == paths)
        {
            string msg = format("Wait till finished previous task on change rights");
            gs.messages ~= ConsoleMessage(
                    SDL_Color(0xFF, 0x00, 0x00, 0xFF),
                    msg,
                    SDL_GetTicks()
                    );
            writeln(msg);
            return -1;
        }
    }

    shared LsblkInfo[string] lsblk = to!(shared LsblkInfo[string])(gs.lsblk);
    auto tid = spawn(&start_change_rights, lsblk, paths, set, bit, dof, 
                        recursive, thisTid);
    gs.changers_rights[tid] = paths.dup();
    return 0;
}

void check_changer_rights(GlobalState gs)
{
    // Look check_scanners
}
}
