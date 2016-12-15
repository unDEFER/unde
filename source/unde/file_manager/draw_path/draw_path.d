module unde.file_manager.draw_path.draw_path;

import unde.global_state;
import unde.lib;
import unde.lsblk;
import unde.scan;
import unde.clickable;
import unde.file_manager.draw_path.draw_elements;
import unde.file_manager.change_rights;
import unde.path_mnt;
import unde.viewers.image_viewer.lib;
import unde.viewers.text_viewer.lib;
import unde.slash;

import berkeleydb.all;
import core.thread;

import derelict.sdl2.sdl;

import std.string;
import std.format;
import std.conv;
import std.stdio;
import std.datetime;
import std.regex;
import std.process;
import std.utf;

import core.stdc.string;
import core.stdc.errno;

import std.file;
import core.sys.posix.sys.stat;

version (Windows)
{
import unde.scan;
}

private void
calculate_parent_animation_info(GlobalState gs, ref RectSize rectsize,
        SortType sort,
        ref SDL_Rect sdl_rect,
        ref bool calculated,
        ref CoordinatesPlusScale screen)
{
    sdl_rect = rectsize.rect(sort).to_screen(screen);

    sdl_rect.x = sdl_rect.x+sdl_rect.w/3;
    sdl_rect.y = sdl_rect.y+sdl_rect.h/3;
    sdl_rect.w /= 3;
    sdl_rect.h /= 3;

    calculated = true;
}

private void
calculate_directory_animation_info(GlobalState gs, ref RectSize rectsize,
        SortType sort,
        ref SDL_Rect sdl_rect,
        ref bool calculated,
        ref CoordinatesPlusScale screen)
{
    sdl_rect = rectsize.rect(sort).to_screen(screen);
    calculated = true;
}

private void
calculate_animation_info(GlobalState gs, ref RectSize rectsize,
        string path,
        SortType sort)
{
    foreach (ref animation_info; gs.animation_info)
    {
        if ( animation_info.parent == path && !animation_info.from_calculated && 
                (animation_info.type == NameType.CreateDirectory ||
                 (animation_info.type == NameType.Copy || 
                  animation_info.type == NameType.Move) && animation_info.stage == 1) )
        {
            calculate_parent_animation_info(gs, rectsize,
                    sort,
                    animation_info.from,
                    animation_info.from_calculated,
                    gs.screen);
        }
        if ( animation_info.parent == path && !animation_info.to_calculated && 
                (animation_info.type == NameType.Copy ||
                 animation_info.type == NameType.Move) &&
                animation_info.stage == 0 )
        {
            calculate_parent_animation_info(gs, rectsize,
                    sort,
                    animation_info.to,
                    animation_info.to_calculated,
                    gs.screen);
        }
    }

    if ( path in gs.animation_info && 
            !gs.animation_info[path].to_calculated &&
            (gs.animation_info[path].type == NameType.CreateDirectory ||
             (gs.animation_info[path].type == NameType.Copy ||
              gs.animation_info[path].type == NameType.Move) &&
             gs.animation_info[path].stage == 1) )
    {
        calculate_directory_animation_info(gs, rectsize,
                sort,
                gs.animation_info[path].to, 
                gs.animation_info[path].to_calculated, 
                gs.screen);
    }

    if ( path in gs.animation_info && 
            !gs.animation_info[path].from_calculated &&
            (gs.animation_info[path].type == NameType.Copy ||
             gs.animation_info[path].type == NameType.Move) &&
            gs.animation_info[path].stage == 0 )
    {
        calculate_directory_animation_info(gs, rectsize,
                sort,
                gs.animation_info[path].from, 
                gs.animation_info[path].from_calculated, 
                gs.screen);
    }
}

