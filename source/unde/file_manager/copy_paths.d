module unde.file_manager.copy_paths;

import unde.global_state;
import unde.lsblk;
import unde.lib;
import unde.scan;
import unde.path_mnt;
import unde.slash;

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

/*mkstemp, fchmod. strerror, errno, close*/
import core.stdc.string;
import core.stdc.errno;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;
import derelict.sdl2.image;

import std.file;
import core.sys.posix.unistd;
import core.sys.posix.stdlib;
import core.sys.posix.sys.stat;

immutable DRect drect_zero = DRect(0, 0, 0, 0);

private void
save_errors(FMGlobalState cgs, PathMnt path, string error)
{
    cgs.recommit();
    Dbt key, data;
    string path0 = path.get_key(cgs.lsblk);
    key = path0;
    auto res = cgs.db_map.get(cgs.txn, &key, &data);
    cgs.OIT++;

    RectSize rectsize;
    if (res == 0)
        rectsize = data.to!(RectSize);

    ulong curr_time = Clock.currTime().toUnixTime();
    rectsize.msg = to_char_array!80(error);
    rectsize.msg_time = curr_time;
    rectsize.msg_color = 0x80FF8080; // ARGB

    data = rectsize;
    //writefln("WRITE - %s - %s", path0, rectsize);
    res = cgs.db_map.put(cgs.txn, &key, &data);
    if (res != 0)
        throw new Exception("Path info to map-db not written");
    cgs.OIT++;
    cgs.recommit();

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
        res = cgs.db_map.get(cgs.txn, &key, &data);
        cgs.OIT++;
        if (res == 0)
        {
            rectsize = data.to!(RectSize);

            if (curr_time > rectsize.newest_msg_time)
            {
                rectsize.newest_msg_time = curr_time;

                data = rectsize;
                //writefln("WRITE - %s - %s", path0, rectsize);
                res = cgs.db_map.put(cgs.txn, &key, &data);
                if (res != 0)
                    throw new Exception("Path info to map-db not written");
                cgs.OIT++;
                cgs.recommit();
            }
        }
    }
}

private RectSize
get_path_rectsize(FMGlobalState cgs, PathMnt path)
{
    string path0 = path.get_key(cgs.lsblk);
    path0 = path0[0..$-1];
    Dbt key = path0;
    Dbt data;
    RectSize rectsize;
    auto res = cgs.db_map.get(cgs.txn, &key, &data);
    cgs.OIT++;
    if (res == 0)
    {
        rectsize = data.to!(RectSize);
    }
    return rectsize;
}

package void
update_progress(FMGlobalState cgs, PathMnt copy_to_mnt, 
        string progress_path,
        long estimate_end,
        int progress // from 0 tlll 10000
        )
{
    cgs.recommit();
    string copy_to0 = copy_to_mnt.get_key(cgs.lsblk);

    Dbt key;
    Dbt data;
    copy_to0 = copy_to0[0..$-1];

    key = copy_to0;
    //writefln("Get %s", copy_to0.replace("\0", SL));
    int res = cgs.db_map.get(cgs.txn, &key, &data);
    cgs.OIT++;
    if (res == 0)
    {
        RectSize rectsize;
        rectsize = data.to!(RectSize);

        if (progress >= 10000)
        {
            rectsize.path[0..$] = char.init;
            rectsize.estimate_end = 0;
            rectsize.progress = 0;
            rectsize.show_info = InfoType.None;
        }
        else
        {
            rectsize.path = to_char_array!80(progress_path);
            rectsize.estimate_end = estimate_end;
            rectsize.progress = progress;
            rectsize.show_info = InfoType.Progress;
        }

        //writefln("Put progress %s", progress);
        data = rectsize;
        res = cgs.db_map.put(cgs.txn, &key, &data);
        if (res != 0)
            throw new Exception("Path info to map-db not written");
        cgs.OIT++;
        cgs.recommit();
    }
}

