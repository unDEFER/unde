module unde.marks;

import unde.global_state;
import unde.lib;
import unde.font;
import unde.path_mnt;
import unde.viewers.image_viewer.lib;
import unde.viewers.text_viewer.lib;
import unde.slash;

version (Windows)
{
import unde.file_manager.find_path;
}

import berkeleydb.all;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;

import std.math;
import std.stdio;
import std.string;
import std.conv;


public DRect
get_rectsize_for_mark(GlobalState gs, PathMnt path, string full_path,
        DRect apply_rect, SortType sort = SortType.ByName)
{
    bool pmnt;
    Dbt key, data;
    if (path in gs.lsblk)
    {
        string path0 = path.get_key(gs.lsblk);
        key = path0;
        auto res = gs.db_map.get(null, &key, &data);
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

        pmnt = true;
    }

    try
    {
        path.update(gs.lsblk);
    }
    catch (Exception e)
    {
        return DRect();
    }

    string path0 = path.get_key(gs.lsblk);
    key = path0;
    //writefln("GET %s", path0.replace("\0", SL));
    auto res = gs.db_map.get(null, &key, &data);
    version(Windows)
    {
    if (path == SL) res = 0;
    }

    if (res == 0)
    {
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

        //writefln("path=%s, full_path=%s", path, full_path);
        if (path == full_path)
        {
            return rectsize.rect(sort);
        }

	string next;
	bool found = false;
	version (Windows)
	{
		if (path == SL && full_path[1] == ':')
		{
			next = full_path[0..2];
			found = true;
		}
	}
	if (!found)
	{
		auto after_path = full_path[path.length+1..$];
		if (path == SL) after_path = full_path[1..$];
		//writefln("after_path=%s", after_path);
		if (after_path.indexOf(SL) > 0)
		    next = path ~ SL ~ after_path[0..after_path.indexOf(SL)];
		else
		    next = path ~ SL ~ after_path;
		if (path == SL) next = next[1..$];
	}
		//writefln("next=%s", next);

        auto drect = get_rectsize_for_mark(gs, path.next(next), full_path, rectsize.rect(sort), rectsize.sort);
        return drect;
    }
    return DRect();
}