private string
size_to_string(ulong size)
{
    string prefix;
    double s;
    if (size <= 1024UL)
    {
        prefix = "";
        s = cast(double)size;
    }
    else if (size <= 1024UL*1024)
    {
        prefix = "Ki";
        s = cast(double)size/1024.0;
    }
    else if (size <= 1024UL*1024*1024)
    {
        prefix = "Mi";
        s = cast(double)size/(1024.0*1024.0);
    }
    else if (size <= 1024UL*1024*1024*1024)
    {
        prefix = "Gi";
        s = cast(double)size/(1024.0*1024.0*1024.0);
    }
    else //if (size <= 1024UL*1024*1024*1024*1024)
    {
        prefix = "Ti";
        s = cast(double)size/(1024.0*1024.0*1024.0*1024.0);
    }

    return format("%.3f %sb", s, prefix);
}

private int
calc_selected_and_draw_blue_rect(GlobalState gs, 
        in string path, in ref SDL_Rect rect)
{
    int selected = 0;
    foreach(sel_path; gs.selection_hash.byKey())
    {
        if (sel_path > path && sel_path.startsWith(path))
            selected++;
    }

    if (selected > 0)
    {
        SDL_Rect dup_rect = rect;
        unDE_RenderFillRect(gs.renderer, &dup_rect, 0x808080FF);
    }

    return selected;
}

private int
draw_fs_info(GlobalState gs,
        in ref SDL_Rect_With_Not_Visible_And_No_Draw rnvnd,
        in PathMnt path,
        in ref LsblkInfo info,
        bool not_scanned,
        SortType sort,
        int line = 0)
{
    SDL_Rect rect = rnvnd.sdl_rect;

    rect.x = rect.x+rect.w/3;
    rect.y = rect.y+rect.h/3;
    rect.w /= 3;
    rect.h /= 3;

    draw_line(gs, format("Name: %s", info.name), 
                0, (line++)*36, 12, rect);
    draw_line(gs, format("Mountpoint: %s", info.mountpoint), 
                0, (line++)*36, 12, rect);
    draw_line(gs, format("Filesystem: %s", info.fstype), 
                0, (line++)*36, 12, rect);
    draw_line(gs, format("Label: %s", info.label), 
                0, (line++)*36, 12, rect);
    draw_line(gs, format("UUID: %s", info.uuid), 
                0, (line++)*36, 12, rect);
    line++;
    draw_line(gs, format("Size: %s", size_to_string(info.size)), 
                0, (line++)*36, 12, rect);
    draw_line(gs, format("Used: %s", size_to_string(info.used)), 
                0, (line++)*36, 12, rect);
    draw_line(gs, format("Available: %s", size_to_string(info.avail)), 
                0, (line++)*36, 12, rect);
    line++;

    if (not_scanned)
    {
        if (path !in gs.interface_flags)
            gs.interface_flags[path] = false;

        draw_line(gs, (gs.interface_flags[path]?"☑":"☐") ~ " Scan all other file systems recursively", 
                    0, (line)*36, 12, rect);

        auto tt = gs.text_viewer.font.get_char_from_cache(
                "☐", 12, SDL_Color(0xFF, 0xFF, 0xFF, 0xFF));

        SDL_Rect dst = SDL_Rect(rect.x, rect.y + (line*36) * rect.h/1024,
                cast(int)(tt.w*rect.w/1024.0/2), cast(int)(tt.h*rect.h/1024.0/2));

        void checkbox_clicked(GlobalState gs, int stage)
        {
            gs.interface_flags[path] = !gs.interface_flags[path];
            gs.dirty = true;
        }

        gs.new_clickable_list.insertFront(new Clickable(gs, dst, &checkbox_clicked));

        line++;
        dst = draw_button(gs, 0, ((line)*36-4), 5*32, 42, rect);

        void button_clicked(GlobalState gs, int stage)
        {
            start_scan(gs, path);
        }

        gs.new_clickable_list.insertFront(new Clickable(gs, dst, &button_clicked));
        draw_line(gs, "  Scan", 0, (line++)*36, 12, rect);
    }

    return line;
}

