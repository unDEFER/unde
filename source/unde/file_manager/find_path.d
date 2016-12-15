module unde.file_manager.find_path;

import unde.global_state;
import unde.lib;
import unde.lsblk;
import unde.path_mnt;
import unde.slash;

import berkeleydb.all;

import std.stdio;
import std.string;

import std.file;

version (Windows)
{
import unde.scan;
}

enum unDE_Path_Finder_Flags {
    Go_Up,
    Go_Down,
    Out,
    Try_Other_Directory
}

private unDE_Path_Finder_Flags
what_to_do_with_path_by_rectangle(GlobalState gs,
        in ref DRect surf_rect, in ref RectSize rectsize,
        in PathMnt path, DRect apply_rect, in SortType sort,
        in int level = 0)
{
    if (level == 0)
    {
        if (rectsize.rect(sort).In(surf_rect))
        {
            if (path > gs.main_path)
            {
                if (gs.path != SL)
                {
                    return unDE_Path_Finder_Flags.Go_Up;
                }
                else
                {
                    return unDE_Path_Finder_Flags.Try_Other_Directory;
                }
            }
        }
    }

    /*writefln("!%s", path);
    writefln("R %s, %s, %s, %s", rectsize.rect(sort).x,
            rectsize.rect(sort).x+rectsize.rect(sort).w,
            rectsize.rect(sort).y,
            rectsize.rect(sort).y+rectsize.rect(sort).h);
    writefln("S %s, %s, %s, %s", surf_rect.x, surf_rect.x+surf_rect.w,
            surf_rect.y, surf_rect.y+surf_rect.h);*/

    if (surf_rect.In(rectsize.rect(sort)))
    {
        gs.path = path;
        gs.apply_rect = apply_rect;
        gs.sort = sort;
        //writefln("path=%s, apply_rect=%s, sort=%s",
        //        gs.path, gs.apply_rect, gs.sort);
    }

    //writefln("rectsize=%s, surf_rect=%s", rectsize.rect(sort), surf_rect);
    if (rectsize.rect(sort).In(surf_rect))
        return unDE_Path_Finder_Flags.Out;

    if (rectsize.rect(sort).NotIntersect(surf_rect))
        return unDE_Path_Finder_Flags.Try_Other_Directory;

    return unDE_Path_Finder_Flags.Go_Down;
}

version(Windows)
{
public DRect
get_drect_of_drives(GlobalState gs, string drive)
{
	DRect full_rect = DRect(0, 0, 1024*1024, 1024*1024);
	RectSize rectsize = RectSize(full_rect, full_rect, full_rect);

	int ret = 0;

	string[] paths;

	foreach(char c; 'A'..'Z'+1)
	{
		string disk = c ~ ":";
		if ( disk in gs.lsblk )
		{
			paths ~= disk;
		}
	}

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

	//RectSize[string] rect_sizes;

	//writefln("levels = %s", levels);
	long[] coords = new long[levels+1];
	long i = 0;
	size_t lev = 1;
	bool first = true;
	foreach (string name; paths)
	{
		DRect rect;
		calculate_rect(full_rect, rect, coords, lev);

		if (name == drive) return rect;

		calculate_coords(coords, lev, i, levels, entries_on_last_level);
		first = false;
	}

	return full_rect;
}
}

/* EN: This function make selection of directory by surface rectangle
   So gs.path must specify the most deep directory which still
   include surface rectangle.

   RU: Эта функция выбирает директорию в соответствии с прямоугольником,
   который занимает surface. После выполнения этой функции gs.path
   должен указывать на самую глубокую директорию которая ещё включает
   прямоугольник surface.
  */