void draw_marks(GlobalState gs, ref CoordinatesPlusScale surf)
{
//unmark(gs, "L");
    foreach(char m; 'A'..('Z'+1))
    {
        Dbt key = m;
        Dbt data;

        auto res = gs.db_marks.get(null, &key, &data);
        if (res == 0)
        {
            Mark mark = data.to!(Mark);
            string path = from_char_array(mark.path);
            string uuid = path[0..path.indexOf("\0")];

            string full_path = null;
            foreach(mount_point, lsblk_info; gs.lsblk)
            {
                if (lsblk_info.uuid == uuid)
                {
                    full_path = mount_point ~ path[path.indexOf("\0")..$].replace("\0", SL);
                    if (mount_point == SL) full_path = full_path[1..$];
                    break;
                }
            }

            if (full_path)
            {
                auto apply_rect = DRect(0, 0, 1024*1024, 1024*1024);
                auto drect = get_rectsize_for_mark(gs, PathMnt(gs.lsblk, SL), full_path, apply_rect);

                SDL_Rect on_surf = drect.to_screen(surf);
                SDL_Rect on_screen = drect.to_screen(gs.screen);
                //writefln("%s: %s", m, full_path);
                //writefln("SDL_Rect: %s", on_screen);
                //writefln("Mark screen_rect: %s", mark.screen_rect);

                if (on_screen.w <= mark.screen_rect.w && on_screen.h <= mark.screen_rect.h)
                {
                    double xrelation = cast(double)(gs.screen.w/2 - mark.screen_rect.x) / (mark.screen_rect.x + mark.screen_rect.w - gs.screen.w/2);
                    double yrelation = cast(double)(gs.screen.h/2 - mark.screen_rect.y) / (mark.screen_rect.y + mark.screen_rect.h - gs.screen.h/2);

                    //xrelation = X / (on_screen.w - X);
                    //xrelation*on_screen.w = xrelation*X + X

                    int x = cast(int)( on_surf.x + xrelation*on_surf.w/(xrelation+1) );
                    int y = cast(int)( on_surf.y + yrelation*on_surf.h/(yrelation+1) );

                    //writefln("%dx%d", x, y);

                    auto tt1 = gs.text_viewer.font.get_char_from_cache(
                            "⬤", 10, SDL_Color(0x00, 0xFF, 0xFF, 0x80));
                    auto tt2 = gs.text_viewer.font.get_char_from_cache(
                            "◯", 10, SDL_Color(0x00, 0x00, 0x00, 0xFF));
                    auto tt3 = gs.text_viewer.font.get_char_from_cache(
                            ""~m, 9, SDL_Color(0x00, 0x00, 0x00, 0xFF));

                    SDL_Rect rect1 = SDL_Rect(x-tt1.w/2, y-tt1.h/2, 
                                                tt1.w, tt1.h);
                    SDL_Rect rect2 = SDL_Rect(x-tt2.w/2, y-tt2.h/2, 
                                                tt2.w, tt2.h);
                    SDL_Rect rect3 = SDL_Rect(x-tt3.w/2, y-tt3.h/2, 
                                                tt3.w, tt3.h);

                    auto r = SDL_RenderCopy(gs.renderer, tt1.texture, 
                                                null, &rect1);
                    if (r < 0)
                    {
                        writefln( "draw_marks(): Error while render copy 1: %s",
                                SDL_GetError().to!string() );
                    }

                    r = SDL_RenderCopy(gs.renderer, tt2.texture, 
                                                null, &rect2);
                    if (r < 0)
                    {
                        writefln( "draw_marks(): Error while render copy 2: %s",
                                SDL_GetError().to!string() );
                    }

                    r = SDL_RenderCopy(gs.renderer, tt3.texture, 
                                                null, &rect3);
                    if (r < 0)
                    {
                        writefln( "draw_marks(): Error while render copy 3: %s", SDL_GetError().to!string() );
                    }
                }
            }
        }
    }
}

void remark_desktop(GlobalState gs)
{
    static CoordinatesPlusScale old_screen;
    static State old_state;
    static string old_path;
    static long old_offset;

    bool remark = false;
    if (gs.screen != old_screen || gs.state != old_state)
    {
        remark = true;
        old_screen = gs.screen;
        old_state = gs.state;
    }
    else if (gs.screen == old_screen && gs.state == old_state &&
            (gs.state == State.ImageViewer || gs.state == State.TextViewer))
    {
        string path;
        long offset;
        if (gs.state == State.ImageViewer)
        {
            path = gs.image_viewer.path.get_key(gs.lsblk);
            offset = old_offset;
        }
        else
        {
            path = gs.text_viewer.path.get_key(gs.lsblk);
            offset = gs.text_viewer.rectsize.offset;
        }

        if (path != old_path || offset != old_offset)
            remark = true;

        old_path = path;
        old_offset = offset;
    }

    if (remark)
        mark(gs, gs.desktop, true);
}

void mark(GlobalState gs, string m, bool hide_remark_message = false)
{
    //writefln("mark %s", m);
    Mark mark;
    mark.state = gs.state;
    string path;
    final switch (gs.state)
    {
        case State.FileManager:
            path = gs.current_path;
            break;
        case State.ImageViewer:
            path = gs.image_viewer.path.get_key(gs.lsblk);
            break;
        case State.TextViewer:
            path = gs.text_viewer.path.get_key(gs.lsblk);
            mark.offset = gs.text_viewer.rectsize.offset;
            break;
    }
    mark.path = to_char_array!MARKS_PATH_MAX(path);

    final switch (gs.state)
    {
        case State.FileManager:
            mark.screen_rect = gs.current_path_rect.to_screen(gs.screen);
            if (!(m >= "0" && m <= "9"))
            {
                mark.screen_rect.x += gs.screen.w/2 - gs.mouse_screen_x;
                mark.screen_rect.y += gs.screen.h/2 - gs.mouse_screen_y;
            }
            break;
        case State.ImageViewer:
            goto case;
        case State.TextViewer:
            mark.screen_rect = SDL_Rect((gs.screen.w - gs.screen.h)/2, 0, gs.screen.h, gs.screen.h);
            break;
    }

    //writefln("%s, screen_rect = %s, path = %s", m, mark.screen_rect, path);
    Dbt key, data;
    key = m;
    data = mark;

    auto res = gs.db_marks.put(null, &key, &data);
    if (res != 0)
        throw new Exception("Mark info to marks-db not written");

    else if (!hide_remark_message && m >= "0" && m <= "9")
    {
        string msg = format("Desktop %s remarked", m);
        gs.messages ~= ConsoleMessage(
                SDL_Color(0xFF, 0xFF, 0xFF, 0xFF),
                msg,
                SDL_GetTicks()
                );
        writeln(msg);
    }
}