private void
draw_de_info(GlobalState gs,
        in ref SDL_Rect_With_Not_Visible_And_No_Draw rnvnd,
        in PathMnt path,
        in RectSize rectsize,
        DirEntry de)
{
    SDL_Rect rect = rnvnd.sdl_rect;

    rect.x = rect.x+rect.w/3;
    rect.y = rect.y+rect.h/3;
    rect.w /= 3;
    rect.h /= 3;

    if (rect.w < 256) return;

    int selected = calc_selected_and_draw_blue_rect(gs, path, rect);

    if (rectsize.show_info == InfoType.Progress)
        unDE_RenderFillRect(gs.renderer, &rect, 0x8080FF80);
    else if ( rectsize.msg[0] != char.init && (rectsize.msg_time == 0 || rectsize.msg_time > gs.msg_stamp) )
        unDE_RenderFillRect(gs.renderer, &rect, rectsize.msg_color);

    int line;
    if (path in gs.lsblk)
    {
        line = draw_fs_info(gs, rnvnd, path, gs.lsblk[path], false, rectsize.sort, line);
    }

    if (!de.isSymlink && de.isDir)
    {
        string name = path[path.lastIndexOf(SL)+1..$];
        if (path == SL)
            name = SL;

        draw_line(gs, format("Name: %s", name), 
                    0, (line++)*36, 12, rect);
        draw_line(gs, format("Sorted %s", rectsize.sort),
                    0, (line++)*36, 12, rect);
        draw_line(gs, format("Files: %s", rectsize.files), 
                    0, (line++)*36, 12, rect);
        line++;
    }
    if (!de.isSymlink)
    {
        if ( rectsize.size < 0 )
        {
            draw_line(gs, format("Scanning..."),
                    0, (line++)*36, 12, rect);
        }
        else
        {
            draw_line(gs, format("Size: %s", size_to_string(rectsize.size)), 
                        0, (line++)*36, 12, rect);
            draw_line(gs, format("Disk Usage: %s", size_to_string(rectsize.disk_usage)), 
                        0, (line++)*36, 12, rect);
            version(DigitalMars)
            {
                auto time = SysTime.fromUnixTime(rectsize.mtime);
                draw_line(gs, format("Mod. time: %s", time.toISOExtString()), 
                            0, (line++)*36, 12, rect);
            }
            line++;
	    version (Posix)
	    {
            string access = mode_to_string(de.statBuf.st_mode);
	    }
	    else version (Windows)
	    {
            string access = "N/A";
	    }
            auto access_rect = draw_line(gs, format("Access: "),
                        0, (line)*36, 12, rect);

            foreach (int i, a; access)
            {
                auto tt = gs.text_viewer.font.get_char_from_cache(
                        ""~a, 12, SDL_Color(0xFF, 0xFF, 0xFF, 0xFF));

                SDL_Rect dst = SDL_Rect(access_rect.x + access_rect.w, 
                                        rect.y + (line*36) * rect.h/1024,
                                        cast(int)(tt.w*rect.w/1024.0/2), 
                                        cast(int)(tt.h*rect.h/1024.0/2));
                access_rect.x += dst.w;

                auto r = SDL_RenderCopy(gs.renderer, tt.texture, 
                                            null, &dst);
                if (r < 0)
                {
                    writefln( "Error while render copy (access symbol): %s",
                            SDL_GetError().to!string() );
                }

                auto get_access_clicked(int i)
                {
                    void access_clicked(GlobalState gs, int stage)
                    {
			version(Posix)
			{
                        mode_t new_mode = de.statBuf.st_mode ^ (1 << (11-i));

                        DirOrFile dof = DirOrFile.All;
                        if (i == 5 || i == 8 || i == 11)
                        {
                            if (!de.isSymlink && de.isDir)
                                dof = DirOrFile.Dir;
                            else
                                dof = DirOrFile.File;
                        }

                        bool set = cast(bool)(new_mode & (1 << (11-i)));

                        string[] selection = gs.selection_hash.keys;
                        int res = change_rights(gs, selection.idup(), set, i, dof, gs.interface_flags[path]);

                        if (res == 0)
                        {
                            res = chmod(path.toStringz, new_mode);
                            if (res < 0)
                            {
                                string msg = format("Chmod error: %s", fromStringz(strerror(errno)).idup());
                                gs.messages ~= ConsoleMessage(
                                        SDL_Color(0xFF, 0x00, 0x00, 0xFF),
                                        msg,
                                        SDL_GetTicks()
                                        );
                                writeln(msg);
                            }
                        }
                        gs.dirty = true;
			}
                    }
                    return &access_clicked;
                }

                gs.new_clickable_list.insertFront(new Clickable(gs, dst, get_access_clicked(i)));
            }
            line++;

	    version(Posix)
	    {
            draw_line(gs, format("User: %s", uid_to_name(de.statBuf.st_uid)),
                        0, (line++)*36, 12, rect);
            draw_line(gs, format("Group: %s", gid_to_name(de.statBuf.st_gid)),
                        0, (line++)*36, 12, rect);
            }

            if (path !in gs.interface_flags)
                gs.interface_flags[path] = false;

            auto tt = gs.text_viewer.font.get_char_from_cache(
                    "☐", 12, SDL_Color(0xFF, 0xFF, 0xFF, 0xFF));

            SDL_Rect dst = SDL_Rect(rect.x, rect.y + (line*36) * rect.h/1024,
                    cast(int)(tt.w*rect.w/1024.0/2), cast(int)(tt.h*rect.h/1024.0/2));

            draw_line(gs, format((gs.interface_flags[path]?"☑":"☐")~" Recursively change rights"),
                        0, (line++)*36, 12, rect);

            void checkbox_clicked(GlobalState gs, int stage)
            {
                gs.interface_flags[path] = !gs.interface_flags[path];
                gs.dirty = true;
            }

            gs.new_clickable_list.insertFront(new Clickable(gs, dst, &checkbox_clicked));
        }
    }
    line++;
    if (selected > 0)
        draw_line(gs, format("Selected %d items", selected), 
                    0, (line++)*36, 12, rect);
        line++;

    if (rectsize.show_info == InfoType.Progress)
    {
        draw_line(gs, from_char_array(rectsize.path), 
                    0, (line++)*36, 12, rect);

        draw_line(gs, format("Progress: %.2f %%", cast(double)rectsize.progress/100),
                    0, (line++)*36, 12, rect);

        long estimate_time = rectsize.estimate_end - Clock.currTime().toUnixTime();
        long secs = estimate_time%60;
        long mins = estimate_time/60%60;
        long hours = estimate_time/3600;

        draw_line(gs, format("Estimate Time: %d:%02d:%02d", hours, mins, secs),
                    0, (line++)*36, 12, rect);
    }
    else if (rectsize.msg[0] != char.init && (rectsize.msg_time == 0 || rectsize.msg_time > gs.msg_stamp) )
    {
        draw_line(gs, from_char_array(rectsize.msg), 
                    0, (line++)*36, 12, rect);
    }
}

