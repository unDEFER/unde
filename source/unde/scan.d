module unde.scan;

import unde.global_state;
import unde.lsblk;
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
import std.algorithm.searching;
import std.utf;
import std.concurrency;
import core.time;
import core.exception;
import std.process;
import std.regex;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;
import derelict.sdl2.image;

import unde.lib;

import std.file;

version(Windows)
{
import core.sys.windows.windows;
import core.stdc.time;
alias ulong ulong_t;
}

immutable DRect drect_zero = DRect(0, 0, 0, 0);

private void
remove_deleted_files(ScannerGlobalState sgs, string mnt, string name1, string name2)
{
    if (sgs.copy_map.length > 0) return;
    Dbc cursor = sgs.db_map.cursor(sgs.txn, 0);
    scope(exit) cursor.close();

    LsblkInfo info = sgs.lsblk[mnt];
    string subpath = .subpath(name1, mnt);
    string path0 = info.uuid ~ subpath.replace(SL, "\0");

    string subpath2 = .subpath(name2, mnt);
    string path02 = info.uuid ~ subpath2.replace(SL, "\0");

    Dbt key = path0;
    Dbt data;
    auto res = cursor.get(&key, &data, DB_SET_RANGE);
    if (res != 0) return;

    int removed = 0;    
    do
    {
        string path = key.to!string();
        if (path < path02)
        {
            DirEntry de;
            string pathfile = path.replace("\0", SL);
            //writefln("Remove %s", pathfile);

            pathfile = mnt ~ pathfile[pathfile.indexOf(SL)..$];
            if (exists(pathfile))
            {
                writeln(pathfile ~ " exists.\nRemoving from " ~ info.uuid ~ subpath ~ " till " ~ info.uuid ~ subpath2);
            }

            // FYI: proc system sometimes make not listable but existing
            // directories
            //assert (!exists(pathfile), pathfile ~ " exists.\nRemoving from " ~ info.uuid ~ subpath ~ " till " ~ info.uuid ~ subpath2);
            removed++;
            cursor.del();
            sgs.OIT++;
            if (sgs.OIT > 100)
            {
                cursor.close();
                sgs.recommit();
                cursor = sgs.db_map.cursor(sgs.txn, 0);
                res = cursor.get(&key, &data, DB_SET_RANGE);
                if (res != 0) return;
            }
        }
        else break;
    }
    while (cursor.get(&key, &data, DB_NEXT) == 0);

    /*
    if (removed > 0)
        writefln("%s items removed from %s to %s", removed, info.uuid ~ subpath, info.uuid ~ subpath2);
    */
}

private void
copy_map_of_path(ScannerGlobalState sgs, PathMnt path,
        PathMnt copy_to_mnt, bool move)
{
    string copy_to0 = copy_to_mnt.get_key(sgs.lsblk);

    Dbc cursor = sgs.db_map.cursor(sgs.txn, 0);
    scope(exit) cursor.close();

    string path0 = path.get_key(sgs.lsblk);
    Dbt key = path0;
    Dbt data;
    auto res = cursor.get(&key, &data, DB_SET_RANGE);
    if (res != 0) return;

    int removed = 0;    
    writefln("Start copy map %s to %s", path, copy_to_mnt);
    do
    {
        receive_copy_map(sgs);
        string path1 = key.to!string();
        if (path1.startsWith(path0))
        {
            string path2 = path1.replace(path0, copy_to0);
            Dbt key2 = path2;
            //writefln("Write %s", path2.replace("\0", SL));
            res = sgs.db_map.put(sgs.txn, &key2, &data);
            if (res != 0)
                throw new Exception("Path info to map-db not written");
            sgs.OIT++;
            if (sgs.OIT > 100)
            {
                cursor.close();
                sgs.recommit();
                cursor = sgs.db_map.cursor(sgs.txn, 0);
                res = cursor.get(&key, &data, DB_SET_RANGE);
                if (res != 0) return;
            }
        }
        else break;
        if (move)
        {
            cursor.del();
            sgs.OIT++;
        }
    }
    while (cursor.get(&key, &data, DB_NEXT) == 0);
    writefln("End copy map");
}