void unmark(GlobalState gs, string m)
{
    Dbt key;
    key = m;

    auto res = gs.db_marks.del(null, &key);
    if (res != 0)
        throw new Exception("Mark info from marks-db not deleted");

    if (m >= "0" && m <= "9")
    {
        string msg = format("Desktop %s removed", m);
        gs.messages ~= ConsoleMessage(
                SDL_Color(0xFF, 0xFF, 0xFF, 0xFF),
                msg,
                SDL_GetTicks()
                );
        writeln(msg);
    }
}

void go_mark(GlobalState gs, string m)
{
    Dbt key = m;
    Dbt data;

    //writefln("Go Mark %s", m);
    auto res = gs.db_marks.get(null, &key, &data);
    if (res == 0)
    {
        Mark mark = data.to!(Mark);
        string path = from_char_array(mark.path);

        if (path == "")
            goto create_desktop;

        string uuid = path[0..path.indexOf("\0")];

        string full_path = null;
        foreach(mount_point, lsblk_info; gs.lsblk)
        {
            if (lsblk_info.uuid == uuid)
            {
                full_path = mount_point ~ path[path.indexOf("\0")..$].replace("\0", SL);
                if (mount_point == SL) full_path = full_path[1..$];
                break;
            }
        }

	version (Windows)
	{
		if (full_path.length == 3 && full_path[1] == ':')
		{
			full_path = full_path[0..2];
		}
	}
	    //writefln("path=%s, screen_rect=%s", path, mark.screen_rect);

        if (full_path)
        {
            auto apply_rect = DRect(0, 0, 1024*1024, 1024*1024);
            auto drect = get_rectsize_for_mark(gs, PathMnt(gs.lsblk, SL), full_path, apply_rect);

            if (!isNaN(drect.w))
            {
                //SDL_Rect on_screen = drect.to_screen(gs.screen);
                //writefln("Recalculate screen coordinates on %s", full_path);
                drect.rescale_screen(gs.screen, mark.screen_rect);
            }
            else
            {
                writefln("Can't calculate DRect for %s", full_path);
            }

            gs.state = State.FileManager;

            if (mark.state != State.FileManager)
            {
                if (mark.state == State.ImageViewer)
                    image_viewer(gs, PathMnt(gs.lsblk, full_path));
                else if (mark.state == State.TextViewer)
                {
                    text_viewer(gs, PathMnt(gs.lsblk, full_path));
                    gs.text_viewer.rectsize.offset = mark.offset;
                }
            }
        }
    }
    
create_desktop:
    if (res != 0 && m >= "0" && m <= "9")
    {
        gs.initScreenAndSurf();
        gs.state = State.FileManager;

        string msg = format("Desktop %s created", m);
        gs.messages ~= ConsoleMessage(
                SDL_Color(0xFF, 0xFF, 0xFF, 0xFF),
                msg,
                SDL_GetTicks()
                );
        writeln(msg);
    }

    if (m >= "0" && m <= "9")
    {
        gs.desktop = m;

        string current_desktop = "current_desktop";
        key = current_desktop;
        data = m;

        res = gs.db_marks.put(null, &key, &data);
        if (res != 0)
            throw new Exception("Can't write current desktop to marks-db");
	//writefln("gs.desktop=%s", gs.desktop);
    }
}