private void
draw_enter_name(GlobalState gs,
        in ref SDL_Rect_With_Not_Visible_And_No_Draw rnvnd,
        in string path0,
        in RectSize rectsize)
{
    SDL_Rect rect = rnvnd.sdl_rect;

    rect.x = rect.x+rect.w/3;
    rect.y = rect.y+rect.h/3;
    rect.w /= 3;
    rect.h /= 3;

    if (rect.w < 256) return;

    unDE_RenderFillRect(gs.renderer, &rect, 0x80FFFFFF);

    if (gs.current_path !in gs.enter_names)
    {
        switch (rectsize.show_info)
        {
            case InfoType.CreateDirectory:
                gs.enter_names[gs.current_path] = EnterName(NameType.CreateDirectory, "", 0);
                break;
            case InfoType.Copy:
                gs.enter_names[gs.current_path] = EnterName(NameType.Copy, "", 0);
                break;
            case InfoType.Move:
                gs.enter_names[gs.current_path] = EnterName(NameType.Move, "", 0);
                break;
            default:
                assert(false);
        }
        writefln("Not in enter_names %s", gs.current_path);
    }

    with(gs.enter_names[gs.current_path])
    {
        draw_direntry_name(gs, name[0..pos]~"|"~name[pos..$], rnvnd, true);
    }
}