private void
fixsizes_for_parents(ScannerGlobalState sgs, PathMnt path,
        long dsize, long ddisk_usage, long dfiles)
{
    string path0 = path.get_key(sgs.lsblk);
    path0 = path0[0..path0.lastIndexOf("\0")];
    while(path0.lastIndexOf("\0") >= 0)
    {
        Dbt key = path0;
        Dbt data;
        auto res = sgs.db_map.get(sgs.txn, &key, &data);
        if (res == 0)
        {
            RectSize rectsize = data.to!(RectSize);

            //writef("%s diskusage = %s + %s", path0.replace("\0",SL), rectsize.disk_usage, ddisk_usage);
            rectsize.size += dsize;
            rectsize.disk_usage += ddisk_usage;
            rectsize.files += dfiles;
            //writefln("= %s", rectsize.disk_usage);

            data = rectsize;
            res = sgs.db_map.put(sgs.txn, &key, &data);
            if (res != 0)
                throw new Exception("Path info to map-db not written");
            sgs.OIT++;
            sgs.recommit();
        }

        if (path0.lastIndexOf("\0") == path0.length-1)
        {
            path0 = "";
        }
        else
        {
            path0 = path0[0..path0.lastIndexOf("\0")];
            if (path0.lastIndexOf("\0") < 0)
            {
                path0 ~= "\0";
            }
        }
    }
}

private void
receive_copy_map(ScannerGlobalState sgs)
{
    receiveTimeout( 0.seconds, 
            (string path, string copy_to_mnt, bool move)
            {
                auto copymapinfo = CopyMapInfo(path, null, move, thisTid);
                sgs.copy_map[copy_to_mnt] = copymapinfo;
                writefln("scan.thread send(%s, %s, %s, %s)",
                        path, copy_to_mnt, move, MsgState.Received);
                send(sgs.parent_tid, thisTid, path, copy_to_mnt, move, MsgState.Received);
            }
        );
}

private RectSize
scan_direntry(ScannerGlobalState sgs, PathMnt path,
        DRect rect, bool recursively, ref bool cont, int rescan, bool root)
{
    sgs.recommit();

	//writefln("%s", path);
    receive_copy_map(sgs);

    bool orig_cont = cont;
    bool fully_scanned = false;
    string path0 = path.get_key(sgs.lsblk);
    Dbt key = path0;
    Dbt data;
    RectSize rectsize;
    RectSize rectsize_before;

    if (cont || rescan)
    {
        auto res = sgs.db_map.get(sgs.txn, &key, &data);
        if (res == 0)
        {
            rectsize = data.to!(RectSize);

            if (rectsize.size >= 0)
            {
                fully_scanned = true;
                rectsize = rectsize;
            }
        }
        if (sgs.one_level) fully_scanned = true;
	if (cont && !fully_scanned) writefln("Continue from %s", path);
        if (!fully_scanned) cont = false;
    }
    rectsize_before = rectsize;

        //writefln("path=%s in copy_map=%s", path, sgs.copy_map);
    if (path in sgs.copy_map)
    {
        //writefln("scan.thread Found path=%s", path);
        PathMnt copy_to_mnt = PathMnt(sgs.lsblk, path);
        PathMnt path_from_mnt = PathMnt(sgs.lsblk, sgs.copy_map[path].path);

        string path_from0 = path_from_mnt.get_key(sgs.lsblk);
        Dbt key2 = path_from0;
        Dbt data2;
        RectSize rectsize2;

        auto res = sgs.db_map.get(sgs.txn, &key2, &data2);
        //writefln("scan.thread GET %s", path_from0.replace("\0", SL));
        if (res == 0)
        {
            //writefln("GOT");
            rectsize2 = data2.to!(RectSize);

            rectsize.size = rectsize2.size;
            rectsize.disk_usage = rectsize2.disk_usage;
            rectsize.mtime = rectsize2.mtime;
            rectsize.mtime_nsec = rectsize2.mtime_nsec;
            rectsize.files = rectsize2.files;
        }

        if (rect.x > 0)
            rectsize.rect_by_name = rect;

        data = rectsize;
        res = sgs.db_map.put(sgs.txn, &key, &data);
        if (res != 0)
            throw new Exception("Path info to map-db not written");
        sgs.OIT++;

        path_from_mnt._next = path_from_mnt._next ~ SL;
        copy_to_mnt._next = copy_to_mnt._next ~ SL;

        copy_map_of_path(sgs, path_from_mnt, copy_to_mnt, sgs.copy_map[path].move);
        /*writefln("scan.thread send to %s - %s, %s, %s, used", 
                sgs.parent_tid, thisTid, sgs.copy_map[path].path, path);*/
        send(sgs.parent_tid, thisTid, sgs.copy_map[path].path, path._next, sgs.copy_map[path].move, MsgState.Used);
        sgs.copy_map.remove(path);

        if (root)
        {
            long dsize = rectsize.size - rectsize_before.size;
            long ddisk_usage = rectsize.disk_usage - rectsize_before.disk_usage;
            long dfiles = rectsize.files - rectsize_before.files;

            //writefln("%s - size=%s, disk_usage=%s, dfiles=%s",
            //      path, dsize, ddisk_usage, dfiles);

            fixsizes_for_parents(sgs, path,
                    dsize, ddisk_usage, dfiles);
        }

        return rectsize;
    }
    
    //writefln("%s: %s", path, fully_scanned);

    DRect rescan_rect;
    if (rescan > 0 ? rescan == 1 || rescan == 2 && !fully_scanned : !cont)
    {
        if (rescan != 1)
            rectsize = RectSize(rect, drect_zero, drect_zero, -1);
        data = rectsize;
        auto res = sgs.db_map.put(sgs.txn, &key, &data);
        if (res != 0)
            throw new Exception("Path info to map-db not written");
        sgs.OIT++;

        rescan_rect = rectsize.rect_by_name;
        rectsize = walk(sgs, path, recursively, orig_cont, 
                rescan == 1 ? 2 : 0);
    }

    if (path.path == path._next && !(rescan || !cont))
    {
        rectsize.rect_by_size = rect;
        rectsize.rect_by_time = rect;
        rescan = 2;
    }

    if (rescan || !cont)
    {
        if (rescan == 1)
            rectsize.rect_by_name = rescan_rect;
        else
            rectsize.rect_by_name = rect;
        data = rectsize;
        auto res = sgs.db_map.put(sgs.txn, &key, &data);
        if (res != 0)
            throw new Exception("Path info to map-db not written");
        sgs.OIT++;
    }

    if (root)
    {
        long dsize = rectsize.size - rectsize_before.size;
        long ddisk_usage = rectsize.disk_usage - rectsize_before.disk_usage;
        long dfiles = rectsize.files - rectsize_before.files;

        //writefln("%s - size=%s, disk_usage=%s, dfiles=%s",
        //      path, dsize, ddisk_usage, dfiles);

        fixsizes_for_parents(sgs, path,
                dsize, ddisk_usage, dfiles);
    }

    return rectsize;
}