unDE_Path_Finder_Flags
find_path(GlobalState gs, DbTxn txn, CoordinatesPlusScale surf, PathMnt path, 
        DRect apply_rect, SortType sort = SortType.ByName, 
        in int level = 0)
{
    DRect surf_rect = surf.getRect();

go_up:
    bool up = false;
    Dbt key, data;

    DirEntry de;
    try
    {
        de = DirEntry(path);
    }
    catch (FileException e)
    {
        return unDE_Path_Finder_Flags.Try_Other_Directory;
    }

    if (path in gs.lsblk)
    {
        string path0 = path.get_key(gs.lsblk);
        key = path0;
        auto res = gs.db_map.get(txn, &key, &data);
        if (res == 0)
        {
            RectSize rectsize;
            rectsize = data.to!(RectSize);
            apply_rect = rectsize.rect(sort).apply(apply_rect);
        }
	else
	{
		version(Windows)
		{
			if (path.length == 2)
			{
				DRect rect = get_drect_of_drives(gs, path);
				apply_rect = rect.apply(apply_rect);
			}
		}

		{
		    // TODO: Created mount point, rescan up path
		}
	}
    }

    try
    {
        path.update(gs.lsblk);
    }
    catch (Exception e)
    {
        return unDE_Path_Finder_Flags.Out;
    }

    string path0 = path.get_key(gs.lsblk);
    key = path0;
    auto res = gs.db_map.get(txn, &key, &data);
    version(Windows)
    {
    if (path == SL) res = 0;
    }

    if (res == 0)
    {
        up = false;
        RectSize rectsize;
	version(Windows)
	{
		if (path == SL) 
		{
			DRect full_rect = DRect(0, 0, 1024*1024, 1024*1024);
			rectsize = RectSize(full_rect, full_rect, full_rect);
		}
		else
			rectsize = data.to!(RectSize);
	}
	else
	{
		rectsize = data.to!(RectSize);
	}
        rectsize.rect(sort) = rectsize.rect(sort).apply(apply_rect);
        auto wtdwpbr = what_to_do_with_path_by_rectangle(gs, surf_rect,
                    rectsize, path, apply_rect, sort, level);
        //writefln("%s - %s", path, wtdwpbr);
        final switch (wtdwpbr)
        {
            case unDE_Path_Finder_Flags.Go_Up:
                path = gs.path = PathMnt(SL);
                apply_rect = gs.apply_rect = DRect(0, 0, 1024*1024, 1024*1024);
                gs.sort = SortType.ByName;
                goto go_up;

            case unDE_Path_Finder_Flags.Go_Down:
                if (!de.isSymlink && de.isDir)
                {
                    string[] paths;

                    try
                    {
			    //writefln("Go Down?");
			bool done = false;
		        version(Windows)
		        {
			    if (path == SL) 
			    {
			    //writefln("This way?");
				foreach(char c; 'A'..'Z'+1)
				{
				    string name = c ~ ":";
				    if ( name in gs.lsblk )
				    {
					auto r = find_path(gs, txn, surf, path.next(name),  
						rectsize.rect(sort), rectsize.sort, level+1);
					if (r == unDE_Path_Finder_Flags.Out) return r;
				    }
				}
				done = true;
			    }
			}

			if (!done)
			{
			    //writefln("This way!");
			    foreach (string name;
			            dirEntries(path, SpanMode.shallow))
			    {
				auto r = find_path(gs, txn, surf, path.next(name),  
				        rectsize.rect(sort), rectsize.sort, level+1);
				if (r == unDE_Path_Finder_Flags.Out) return r;
			    }
			}
                    } catch (FileException e)
                    {
                    }
                }
                break;

            case unDE_Path_Finder_Flags.Out:
                if (level == 0 && path != SL)
                    goto case unDE_Path_Finder_Flags.Go_Up;
                return unDE_Path_Finder_Flags.Out;

            case unDE_Path_Finder_Flags.Try_Other_Directory:
                if (level == 0 && path != SL)
                    goto case unDE_Path_Finder_Flags.Go_Up;
                return unDE_Path_Finder_Flags.Try_Other_Directory;
        }
    }
    else
    {
        //throw new Exception("No " ~ path ~ " entry");
    }

    return unDE_Path_Finder_Flags.Try_Other_Directory;
}