version (Windows)
{
private string
windows_path_to_cygwin(FMGlobalState cgs, string path)
{
	if (path[1] == ':')
	{
		path = "\\cygdrive\\" ~ toLower(path[0..1]) ~ path[2..$];
	}	
	return path.replace(SL, "/");
}

private string
cygwin_path_to_windows(FMGlobalState cgs, string path)
{
	if (path.startsWith("/cygdrive/"))
	{
		path = toUpper(path[10..11]) ~ ":" ~ path[11..$];
	}	
	return path.replace("/", SL);
}

unittest
{
	string win_path = "C:\\TEST\\";
	string cygwin_path = "/cygdrive/c/TEST/";

	string cygwin_path2 = windows_path_to_cygwin(null, win_path);
	string win_path2 = cygwin_path_to_windows(null, cygwin_path);
	assert(win_path == win_path2, win_path ~ " == " ~ win_path2);
	assert(cygwin_path == cygwin_path2, cygwin_path ~ " == " ~ cygwin_path2);
}
}

package int
copy_path(FMGlobalState cgs, PathMnt path, string copy_to, bool remove_flag, Tid tid)
{
    cgs.recommit();
    int num_errors;
    string archieve_option = "-a";

    version(Posix)
    {
    string to_directory = getParent(copy_to);
    char[] temp_template = (to_directory ~ "/check_chmod_XXXXXXX").dup();
    int fd = mkstemp(cast(char*)temp_template);
    if (fd >= 0)
    {
        string temp_file = temp_template.idup();
        int res = fchmod(fd, std.conv.octal!666);
        if (res != 0)
        {
            archieve_option = "-rltgoD";
        }
        close(fd);
        remove(temp_file);
    }
    else
    {
        string error = fromStringz(strerror(errno)).idup();
        writefln(error);
    }
    }

    string path_for_rsync = path;
    string copy_to_for_rsync = copy_to;
    version (Windows)
    {
    path_for_rsync = windows_path_to_cygwin(cgs, path_for_rsync);
    copy_to_for_rsync = windows_path_to_cygwin(cgs, copy_to_for_rsync);
    }

    string[] rsync_args;
    /* I very want to use -S (--sparse) option here, but it not compatible with --inplace
       but inplace necessary for progress algorithm */
    if (remove_flag)
        rsync_args = ["rsync", archieve_option, "-vuH", "--inplace", "--delete", path_for_rsync, copy_to_for_rsync];
    else
        rsync_args = ["rsync", archieve_option, "-vuH", "--inplace", path_for_rsync, copy_to_for_rsync];
    auto rsync_pipes = pipeProcess(rsync_args, Redirect.stdout | Redirect.stderrToStdout);
    scope(exit) wait(rsync_pipes.pid);

    if (copy_to[$-1] == SL[0])
    {
        string name = path.path[path.path.lastIndexOf(SL)+1..$];
        copy_to ~= name ~ SL;
    }
    else copy_to ~= SL;

    PathMnt copy_to_mnt = PathMnt(cgs.lsblk, copy_to);

    if (path._next[$-1] != SL[0])
        path._next ~= SL;

    RectSize goal_rectsize = get_path_rectsize(cgs, path);
    RectSize current_rectsize = get_path_rectsize(cgs, copy_to_mnt);

    writefln("Goal %s", goal_rectsize.disk_usage);
    writefln("Current %s", current_rectsize.disk_usage);

    long disk_usage_at_start = current_rectsize.disk_usage;
    long last_measure = Clock.currTime().stdTime;
    bool first_measure = true;
    long disk_usage_at_last_measure = current_rectsize.disk_usage;
    long[] measurements;
    long estimate_end;

    cgs.commit();
    string path_from = path.path;
    if (path_from[$-1] == SL[0]) path_from = path_from[0..$-1];
    send(tid, thisTid, path_from, copy_to[0..$-1], false, MsgState.Send);
    MsgState resent;
    //writefln("%s waits resent", thisTid);
    do
    {
        receive( (MsgState msg) { resent = msg; } );
    } while (resent != MsgState.Resent);
    //writefln("%s resent got", thisTid);
    cgs.recommit();

    foreach (rsync_line; rsync_pipes.stdout.byLine)
    {
        cgs.recommit();
        //writefln("rsync_line: %s", rsync_line);
        // exits on exits of parent
        receiveTimeout( 0.seconds, 
                (OwnerTerminated ot) {
                    writefln("Abort copying due stopping parent");
                    cgs.finish = true;
                } );
        if (cgs.finish) break;

        auto match = matchFirst(rsync_line, regex(`rsync: ([^()"]*)\(?"?(.*?)"?\)? failed: (.*)`));
	if (!match)
	    match = matchFirst(rsync_line, regex(`([^()"]*) failed to [^"]* "(.*?)": (.*)`));
        if (match)
        {
            string operation = match[1].idup();
            string err_path = match[2].idup();
            string error = match[3].idup();
            while (operation[$-1] == ' ') operation = operation[0..$-1];
            if (err_path[0] != SL[0])
                err_path = copy_to ~ err_path;

            string name = "";
            while(!exists(err_path)) 
            {
                writefln("copy_path: %s doesn't exists", err_path);
                name = err_path[err_path.lastIndexOf(SL)+1..$]~SL~name;
                err_path = getParent(err_path);
                if (err_path == "") err_path = SL;
            }

            PathMnt err_pathmnt = PathMnt(cgs.lsblk, err_path);

            num_errors++;

            save_errors(cgs, err_pathmnt, operation ~": "~error);
            //writefln("[%s, %s, %s]", operation, err_path, error);
        }
        else
        {
            match = matchFirst(rsync_line, regex(`^(\*\*\*.*\*\*\*|sending incremental file list||sent .*|total .*|.*some files/attrs were not transferred.*)$`));
            if (!match)
            {
                match = matchFirst(rsync_line, regex(`^deleting (.*)$`));
                if (match)
                {
                    string del_path = match[1].idup();
		    version(Windows)
		    {
			    del_path = cygwin_path_to_windows(cgs, del_path);
		    }
                    if (del_path[0] != SL[0])
                        del_path = copy_to ~ del_path;

                    PathMnt del_path_mnt = PathMnt(cgs.lsblk, del_path);

                    if (del_path_mnt._next[$-1] != SL[0])
                        del_path_mnt._next ~= SL;

                    RectSize del_rectsize = get_path_rectsize(cgs, del_path_mnt);

                    current_rectsize.disk_usage -= del_rectsize.disk_usage;

                    writefln("del path %s, usage %s", del_path, del_rectsize.disk_usage);
                }
                else
                {
                    string line = rsync_line.idup();
                    match = matchFirst(rsync_line, regex(`^(.*) -> (.*)$`));
                    if (match)
                    {
                        line = match[1].idup();
                    }
                    else
                    {
                        match = matchFirst(rsync_line, regex(`^(.*) => (.*)$`));
                        if (match)
                        {
                            line = match[2].idup();
                        }
			else
			{
			    match = matchFirst(rsync_line, regex(`^created directory (.*)$`));
			    if (match)
			    {
				line = match[1].idup();
				continue;
			    }
			    else
			    {
			        match = matchFirst(rsync_line, regex(`^skipping non-regular file`));
				if (match)
				{
				    continue;
				}
  			    }
			}
                    }

		    version(Windows)
		    {
			    line = cygwin_path_to_windows(cgs, line);
		    }

                    string path_wo_slash = path[0..$-1];
                    string cur_path = path[0..path_wo_slash.lastIndexOf(SL)+1] ~ line;
                    string copy_to_wo_slash = copy_to[0..$-1];
                    string copy_to_path = copy_to[0..copy_to_wo_slash.lastIndexOf(SL)+1] ~ line;

                    if (path.path == cur_path)
                    {
                        copy_to_path = copy_to[0..$-1];
                    }

                    if (path.path[$-1] == SL[0])
                    {
                        cur_path = path ~ line;
                        copy_to_path = copy_to ~ line;
                    }

                    PathMnt cur_path_mnt = PathMnt(cgs.lsblk, cur_path);

                    if (cur_path_mnt._next[$-1] != SL[0])
                        cur_path_mnt._next ~= SL; 

                    //writefln("%s, %s", cur_path_mnt._next, copy_to_path);
                    RectSize cur_rectsize = get_path_rectsize(cgs, cur_path_mnt);

                    long current_disk_usage = current_rectsize.disk_usage;

                    //writefln("path %s, size %s", line,
                    //        cur_rectsize.disk_usage);

                    long disk_usage;
                    int error = 0;
                    int tries = 5;
                    do{
                        error = 0;
                        try{
                            auto de = DirEntry(copy_to_path);
                            if (!de.isSymlink() && !de.isDir())
                            { 
                                long last_disk_usage = 0;
                                int the_same_disk_usage_times = 0;
                                do
                                {
                                    long stdtime = Clock.currTime().stdTime;
                                    long unixtime = Clock.currTime().toUnixTime();

				    version(Posix)
				    {
                                    de = DirEntry(copy_to_path);
                                    disk_usage = de.statBuf.st_blocks*512;
				    }
				    else version(Windows)
				    {
				    disk_usage = getFileSizeOnDisk(copy_to_path);
				    }
                                    if (disk_usage == last_disk_usage) 
                                    {
                                        the_same_disk_usage_times++;
                                        int number_tries = 5;
                                        if (path.path == cur_path)
                                            number_tries = 500;
                                        if (the_same_disk_usage_times > number_tries)
                                        {
                                            writefln("FILE DOESN'T GROW %s (current=%s), %s", 
                                                    cur_rectsize.disk_usage, disk_usage, copy_to_path);
                                            break;
                                        }
                                    }
                                    else
                                    {
                                        the_same_disk_usage_times = 0;
                                    }
                                    last_disk_usage = disk_usage;

                                    current_rectsize.disk_usage = current_disk_usage+disk_usage;

                                    if (stdtime > (last_measure+10_000_000) || first_measure)
                                    {
                                        if (first_measure)
                                        {
                                            last_measure = stdtime;
                                            first_measure = true;
                                        }
                                        last_measure += 10_000_000;
                                        measurements = measurements ~ (current_rectsize.disk_usage - disk_usage_at_last_measure);

                                        size_t len = measurements.length;
                                        if (len > 20)
                                        {
                                            measurements = measurements[1..$];
                                        }

                                        //writefln("measurements=%s", measurements);

                                        auto sorted = measurements[0..$];
                                        sort!("a < b")(sorted);

                                        long min = sorted[len/5];
                                        long max = sorted[len*4/5];
                                        long avg = sorted[len/2];
                                        //writefln("min=%s, max=%s, avg=%s", min, max, avg);

                                        long max_estimate_end = long.max;
                                        if (min > 0) max_estimate_end = unixtime + (goal_rectsize.disk_usage - current_rectsize.disk_usage)/min;
                                        long min_estimate_end = long.max;
                                        if (max > 0) min_estimate_end = unixtime + (goal_rectsize.disk_usage - current_rectsize.disk_usage)/max;

                                        //writefln("min_estimate_end=%s, max_estimate_end=%s, estimate_end=%s", min_estimate_end, max_estimate_end, estimate_end);
                                        long maxmin = max_estimate_end-min_estimate_end;
                                        //min_estimate_end -= maxmin/2;
                                        //max_estimate_end += maxmin/2;
                                        if (min_estimate_end < unixtime) min_estimate_end = unixtime;

                                        //writefln("Extended unixtime=%s, min_estimate_end=%s, max_estimate_end=%s, estimate_end=%s", unixtime, min_estimate_end, max_estimate_end, estimate_end);

                                        if (estimate_end > max_estimate_end || estimate_end < min_estimate_end)
                                        {
                                            estimate_end = long.max;
                                            if (avg > 0) estimate_end = unixtime + (goal_rectsize.disk_usage - current_rectsize.disk_usage)/avg;
                                            //writefln("new estimate_end=%s", estimate_end);
                                        }

                                        int progress = 0;
                                        if ((goal_rectsize.disk_usage - disk_usage_at_start) > 0) 
                                            progress = cast(int)(10000*(current_rectsize.disk_usage - disk_usage_at_start)/(goal_rectsize.disk_usage - disk_usage_at_start));
                                        if (progress >= 10000)
                                            progress = 9999;
                                        update_progress(cgs, copy_to_mnt, 
                                                rsync_line.idup(),
                                                estimate_end,
                                                progress // from 0 tlll 10000
                                                );

                                        disk_usage_at_last_measure = current_rectsize.disk_usage;
                                    }

                                    if (disk_usage < cur_rectsize.disk_usage)
                                    {
                                        writefln("%s < %s", disk_usage, cur_rectsize.disk_usage);
                                        cgs.commit();
                                        cgs.recommit();
                                        Thread.sleep( dur!("msecs")( 200 ) );
                                    }
                                }
                                while (disk_usage < cur_rectsize.disk_usage);

                                current_rectsize.disk_usage = current_disk_usage + cur_rectsize.disk_usage;
                            }
                            else if (!de.isSymlink())
                            {
				version(Posix)
				{
                                de = DirEntry(cur_path);
                                disk_usage = de.statBuf.st_blocks*512;
				}
				else version(Windows)
				{
				disk_usage = getFileSizeOnDisk(cur_path);
				}
                                current_rectsize.disk_usage = current_disk_usage + disk_usage;
                                /*writefln("Dir or Symlink. path %s, size %s", rsync_line,
                                        disk_usage);*/
                            }
                        }
                        catch (Exception e)
                        {
                            error = 1;
                        }
                        tries--;
                        if (error)
                        {
                            Thread.sleep( dur!("msecs")( 200 ) );
                        }
                    }
                    while (error && tries > 0);

                    if (tries == 0)
                    {
                        writefln("Can't open path %s - %s, size %s", cur_path, copy_to_path,
                                cur_rectsize.disk_usage);
                    }

                    /*writefln("path %s, size %s, current %s", rsync_line,
                            cur_rectsize.disk_usage, disk_usage);*/

                    /*writefln("current_rectsize.disk_usage=%s, goal_rectsize.disk_usage=%s",
                            current_rectsize.disk_usage,
                            goal_rectsize.disk_usage);*/
                }
            }
        }
    }

    update_progress(cgs, copy_to_mnt, 
            "",
            Clock.currTime().toUnixTime(),
            10000);

    return num_errors;
}