public void
calculate_rect(DRect full_rect, out DRect rect, const(long)[] coords, size_t lev)
{
    if (lev == 0)
    {
        rect.w = full_rect.w/3;
        rect.h = full_rect.h/3;
        rect.x = full_rect.x + rect.w;
        rect.y = full_rect.y + rect.h;
    }
    else
    {
        rect.w = full_rect.w/3/exp2(lev);
        rect.h = full_rect.h/3/exp2(lev);

        rect.x = full_rect.x + full_rect.w/3;
        rect.y = full_rect.y + full_rect.w/3/exp2(lev);

        /* right, down, left, up, right2 */
        long r = 2, dlu = 3, r2 = 1;
        foreach (j; 1..lev)
        {
            r = r*2+2;
            dlu = dlu*2+3;
            r2 = r2*2+1;
        }

        // right
        if (coords[lev] < r)
        {
            rect.x += full_rect.w/3/exp2(lev) * coords[lev];
        }
        else
        {
            rect.x += full_rect.w/3/exp2(lev) * r;

            // down
            if (coords[lev] < r+dlu)
            {
                rect.y += full_rect.w/3/exp2(lev) * (coords[lev]-r);
            }
            else
            {
                rect.y += full_rect.w/3/exp2(lev) * dlu;

                // left
                if (coords[lev] < r+2*dlu)
                {
                    rect.x -= full_rect.w/3/exp2(lev) * (coords[lev]-r-dlu);
                }
                else
                {
                    rect.x -= full_rect.w/3/exp2(lev) * dlu;

                    // up
                    if (coords[lev] < r+3*dlu)
                    {
                        rect.y -= full_rect.w/3/exp2(lev) * (coords[lev]-r-2*dlu);
                    }
                    else
                    {
                        rect.y -= full_rect.w/3/exp2(lev) * dlu;

                        // right
                        if (coords[lev] < r+3*dlu+r2)
                        {
                            rect.x += full_rect.w/3/exp2(lev) * (coords[lev]-r-3*dlu);
                        }
                        else
                        {
                            rect.x += full_rect.w/3/exp2(lev) * dlu;
                        }
                    }
                }
            }
        }
    }
}