private void
draw_link_info(GlobalState gs,
        in ref SDL_Rect_With_Not_Visible_And_No_Draw rnvnd,
        in string path)
{
    version(Posix)
    {
    SDL_Rect rect = rnvnd.sdl_rect;

    /*rect.x = rect.x+rect.w/3;
    rect.y = rect.y+rect.h/3;
    rect.w /= 3;
    rect.h /= 3;*/

    if (rect.w < 256) return;

    string name = path[path.lastIndexOf(SL)+1..$];
    if (path == SL)
        name = SL;

    int line;
    draw_line(gs, format("Name: %s", name), 
                0, (line++)*36, 12, rect);
    draw_line(gs, format("Link to: %s", readLink(path)), 
            0, (line++)*36, 12, rect);
    }
}

private bool
isSelected(GlobalState gs, in ref RectSize rectsize,
        in string path, SortType sort)
{

    bool selected = false;
    bool full_selected = false;
    
    foreach(i, sel; gs.selection_list)
    {
        string parent = getParent(path);
        string par_from = getParent(sel.from);
        string par_to = getParent(sel.to);

        if (parent == par_from && parent == par_to)
        {
            if (sel.sort == SortType.BySize)
            {
                if (rectsize.disk_usage <= sel.size_from &&
                        rectsize.disk_usage >= sel.size_to &&
                        (rectsize.disk_usage == sel.size_from ?
                         path >= sel.from : 1) &&
                        (rectsize.disk_usage == sel.size_to ?
                         path <= sel.to : 1))
                {
                    if (i < gs.selection_lsof)
                        selected = !selected;
                    full_selected = !full_selected;
                }
            }
            else if (sel.sort == SortType.ByTime)
            {
                if (rectsize.mtime <= sel.mtime_from &&
                        rectsize.mtime >= sel.mtime_to &&
                        (rectsize.mtime == sel.mtime_from ?
                         path >= sel.from : 1) &&
                        (rectsize.mtime == sel.mtime_to ?
                         path <= sel.to : 1))
                {
                    if (i < gs.selection_lsof)
                        selected = !selected;
                    full_selected = !full_selected;
                }
            }
            else
            {
                if (path >= sel.from && path <= sel.to )
                {
                    if (i < gs.selection_lsof)
                        selected = !selected;
                    full_selected = !full_selected;
                }
            }
        }
    }

    if (gs.selection_finish == 2 && selected)
    {
        if (path in gs.selection_hash)
            gs.selection_hash.remove(path);
        else
            /* EN: FIXME: THe position of selected item can be changed
               by changing sort ype
               RU: ИСПРАВЬ_МЕНЯ: позиция выбранного элемента может
               изменится при изменении порядка сортировки */
            gs.selection_hash[path] = rectsize.rect(sort);

        full_selected = !full_selected;
        gs.dirty = true;
    }


    return full_selected;
}

version(Windows)
{
int
draw_my_computer(GlobalState gs, DbTxn txn, 
        PathMnt path,
        ref CoordinatesPlusScale surf,
        DRect apply_rect,
        SortType sort = SortType.ByName,
        bool current = false,
        bool fast = false, int level = 0)
{
	RectSize rectsize = RectSize(apply_rect, apply_rect, apply_rect);
	DRect full_rect = DRect(0, 0, 1024*1024, 1024*1024);

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
	RectSize full_size = RectSize(drect_zero, drect_zero, drect_zero, 
			0, 0,
			0, 0, 0);
	long i = 0;
	size_t lev = 1;
	bool first = true;
	foreach (string name; paths)
	{
		DRect rect;
		calculate_rect(full_rect, rect, coords, lev);

		auto res = draw_path(gs, txn, path.next(name),
				surf, rect,
				rectsize.sort,
				false,
				ret < 0, level+1);
		if (res == -1)
		{
			fast = true;
			ret = -1;
		}

		//full_size.size += rect_size.size;
		//full_size.disk_usage += rect_size.disk_usage;
		//full_size.files += rect_size.files;

		//rect_sizes[name] = rect_size;

		calculate_coords(coords, lev, i, levels, entries_on_last_level);
		first = false;
	}

	bool selected = isSelected(gs, rectsize, path, sort);
	auto rnvnd = draw_rect_with_color_by_size(
			gs, rectsize, sort, surf, 
			(cast(bool)(path in gs.selection_hash)) ^ selected,
			path);

	draw_fs_info(gs, rnvnd, path, gs.lsblk[path], false, SortType.ByName);

        draw_direntry_name(gs, gs.lsblk[path].name, rnvnd);

	return ret;
}

}