private void
start_copy_paths(shared LsblkInfo[string] lsblk, immutable string[] paths, string copy_to, bool remove, Tid tid)
{
    writefln("Start copying %s, remove=%s", paths, remove);

    try {
        FMGlobalState cgs = new FMGlobalState();
        scope(exit)
        {
            destroy(cgs);
        }

        cgs.lsblk = to!(LsblkInfo[string])(lsblk);

        string[] paths_dup = paths.dup;
        sort!("a < b")(paths_dup);
        foreach(path; paths_dup)
        {
            copy_path(cgs, PathMnt(cgs.lsblk, path), copy_to, remove, tid);
            cgs.commit();
        }
    } catch (shared(Throwable) exc) {
        send(tid, exc);
    }

    writefln("Finish copying %s", paths);
    send(tid, thisTid);
}

int copy_paths(GlobalState gs, immutable string[] paths, string copy_to, bool remove)
{
    foreach(tid, paths2; gs.copiers)
    {
        if (paths2 == paths)
        {
            writefln("Copy %s already in work", paths);
            return 0;
        }
    }

    shared LsblkInfo[string] lsblk = to!(shared LsblkInfo[string])(gs.lsblk);
    auto tid = spawn(&start_copy_paths, lsblk, paths, copy_to, remove, thisTid);
    gs.copiers[tid] = paths.dup();
    return 0;
}

void check_copiers(GlobalState gs)
{
    // Look check_scanners
}