public void
calculate_coords(long[] coords, ref size_t lev, ref long i,
        int levels, immutable long entries_on_last_level)
{
    coords[lev]++;
    i++;
    lev++;
    /*foreach(j; 1..lev)
    {
        writef("%s, ", coords[j]);
    }
    writefln("");
    writefln("coords[levels]=%s, entries_on_last_level=%s", coords[levels], entries_on_last_level);
    */
    if (lev > levels || coords[levels] >= entries_on_last_level && lev >= levels)
    {
        bool repeat = false;
        do
        {
            lev--;
            if (lev == 1) break;

            /* right, down, left, up */
            long r = 4, rd = 5, d = 4, r1 = 0;
            foreach (j; 2..lev)
            {
                r = r*2+4;
                d = d*2+8;
                r1 = r1*2+4;
            }
            //writefln("lev=%s, r=%s, d=%s, r1=%s", lev, r, d, r1);

            long c = coords[lev];

            // right
            if (c <= r)
            {
                repeat = ((c%2)==0);
            }
            else
            {
                // right, down
                c -= r;
                if (c <= rd)
                {
                    repeat = (c == 5);
                }
                else
                {
                    // down
                    c -= rd;
                    if (c <= d)
                    {
                        repeat = ((c%2)==0);
                    }
                    else
                    {
                        // down, left
                        c -= d;
                        if (c <= rd)
                        {
                            repeat = (c == 5);
                        }
                        else
                        {
                            // left
                            c -= rd;
                            if (c <= d)
                            {
                                repeat = ((c%2)==0);
                            }
                            else
                            {
                                // left, up
                                c -= d;
                                if (c <= rd)
                                {
                                    repeat = (c == 5);
                                }
                                else
                                {
                                    // up
                                    c -= rd;
                                    if (c <= d)
                                    {
                                        repeat = ((c%2)==0);
                                    }
                                    else
                                    {
                                        // up, right
                                        c -= d;
                                        if (c <= rd)
                                        {
                                            repeat = (c == 5);
                                        }
                                        else
                                        {
                                            // right
                                            c -= rd;
                                            if (c <= r1)
                                            {
                                                repeat = ((c%2)==0);
                                            }
                                            else
                                            {
                                                assert(false);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } 
        while(repeat);

        if (coords[levels] >= entries_on_last_level && lev >= levels)
            lev--;
    }
}

private RectSize
rectsize_from_exception(Exception e)
{
    auto rectsize = RectSize();
    rectsize.msg_color = 0x80808000; //ARGB
    rectsize.msg = to_char_array!80(strip_error(e.msg));
    return rectsize;
}

version (Windows)
{
ulong getFileSizeOnDisk(string path)
{
	DWORD high_size;
	auto size = GetCompressedFileSize(path.toUTF16z(), &high_size);
	if (size == INVALID_FILE_SIZE)
	{
		throw new Exception("GetCompressedFileSize: "~GetErrorMessage());
	}

	return (cast(ulong)high_size << 32) | size; 
}

ulong getFileSize(string path)
{
	HANDLE file = CreateFile(
			path.toUTF16z(),
			GENERIC_READ,
			7,
			null,
			OPEN_EXISTING,
			FILE_FLAG_BACKUP_SEMANTICS,
			null
			);
	if (file == INVALID_HANDLE_VALUE)
	{
		writefln("CreateFile %s: %s", path, GetErrorMessage());
		return 0;
	}

	DWORD high_size;
	auto size = GetFileSize(file, &high_size);
	if (size == INVALID_FILE_SIZE)
	{
		CloseHandle(file);
		throw new Exception("GetFileSize: "~GetErrorMessage());
	}

	auto res = CloseHandle(file);
	if (!res)
	{
		throw new Exception("CloseHandle: "~GetErrorMessage());
	}

	return (cast(ulong)high_size << 32) | size; 
}

time_t[2] getFileModTime(string path)
{
	HANDLE file = CreateFile(
			path.toUTF16z(),
			GENERIC_READ,
			7,
			null,
			OPEN_EXISTING,
			FILE_FLAG_BACKUP_SEMANTICS,
			null
			);
	if (file == INVALID_HANDLE_VALUE)
	{
		writefln("CreateFile %s: %s", path, GetErrorMessage());
		return [0, 0];
	}

	FILETIME filetime;
	auto res = GetFileTime(file, null, null, &filetime);
	if (!res)
	{
		CloseHandle(file);
		throw new Exception("GetFileTime: "~GetErrorMessage());
	}

	res = CloseHandle(file);
	if (!res)
	{
		throw new Exception("CloseHandle: "~GetErrorMessage());
	}

	ulong windows_time = (cast(ulong)filetime.dwHighDateTime << 32) | filetime.dwLowDateTime;

	enum WINDOWS_TICK=10000000;
	enum SEC_TO_UNIX_EPOCH=11644473600;

	return [ cast(time_t)(windows_time / WINDOWS_TICK - SEC_TO_UNIX_EPOCH),
		  cast(time_t)(windows_time % WINDOWS_TICK) ];
}

}

private RectSize
walk(ScannerGlobalState sgs, PathMnt path,
        bool recursively, bool cont, int rescan)
{
    sgs.recommit();
    DRect full_rect = DRect(0, 0, 1024*1024, 1024*1024);
    // receive any messages and exits on exits of parent
    receiveTimeout( 0.seconds, 
            (OwnerTerminated ot) {
                writefln("Abort scanning due stopping parent");
                sgs.finish = true;
            } );

    if (sgs.finish)
        return RectSize(drect_zero, drect_zero, drect_zero, -1);

    DirEntry de;
    try
    {
        de = DirEntry(path);
    }
    catch (FileException e)
    {
        return rectsize_from_exception(e);
    }

    if (path in sgs.lsblk)
    {
        //writefln("path=%s, recursively=%s, root=%s", path,
        //        recursively, path.path == path);
        if (!recursively && path.path != path)
        {
            //writefln("EXIT!");
            return RectSize();
        }
    }

    bool np = (path._next != path.path);

    try
    {
        path.update(sgs.lsblk);
    }
    catch (Exception e)
    {
        return rectsize_from_exception(e);
    }

    if (path in sgs.lsblk && np)
    {
        DRect rect = DRect(0, 0, 1024*1024, 1024*1024);
        scan_direntry(sgs, path, rect, recursively, cont, rescan, false);
	version(Posix)
	{
        return RectSize(drect_zero, drect_zero, drect_zero, 
                0, de.statBuf.st_blocks*512,
                de.statBuf.st_mtime, de.statBuf.st_mtimensec, 0);
	}
	else version(Windows)
	{
	time_t[2] modtime = getFileModTime(path);
        return RectSize(drect_zero, drect_zero, drect_zero, 
                getFileSize(path), getFileSizeOnDisk(path),
                modtime[0], modtime[1], 0);
	}
    }

    bool isSymlink = false;
    try
    {
        isSymlink = de.isSymlink;
    }
    catch (Exception e)
    {
        return rectsize_from_exception(e);
    }

    if (isSymlink)
    {
        return RectSize(drect_zero, drect_zero, drect_zero, 0, 0, 0, 0, 1);
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
        catch (FileException e)
        {
            return rectsize_from_exception(e);
        }

        sort!("a < b")(paths);

        int levels = 0;
        long l = paths.length;
        /*if (l > 0)
        {
            l--;
        }*/
        for (long i=12; i < l; i=i*2+12)
        {
            l -= i;
            levels++;
        }
        if (l > 0) levels++;

        immutable long entries_on_last_level = l;

        RectSize[string] rect_sizes;

        //writefln("levels = %s", levels);
        long[] coords = new long[levels+1];
	version(Posix)
	{
        RectSize full_size = RectSize(drect_zero, drect_zero, drect_zero, 
                0, de.statBuf.st_blocks*512,
                de.statBuf.st_mtime, de.statBuf.st_mtimensec, 0);
	}
	else version(Windows)
	{
	time_t[2] modtime = getFileModTime(path);
        RectSize full_size = RectSize(drect_zero, drect_zero, drect_zero, 
                getFileSize(path), getFileSizeOnDisk(path),
                modtime[0], modtime[1], 0);
	}
        long i = 0;
        size_t lev = 1;
        string prev_name = path;
        bool first = true;
        foreach (string name; paths)
        {
            if (name != path)
            {
                DRect rect;
                calculate_rect(full_rect, rect, coords, lev);

                remove_deleted_files(sgs, path.mnt, (first ? 
                            prev_name~"/\x00" : 
                            prev_name~"/\xFF"), name);
                prev_name = name;
                RectSize rect_size = scan_direntry(sgs, path.next(name),
                        rect, recursively, cont, rescan, false);
                if (rect_size.size < 0) return RectSize(drect_zero, drect_zero, drect_zero, -1);
                full_size.size += rect_size.size;
                full_size.disk_usage += rect_size.disk_usage;
                full_size.files += rect_size.files;

                rect_sizes[name] = rect_size;

                calculate_coords(coords, lev, i, levels, entries_on_last_level);
                first = false;
            }
        }

        remove_deleted_files(sgs, path.mnt, prev_name~"/\xFF", path~"/\xFF");
        
        sort!((a, b) => rect_sizes[a].disk_usage > rect_sizes[b].disk_usage ||
                rect_sizes[a].disk_usage == rect_sizes[b].disk_usage && a < b)(paths);
        coords = new long[levels+1];
        i = 0, lev = 1;
        foreach (string name; paths)
        {
            if (name != path)
            {
                DRect rect;
                calculate_rect(full_rect, rect, coords, lev);
                rect_sizes[name].rect_by_size = rect;
                calculate_coords(coords, lev, i, levels, entries_on_last_level);
            }
        }

        sort!((a, b) => rect_sizes[a].mtime > rect_sizes[b].mtime ||
                rect_sizes[a].mtime == rect_sizes[b].mtime && a < b)(paths);
        coords = new long[levels+1];
        i = 0, lev = 1;
        foreach (string name; paths)
        {
            if (name != path)
            {
                DRect rect;
                calculate_rect(full_rect, rect, coords, lev);
                rect_sizes[name].rect_by_time = rect;

                path = name;
                string path0 = path.get_key(sgs.lsblk);
                Dbt key = path0;
                Dbt data = rect_sizes[name];
                assert(rect_sizes[name].rect_by_time.w > 0);
                //writefln("WRITE %s - %s", name, rect_sizes[name]);
                auto res = sgs.db_map.put(sgs.txn, &key, &data);
                if (res != 0)
                    throw new Exception("Path info to map-db not written");
                sgs.OIT++;

                calculate_coords(coords, lev, i, levels, entries_on_last_level);
            }
        }


        //writefln("E %s %sx%s, size %d, density %.5f bytes/pix^2", full_rect.path, full_rect.w, full_rect.h, full_rect.size, cast(double)(full_rect.size)/(full_rect.w*full_rect.h));
        return full_size;
    }
    else if (de.isFile)
    {
        try{
	    version(Posix)
	    {
		return RectSize(drect_zero, drect_zero, drect_zero,
				de.size, de.statBuf.st_blocks*512,
				de.statBuf.st_mtime, de.statBuf.st_mtimensec, 1);
	    }
	    else version(Windows)
	    {
		time_t[2] modtime = getFileModTime(path);
		return RectSize(drect_zero, drect_zero, drect_zero, 
			getFileSize(path), getFileSizeOnDisk(path),
			modtime[0], modtime[1], 1);
	    }
        }
        catch (Exception e)
        {
            return RectSize(drect_zero, drect_zero, drect_zero, -1);
        }
    }
    else 
    {
        try
        {
	    version(Posix)
	    {
		return RectSize(drect_zero, drect_zero, drect_zero,
				de.size, de.statBuf.st_blocks*512,
				de.statBuf.st_mtime, de.statBuf.st_mtimensec, 1);
	    }
	    else version(Windows)
	    {
		time_t[2] modtime = getFileModTime(path);
		return RectSize(drect_zero, drect_zero, drect_zero, 
			getFileSize(path), getFileSizeOnDisk(path),
			modtime[0], modtime[1], 1);
	    }
        }
        catch (Exception e)
        {
            return RectSize(drect_zero, drect_zero, drect_zero, -1);
        }
    }
}

private void
scan(shared LsblkInfo[string] lsblk, shared CopyMapInfo[string] copy_map, 
        PathMnt path, bool recursively, bool cont, bool rescan, 
        bool one_level, Tid tid)
{
    ScannerGlobalState sgs = new ScannerGlobalState();
    try {
        scope(exit)
        {
            destroy(sgs);
        }
        sgs.one_level = one_level;
        sgs.lsblk = to!(LsblkInfo[string])(lsblk);
        sgs.copy_map = cast(CopyMapInfo[string])(copy_map);
        sgs.parent_tid = tid;

        DRect rect = DRect(0, 0, 1024*1024, 1024*1024);
        scan_direntry(sgs, path, rect, recursively, cont, rescan?1:0, true);
        sgs.commit();
        receive_copy_map(sgs);
    } catch (DbDeadlockException exc) {
        writefln("Oops! Seems Deadlock..");
        writefln("Scanning %s interrupted unexpectedly", path);
        writefln("Will be continued immediatedly..");
        send(tid, thisTid, path);
        return;
    } catch (shared(Throwable) exc) {
        send(tid, exc);
    }

    writefln("Finish scan %s", path);
    send(tid, thisTid);
}

public int
start_scan(GlobalState gs, PathMnt path)
{
    shared LsblkInfo[string] lsblk = to!(shared LsblkInfo[string])(gs.lsblk);
    shared CopyMapInfo[string] copy_map = cast(shared CopyMapInfo[string])(gs.copy_map);

    writefln("Start scan %s", path);
    auto tid = spawn(&scan, lsblk, copy_map, path, gs.interface_flags[path], false, false, false, thisTid);
    gs.scanners ~= tid;
    return 0;
}

public int
rescan_path(GlobalState gs, PathMnt path)
{
    shared LsblkInfo[string] lsblk = to!(shared LsblkInfo[string])(gs.lsblk);
    shared CopyMapInfo[string] copy_map = cast(shared CopyMapInfo[string])(gs.copy_map.dup);

    if (gs.rescanners.length > 0) return 0;
    if (gs.scanners.length > 0) return 0;
    if (path in gs.rescanners) return 0;

    writefln("Rescan path %s", path);
    auto tid = spawn(&scan, lsblk, copy_map, path, false, false, true, gs.copiers.length > 0, thisTid);
    gs.scanners ~= tid;
    gs.rescanners[path] = tid;
    return 0;
}

public void
check_if_fully_scanned(GlobalState gs, string path)
{
    static bool[string] checked;
    LsblkInfo info = gs.lsblk[path];
    if (info.uuid in checked)
    {
        return;
    }

    string k = info.uuid ~ "\0";
    Dbt key = k;
    Dbt data;
    auto res = gs.db_map.get(null, &key, &data);
    if (res == 0)
    {
        RectSize rectsize;
        rectsize = data.to!(RectSize);

        if (rectsize.rect_by_time.w > 0)
        {
            writefln("Fully scanned %s FS detected (%s)", info.uuid, path);
        }
        else
        {
            writefln("Not fully scanned %s FS detected (%s)", info.uuid, path);
            writefln("Continue scanning");
            shared LsblkInfo[string] lsblk = to!(shared LsblkInfo[string])(gs.lsblk);
            shared CopyMapInfo[string] copy_map = cast(shared CopyMapInfo[string])(gs.copy_map.dup);
            auto tid = spawn(&scan, lsblk, copy_map, PathMnt(gs.lsblk, path), false, true, false, false, thisTid);
            gs.scanners ~= tid;
        }
    }
    else
    {
        writefln("Not started to scan %s FS detected (%s)", info.uuid, path);
    }

    checked[info.uuid] = true;
}

enum MsgState
{
    Send,
    Resent,
    Received,
    Used
}

public void
check_scanners(GlobalState gs)
{
    if (gs.scanners.length > 0 || gs.removers.length > 0 || 
            gs.copiers.length > 0 || gs.movers.length > 0 ||
            gs.changers_rights.length > 0)
    {
        gs.dirty = true;
        receiveTimeout( 0.seconds, 
                (Tid tid, PathMnt path)
                {
                    bool is_scanner;
                    foreach(i, scanner; gs.scanners)
                    {
                        if (scanner == tid)
                        {
                            is_scanner = true;
                            gs.scanners = gs.scanners[0..i]~gs.scanners[i+1..$];
                        }
                    }

                    bool is_rescanner;
                    foreach(path, t; gs.rescanners)
                    {
                        if (t == tid)
                        {
                            is_rescanner = true;
                            gs.rescanners.remove(path);
                            break;
                        }
                    }

                    if (is_scanner)
                    {
                        shared LsblkInfo[string] lsblk = to!(shared LsblkInfo[string])(gs.lsblk);
                        shared CopyMapInfo[string] copy_map = cast(shared CopyMapInfo[string])(gs.copy_map.dup);
                        auto rescanner_tid = spawn(&scan, lsblk, copy_map, path, false, true, false, false, thisTid);
                        gs.scanners ~= rescanner_tid;
                    }
                    else if (is_rescanner)
                    {
                        rescan_path(gs, path);
                    }
                },
                (Tid tid)
                {
                    bool is_scanner;
                    foreach(i, scanner; gs.scanners)
                    {
                        if (scanner == tid)
                        {
                            is_scanner = true;
                            gs.scanners = gs.scanners[0..i]~gs.scanners[i+1..$];
                        }
                    }

                    foreach(path, t; gs.rescanners)
                    {
                        if (t == tid)
                        {
                            is_scanner = true;
                            gs.rescanners.remove(path);
                            break;
                        }
                    }

                    if (is_scanner)
                    {
                        foreach (copy_map_info; gs.copy_map)
                        {
                            if (copy_map_info.sent.remove(tid))
                            {
                                //writefln("main.thread sent-- = %d", copy_map_info.sent.length);

                                if (copy_map_info.sent.length == 0)
                                {
                                    //writefln("main.thread send(resent) to %s (after got finish from %s)", copy_map_info.from, tid);
                                    send(copy_map_info.from, MsgState.Resent);
                                }
                            }
                        }
                    }
                    else if (tid in gs.removers)
                    {
                        string[] paths = gs.removers[tid];
                        bool[string] parents;
                        foreach (path; paths)
                        {
                            if (!exists(path))
                            {
                                gs.selection_hash.remove(path);
                            }
                            string parent = getParent(path);
                            parents[parent] = true;
                        }

                        foreach(parent, t; parents)
                        {
                            rescan_path(gs, PathMnt(gs.lsblk, parent));
                        }

                        calculate_selection_sub(gs);
                        gs.removers.remove(tid);
                    }
                    else if (tid in gs.copiers)
                    {
                        string[] paths = gs.copiers[tid];
                        bool[string] parents;
                        foreach (path; paths)
                        {
                            if (!gs.selection_hash.remove(path))
                            {
                                path = path[0..$-1];
                                if (!gs.selection_hash.remove(path))
                                {
                                    writefln("Can't unselect %s", path);
                                }
                            }
                            string parent = getParent(path);
                            if (parent == "") parent = SL;
                            parents[parent] = true;
                        }

                        calculate_selection_sub(gs);
                        gs.copiers.remove(tid);

                        foreach(parent, t; parents)
                        {
                            rescan_path(gs, PathMnt(gs.lsblk, parent));
                        }
                    }
                    else if (tid in gs.movers)
                    {
                        string[] paths = gs.movers[tid];
                        bool[string] parents;
                        foreach (path; paths)
                        {
                            if (!gs.selection_hash.remove(path))
                            {
                                path = path[0..$-1];
                                if (!exists(path))
                                {
                                    if (!gs.selection_hash.remove(path))
                                    {
                                        writefln("Can't unselect %s", path);
                                    }
                                }
                            }
                            string parent = getParent(path);
                            if (parent == "") parent = SL;
                            parents[parent] = true;
                        }

                        calculate_selection_sub(gs);
                        gs.movers.remove(tid);

                        foreach(parent, t; parents)
                        {
                            rescan_path(gs, PathMnt(gs.lsblk, parent));
                        }
                    }
                    else if (tid in gs.changers_rights)
                    {
                        gs.changers_rights.remove(tid);
                    }
                    else if (tid in gs.commands)
                    {
                        gs.commands.remove(tid);
                    }
                    else
                    {
                        throw new Exception("UNKNOWN TID");
                    }
                },
                (shared(Throwable) exc) 
                { 
                    throw exc; 
                },
                (shared ConsoleMessage smsg)
                {
                    auto msg = cast(ConsoleMessage)(smsg);
                    if (msg.message == "")
                        msg.message = "Oops, empty message";
                    gs.messages ~= msg;
                    writeln(msg.message);
                },
                (Tid from, string path, string copy_to_mnt, bool move, MsgState command)
                {
                    switch(command)
                    {
                        case MsgState.Send:
                            auto copymapinfo = CopyMapInfo(path, null, move, from);
                            gs.copy_map[copy_to_mnt] = copymapinfo;

                            foreach(i, scanner; gs.scanners)
                            {
                                //writefln("main.thread send(%s, %s, %s)", scanner, path, copy_to_mnt);
                                send(scanner, path, copy_to_mnt, move);
                                gs.copy_map[copy_to_mnt].sent[scanner]=true;
                            }

                                //writefln("main.thread sent = %d", gs.copy_map[copy_to_mnt].sent.length);
                            if (gs.copy_map[copy_to_mnt].sent.length == 0)
                            {
                                //writefln("main.thread send(resent) to %s (immidiately)", from);
                                send(from, MsgState.Resent);
                            }
                            //writefln("copymapinfo.from = %s", copymapinfo.from);
                            break;

                        case MsgState.Received:
                            gs.copy_map[copy_to_mnt].sent.remove(from);
                                //writefln("main.thread sent-- = %d", gs.copy_map[copy_to_mnt].sent.length);

                            if (gs.copy_map[copy_to_mnt].sent.length == 0)
                            {
                                //writefln("main.thread send(resent) to %s (after receiving received)", gs.copy_map[copy_to_mnt].from);
                                send(gs.copy_map[copy_to_mnt].from, MsgState.Resent);
                            }
                            break;

                        case MsgState.Used:
                            //writefln("notused: %s", gs.copy_map);
                            if (! gs.copy_map.remove(copy_to_mnt) )
                            {
                                writefln("Oh, no %s not found in copy map info", copy_to_mnt);
                            }
                            break;
                        default:
                            assert(false, "Unexpected MsgState");
                    }
                },
                (Variant v)
                {
                    writefln("main.thread UNKNOWN MESSAGE: %s", v);
                }
            );
    }

    foreach(i, pid; gs.pids )
    {
        auto dmd = tryWait(pid);
        if (dmd.terminated)
            gs.pids = gs.pids[0..i] ~ gs.pids[i+1..$];
    }
}