int
draw_path(GlobalState gs, DbTxn txn, 
        PathMnt path,
        ref CoordinatesPlusScale surf,
        DRect apply_rect,
        SortType sort = SortType.ByName,
        bool current = false,
        bool fast = false, int level = 0)
{
    Fiber.yield();

    int ret = 0;
    if (level == 0)
    {
        clear_image_cache(gs);
    }

    DirEntry de;
    bool no_de = false;
    try
    {
        de = DirEntry(path);
    }
    catch (FileException e)
    {
	no_de = true;
    }

    bool pmnt;
    Dbt key, data;
    if (path in gs.lsblk)
    {
        check_if_fully_scanned(gs, path);

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
            // TODO: Created mount point, rescan up path
        }

        pmnt = true;
    }

    try
    {
        path.update(gs.lsblk);
    }
    catch (Exception e)
    {
        return 0;
    }

    version(Windows)
    {
	    if (path._next == SL)
	    {
		    return draw_my_computer(gs, txn, 
				    path, surf, apply_rect, sort, current, fast, level);
	    }
    }

    string path0 = path.get_key(gs.lsblk);
    key = path0;
    //writefln("GET %s", path0.replace("\0", SL));
    auto res = gs.db_map.get(txn, &key, &data);

    if (res == 0)
    {
        RectSize rectsize;
        RectSize origrectsize;
        origrectsize = rectsize = data.to!(RectSize);
        rectsize.rect(sort) = rectsize.rect(sort).apply(apply_rect);
        //writefln("path=%s, rect=%s", path, rectsize.rect(sort));
        //writefln("rectsize=%s", rectsize);

        bool selected = isSelected(gs, rectsize, path, sort);
        auto rnvnd = draw_rect_with_color_by_size(
                gs, rectsize, sort, surf, 
                (cast(bool)(path in gs.selection_hash)) ^ selected,
                path);

        if (path in gs.selection_sub)
        {
            draw_center_rect_with_color(
                    gs, rnvnd, 0x8080FFFF);
        }

        try{
            if (no_de)
            {
                draw_center_rect_with_color(
                        gs, rnvnd, 0x808080FF);
            }
            else if (!de.isSymlink && de.isDir && rectsize.show_info == InfoType.Progress)
            {
                draw_center_rect_with_color(
                        gs, rnvnd, 0x8080FF80);
            }
            else if (!de.isSymlink && de.isDir && rectsize.newest_msg_time > gs.msg_stamp ||
                    rectsize.msg[0] != char.init && rectsize.msg_time > gs.msg_stamp)
            {
                draw_center_rect_with_color(
                        gs, rnvnd, 0x80FF8080);
            }
        }
        catch (Exception e)
        {
            return ret;
        }

        calculate_animation_info(gs, rectsize, path, sort);

        void direntry_selected(GlobalState gs, int stage)
        {
            if (stage == 0)
            {
                Selection sel;
                sel.from = path;
                sel.to = path;
                sel.sort = sort;
                if (sort == SortType.BySize)
                {
                    sel.size_from = rectsize.disk_usage;
                    sel.size_to = rectsize.disk_usage;
                }
                else if (sort == SortType.ByTime)
                {
                    sel.mtime_from = rectsize.mtime;
                    sel.mtime_to = rectsize.mtime;
                }
                gs.selection_list ~= sel;
                //writefln("%s Selection %s", stage, sel);
            }
            else if ( (stage == 1 || stage == 2) &&
                    gs.selection_list.length > 0)
            {
                Selection* sel = &gs.selection_list[$-1];

                sel.to = path;
                if (sel.sort == SortType.BySize)
                    sel.size_to = rectsize.disk_usage;
                else if (sel.sort == SortType.ByTime)
                    sel.mtime_to = rectsize.mtime;

                gs.redraw_fast = true;
                //writefln("%s Selection %s", stage, *sel);
            }

            if ( stage == 2)
            {
                if (gs.selection_finish == 0)
                    gs.selection_finish++;
                gs.redraw_fast = false;
            }

            gs.selection_stage = stage;
            gs.dirty = true;
        }

        void run_viewer(GlobalState gs, int stage)
        {
            string mime_type = mime(path);
            if (mime_type == "inode/directory" ||
                    mime_type == "error/none")
            {
                // Do nothing
            }
            else if (mime_type.startsWith("image/"))
            {
                image_viewer(gs, path);
            }
            else if (mime_type.startsWith("text/"))
            {
                text_viewer(gs, path);
            }
            else
            {
                string msg = format("No viewer for '%s' mime type", mime_type);
                gs.messages ~= ConsoleMessage(
                        SDL_Color(0xFF, 0x00, 0x00, 0xFF),
                        msg,
                        SDL_GetTicks()
                        );
                writeln(msg);
            }
        }

        void switch_info(GlobalState gs, int stage)
        {
            if (origrectsize.show_info == InfoType.None)
                origrectsize.show_info = InfoType.FileInfo;
            else if (origrectsize.show_info == InfoType.FileInfo)
                origrectsize.show_info = InfoType.None;

            key = path0;
            data = origrectsize;
            auto res = gs.db_map.put(txn, &key, &data);
            if (res != 0)
                throw new Exception("Path info to map-db not written");
        }

        void run_mime(GlobalState gs, int stage)
        {
            string mime_type = mime(path);
            if ( mime_type in gs.mime_applications )
            {
                auto df_pipes = pipeProcess(["db_recover", "-h", path], Redirect.stdout | Redirect.stderrToStdout);
                auto pid = spawnProcess([gs.mime_applications[mime_type], path]);
                gs.pids ~= pid;
            }
            else
            {
                string msg = format("No mime application for '%s' mime type in ~/.unde/mime", mime_type);
                gs.messages ~= ConsoleMessage(
                        SDL_Color(0xFF, 0x00, 0x00, 0xFF),
                        msg,
                        SDL_GetTicks()
                        );
                writeln(msg);
            }
        }

        if (rnvnd.current_path)
        {
            //writefln("current_path = %s", path0.replace("\0",SL));
            gs.current_path = path0;
            gs.full_current_path = path;
            current = false;
        }

        if (current || rnvnd.current_path && (!no_de && !de.isSymlink && !de.isDir))
        {
            gs.new_double_clickable_list.insertFront(new Clickable(gs, rnvnd.sdl_rect, &run_viewer));
            gs.new_right_clickable_list.insertFront(new Clickable(gs, rnvnd.sdl_rect, &direntry_selected));
        }

        if ((current || rnvnd.current_path) && (!no_de && !de.isDir))
        {
            gs.new_double_right_clickable_list.insertFront(new Clickable(gs, rnvnd.sdl_rect, &switch_info));
        }

        if ((current || rnvnd.current_path) && (!no_de && !de.isSymlink && !de.isDir))
        {
            gs.new_middle_clickable_list.insertFront(new Clickable(gs, rnvnd.sdl_rect, &run_mime));
        }

        if (rnvnd.no_draw)
        {
            if (rectsize.show_info == InfoType.CreateDirectory ||
                    rectsize.show_info == InfoType.Copy ||
                    rectsize.show_info == InfoType.Move)
            {
                draw_enter_name(gs, rnvnd, path0, rectsize);
            }
            else if (!no_de && !de.isSymlink && de.isDir)
            {
                draw_de_info(gs, rnvnd, path, rectsize, de);
            }
        }

        /* EN: Only if it is not symbolic link and not too small rectangle
           draw directory recursively
           RU: Если только это не символическая ссылка или не слишком мелкий
           прямоугольник, рисовать директорию рекурсивно */
        if (!no_de && de.isSymlink)
        {
        version(Posix)
        {
            draw_link_info(gs, rnvnd, path);

            string link_to = readLink(path);
            try
            {
                if (link_to > "" && (gs.redraw_fast ? level < 2 : level < 3))
                {
                    if (link_to[0] != SL[0]) link_to = getParent(path)~SL~link_to;
                    if (link_to[$-1] == SL[0]) link_to = link_to[0..$-1];

                    link_to = replaceAll(link_to, regex(`/\./`), SL);
                    link_to = replaceAll(link_to, regex(`/\.$`), "");
                    auto re = regex(`/[^/]*/\.\.`);
                    string old_link_to;
                    do
                    {
                        old_link_to = link_to;
                        link_to = replaceAll(link_to, re, "");
                    }
                    while (old_link_to !is link_to);
                    DRect linkrect = rectsize.rect(sort);
                    if (link_to == "") link_to = SL;

                    res = draw_path(gs, txn, PathMnt(gs.lsblk, link_to),
                            surf, linkrect,
                            rectsize.sort,
                            rnvnd.current_path,
                            ret < 0, level+1);
                }
            } catch (UTFException e)
            {
                writefln("UTFException: %s", link_to);
            }
	    }
        }
        else if (!no_de && de.isDir &&
                (rnvnd.sdl_rect.w >= 4 || rnvnd.sdl_rect.h >= 4) &&
                !rnvnd.not_visible)
        {
            string[] paths;

            if (gs.redraw_fast ? level < 2 : level < 3)
            {
                try{
                    foreach (string name; dirEntries(path, SpanMode.shallow))
                    {
                        res = draw_path(gs, txn, path.next(name),
                                surf, rectsize.rect(sort),
                                rectsize.sort,
                                rnvnd.current_path,
                                ret < 0, level+1);
                        if (res == -1)
                        {
                            fast = true;
                            ret = -1;
                        }
                        else if (res == -2 && rectsize.size >= 0)
                        {
                            rescan_path(gs, path);
                        }
                    }
                } catch (FileException e)
                {
                }
            }
        }

        if (!no_de && !de.isSymlink && de.isFile &&
                rnvnd.sdl_rect.w > 256 && !rnvnd.not_visible )
        {
            if (rectsize.show_info == InfoType.FileInfo ||
                    rectsize.show_info == InfoType.Progress)
            {
                draw_de_info(gs, rnvnd, path, rectsize, de);
            }
            else
            {
                bool is_picture = draw_picture(gs, rnvnd, path, fast, ret);
                if (!is_picture)
                    draw_text_file(gs, rnvnd, path, ret);
            }
        }

        string name = path[path.lastIndexOf(SL)+1..$];
        if (path == SL)
            name = SL;
        draw_direntry_name(gs, name, rnvnd);
    }
    else if (pmnt)
    {
        RectSize rectsize;
        rectsize.rect(sort) = apply_rect;
        rectsize.size = -1;
        bool selected = isSelected(gs, rectsize, path, sort);
        auto rnvnd = draw_rect_with_color_by_size(
                gs, rectsize, sort, surf, 
                (cast(bool)(path in gs.selection_hash)) ^ selected,
                path);

        draw_fs_info(gs, rnvnd, path, gs.lsblk[path], true, SortType.ByName);

        string name = path[path.lastIndexOf(SL)+1..$];
        if (path == SL)
            name = SL;
        draw_direntry_name(gs, name, rnvnd);
    }
    else
    {
        if (false/*gs.copiers.length > 0 || gs.movers.length > 0*/)
        {
            // Nothing to do
        }
        else
        {
            //writefln("Can't find %s", path0.replace("\0", SL));
            ret = -2;
        }
    }

    return ret;
}
