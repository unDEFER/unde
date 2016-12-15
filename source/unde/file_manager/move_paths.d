module unde.file_manager.move_paths;

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
import std.datetime;
import std.regex;
import std.algorithm.sorting;

import unde.file_manager.copy_paths;
import unde.file_manager.remove_paths;
import unde.slash;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;
import derelict.sdl2.image;

import std.file;

immutable DRect drect_zero = DRect(0, 0, 0, 0);

private long
move_path(FMGlobalState mgs, PathMnt path, string move_to, bool remove_flag, Tid tid)
{
    string orig_move_to = move_to;
    string dir_to = move_to;

    if (move_to[$-1] == SL[0])
    {
        string name = path.path[path.path.lastIndexOf(SL)+1..$];
        move_to ~= name;
    }
    else
        dir_to = getParent(dir_to);

    try
    {
        auto de1 = DirEntry(path._next);
        auto de2 = DirEntry(dir_to);

	
	version(Posix)
	{
        bool the_same_filesystem = de1.statBuf.st_dev == de2.statBuf.st_dev;
	}
	else version(Windows)
	{
	bool the_same_filesystem = path._next[0] == dir_to[0];
	}
	if ( the_same_filesystem )
        {
            if (path._next[$-1] == SL[0]) path._next = path._next[0..$-1];
            /*writefln("move.thread send to %s (%s, %s, %s, %s)", 
                    tid, thisTid, path._next, move_to, "send");*/
            send(tid, thisTid, path._next, move_to, true, MsgState.Send);
            MsgState resent;
            do
            {
                //writefln("move.thread %s wait for resent", thisTid);
                receive( (MsgState msg) { 
                        resent = msg; 
                        /*writefln("move.thread %s receive %s", thisTid, msg);*/ } );
            } while (resent != MsgState.Resent);

            rename(path.path, move_to);

            bool size_updated = false;
            /* It is good to do, but there is no src path to copy info from it
            while (!size_updated)
            {
                size_updated = update_progress(mgs, path, move_to_mnt, 
                        size_updated,
                        "",
                        Clock.currTime().toUnixTime(),
                        10000,
                        txn);
                if (!size_updated)
                    Thread.sleep( 200.msecs() );
            }*/
        }
        else
        {
            int num_errors = copy_path(mgs, path, orig_move_to, remove_flag, tid);
            if (num_errors == 0)
                remove_path(mgs, path);
        }
    }
    catch (Exception exp)
    {
        shared msg = ConsoleMessage(
                SDL_Color(0xFF, 0x00, 0x00, 0xFF),
                format("Failed Move: %s", exp.msg),
                SDL_GetTicks()
                );
        send(tid, msg);
    }

    return 0;
}

private void
start_move_paths(shared LsblkInfo[string] lsblk, immutable string[] paths, string move_to, bool remove, Tid tid)
{
    writefln("Start moving %s, remove=%s", paths, remove);

    try {
        FMGlobalState mgs = new FMGlobalState();
        scope(exit)
        {
            destroy(mgs);
        }

        mgs.lsblk = to!(LsblkInfo[string])(lsblk);

        string[] paths_dup = paths.dup;
        sort!("a < b")(paths_dup);
        foreach(path; paths_dup)
        {
            move_path(mgs, PathMnt(mgs.lsblk, path), move_to, remove, tid);
        }
    } catch (shared(Throwable) exc) {
        send(tid, exc);
    }

    writefln("Finish moving %s", paths);
    send(tid, thisTid);
}

int move_paths(GlobalState gs, immutable string[] paths, string move_to, bool remove)
{
    foreach(tid, paths2; gs.movers)
    {
        if (paths2 == paths)
        {
            writefln("Move %s already in work", paths);
            return 0;
        }
    }

    shared LsblkInfo[string] lsblk = to!(shared LsblkInfo[string])(gs.lsblk);
    auto tid = spawn(&start_move_paths, lsblk, paths, move_to, remove, thisTid);
    gs.movers[tid] = paths.dup();
    return 0;
}

void check_movers(GlobalState gs)
{
    // Look check_scanners
}

