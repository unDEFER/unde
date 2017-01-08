module unde.viewers.text_viewer.lib;

import unde.global_state;
import unde.path_mnt;
import unde.lib;
import unde.slash;
import unde.command_line.lib;

import berkeleydb.all;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;

import core.exception;

import std.string;
import std.stdio;
import std.algorithm.sorting;
import std.math;
import std.utf;

import std.file;

/*
void
text_viewer(GlobalState gs, PathMnt path)
{
}

void
draw_text(GlobalState gs)
{
}

package void
text_next(GlobalState gs)
{
}

package void
text_prev(GlobalState gs)
{
}
*/

void
text_viewer(GlobalState gs, PathMnt path)
{
    auto old_state = gs.state;
    gs.state = State.TextViewer;
    gs.text_viewer.path = path;

    get_rectsize(gs);

    if (old_state != State.TextViewer)
    {
        calculate_positions_in_directories(gs);
    }

    gs.dirty = true;
}

private void
get_rectsize(GlobalState gs)
{
    with (gs.text_viewer)
    {
        Dbt key, data;
        string path0 = path.get_key(gs.lsblk);
        key = path0;
        //writefln("GET %s", path0.replace("\0", SL));
        auto res = gs.db_map.get(null, &key, &data);

        if (res == 0)
        {
            rectsize = data.to!(RectSize);
        }
    }
}

package void
put_rectsize(GlobalState gs)
{
    with (gs.text_viewer)
    {
        Dbt key, data;
        string path0 = path.get_key(gs.lsblk);
        key = path0;
        data = rectsize;
        auto res = gs.db_map.put(null, &key, &data);
        if (res != 0)
            throw new Exception("Path info to map-db not written");
    }
}

package int
measure_lines(GlobalState gs, string text, 
        int size, bool wrap_lines, int line_height, SDL_Color color)
{
    if (text.length > 0 && text[$-1] == '\r') text = text[0..$-1];
    int lines = 1;

    if (!wrap_lines) return 1;

    auto tt = gs.text_viewer.font.get_line_from_cache(text,
            size, gs.screen.w, line_height, color);

    lines = tt.h/line_height;

    return lines;
}

package void
selection_to_buffer(GlobalState gs)
{
    File file;

    with(gs.text_viewer)
    {
        try {
            file = File(path);
        }
        catch (Exception exp)
        {
            return;
        }

        file.seek(start_selection);
        string selection = file.rawRead(new char[end_selection-start_selection+1]).idup();

        SDL_SetClipboardText(selection.toStringz());
    }
}

void
draw_text(GlobalState gs)
{
    File file;

    with(gs.text_viewer)
    {
        if (SDL_GetTicks() - last_redraw > 200)
        {
            int r = SDL_SetRenderTarget(gs.renderer, texture);
            if (r < 0)
            {
                throw new Exception(format("Error while set render target text_viewer.texture: %s",
                        fromStringz(SDL_GetError()) ));
            }

            SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);
            r = SDL_RenderClear(gs.renderer);
            if (r < 0)
            {
                throw new Exception(format("Error while clear renderer: %s",
                        fromStringz(SDL_GetError()) ));
            }

            try {
                file = File(path);
            }
            catch (Exception exp)
            {
                return;
            }

            try{
                int line_height = cast(int)(round(SQRT2^^gs.text_viewer.fontsize)*1.2);
                auto color = SDL_Color(255, 255, 255, 255);

                bool rectsize_changed = false;

                long blocksize = 4096;
                while (y > 0 && rectsize.offset > 0)
                {
                    long offset = rectsize.offset - blocksize;
                    if (offset < 0) offset = 0;
                    file.seek(offset);

                    long lines = 0;

                    struct lineInfo
                    {
                        int lines;
                        long offset;
                    }

                    lineInfo[] lines_info;

                    long startline_offset = file.tell;
                    foreach(line; file.byLine())
                    {
                        if (lines == 0 && offset != 0)
                        {
                            lines++;
                            startline_offset = file.tell;
                            continue;
                        }
                        if (startline_offset >= rectsize.offset) break;

                        int wrapped_lines = measure_lines(gs, line.idup(), 
                                fontsize, wraplines, line_height, color);
                        lines_info ~= lineInfo(wrapped_lines, startline_offset);

                        lines++;
                        startline_offset = file.tell;
                    }

                    if (lines_info.length == 0)
                    {
                        blocksize *= 2;
                        continue;
                    }

                    foreach_reverse(line_info; lines_info)
                    {
                        y -= line_info.lines * line_height;
                        rectsize.offset = line_info.offset;
                        rectsize_changed = true;
                        if (y <= 0) break;
                    }
                }

                file.seek(rectsize.offset);
                long lines = 0;

                int line_y = y;
                int line_x = x;
                auto offset = rectsize.offset;
                foreach(line; file.byLine())
                {
                    if (line_y > gs.screen.h)
                    {
                        break;
                    }

                    ssize_t from, to;
                    if (offset + line.length < start_selection ||
                            offset > end_selection)
                    {
                        from = -1;
                        to = -1;
                    }
                    else
                    {
                        if (start_selection > offset)
                        {
                            from = start_selection - offset;
                        }
                        if (offset > start_selection)
                        {
                            from = 0;
                        }
                        if (offset < end_selection)
                        {
                            to = end_selection - offset;
                        }
                        if ( offset + line.length < end_selection )
                        {
                            to = line.length;
                        }
                    }

                    auto tt = gs.text_viewer.font.get_line_from_cache(line.idup(),
                            fontsize, wraplines?gs.screen.w:0, line_height, color, null, from, to);

                    auto dst = SDL_Rect(line_x, line_y, tt.w, tt.h);

                    r = SDL_RenderCopyEx(gs.renderer, tt.texture, null, &dst, 0,
                                null, SDL_FLIP_NONE);
                    if (r < 0)
                    {
                        writefln( "draw_text(): Error while render copy: %s", fromStringz(SDL_GetError()) );
                    }

                    if (gs.mouse_screen_y >= dst.y && gs.mouse_screen_y <= dst.y+dst.h)
                    {
                        mouse_offset = offset + get_position_by_chars(
                                gs.mouse_screen_x - dst.x,
                                gs.mouse_screen_y - dst.y, tt.chars);
                    }

                    if (line_y + tt.h < 0)
                    {
                        y += tt.h;
                        rectsize.offset = file.tell;
                        rectsize_changed = true;
                    }

                    lines += tt.h/line_height;
                    line_y += tt.h;
                    offset = file.tell;
                }

                if (rectsize_changed)
                    put_rectsize(gs);

                //return;
            }
            catch(UTFException exc)
            {
                //return;
            }

            last_redraw = SDL_GetTicks();

            r = SDL_SetRenderTarget(gs.renderer, null);
            if (r < 0)
            {
                throw new Exception(format("Error while restore render target: %s",
                        fromStringz(SDL_GetError()) ));
            }

            font.clear_chars_cache();
            font.clear_lines_cache();
        }

        if (path in gs.selection_hash)
        {
            int r = SDL_RenderCopy(gs.renderer, gs.texture_blue, null, null);
            if (r < 0)
            {
                writefln( "draw_text(): Error while render copy texture_blue: %s", fromStringz(SDL_GetError()) );
            }
        }

        SDL_Rect dst = SDL_Rect(0, 0, gs.screen.w, gs.screen.h);
        int r = SDL_RenderCopy(gs.renderer, texture, null, &dst);
        if (r < 0)
        {
            writefln( "draw_text(): Error while render copy texture: %s", fromStringz(SDL_GetError()) );
        }
    }
}

private void
positions_in_directories_recursive(GlobalState gs, string p, ssize_t lev = 0)
{
    with (gs.text_viewer)
    {
        if (lev == 0)
        {
            files = [];
            positions = [];
        }

        string[] paths;

        try
        {
            foreach (string name; dirEntries(p, SpanMode.shallow))
            {
                paths ~= name;
            }
        }
        catch (FileException e)
        {
            return;
        }

        sort!("a < b")(paths);

        bool found = false;
        foreach (i, name; paths)
        {
            if (path.startsWith(name) && (name.length+1 > path.length || path[name.length] == SL[0]))
            {
                found = true;
                positions ~= i;
                files ~= paths;

                if (name == path)
                {
                    level = lev;
                }
                else
                {
                    positions_in_directories_recursive(gs, name, level+1);
                }
                break;
            }
        }
        if (!found)
        {
            gs.state = State.FileManager;
            gs.dirty = true;
        }
    }
}

private void
calculate_positions_in_directories(GlobalState gs)
{
    with (gs.text_viewer)
    {
        selections = [];

        foreach (selection; gs.selection_hash.byKey())
        {
            if ( mime(selection) != "inode/directory" ) continue;

            bool found_subdirs = false;
            //writefln("%s", selection);
            rescan_selections:
            foreach (i, ref s; selections)
            {
                if ( selection.startsWith(s) )
                {
                    //writefln("1. %s starts with %s", selection, s);
                    // Do nothing, the super-directory in the selections
                    found_subdirs = true;
                }
                else if ( s.startsWith(selection) )
                {
                    //writefln("2. %s starts with %s", s, selection);
                    // selections consists subdirectory
                    if (found_subdirs)
                    {
                        //writefln("before selections=%s", selections);
                        if (i < selection.length-1)
                            selections = selections[0..i] ~ selections[i+1..$];
                        else
                            selections = selections[0..i];
                        //writefln("after selections=%s", selections);
                        goto rescan_selections;
                    }
                    else
                    {
                        s = selection;
                        found_subdirs = true;
                    }
                }
            }

            if (!found_subdirs)
            {
                selections ~= selection;
            }
        }

        if (selections.length == 0)
        {
            string dir = getParent(path);
            selections ~= dir;
        }

        //writefln("selections = %s", selections);

        sel = -1;
        foreach (i, s; selections)
        {
            if (path.startsWith(s))
            {
                sel = i;
            }
        }

        if (sel >= 0)
        {
            positions_in_directories_recursive(gs, selections[sel]);
        }

        /*writefln("positions = %s", positions);
        writefln("files = %s", files);
        writefln("level = %s", level);*/
    }
}

package void
text_next(GlobalState gs)
{
    with (gs.text_viewer)
    {
        int sel0_count = 0;
        bool found_text = false;
        do
        {
            if (sel >= 0 && level >= 0)
            {
                bool level_dec;
                do
                {
                    level_dec = false;
                    positions[level]++;
                    //writefln("positions[%s] = %s", level, positions[level]);
                    //writefln("files = %s", files);
                    if ( positions[level] >= files[level].length )
                    {
                        //writefln("files[%s] exceeded", level);
                        files = files[0..$-1];
                        positions = positions[0..$-1];
                        level--;
                        level_dec = true;
                        if (level == -1)
                        {
                            //writefln("level == -1");
                            sel++;
                            if (sel >= selections.length)
                            {
                                //writefln("sel = 0");
                                sel = 0;
                                sel0_count++;
                            }
                        }
                    }
                } while (level_dec && level >= 0);
            }
            else if (sel == -1)
            {
                sel = 0;
                sel0_count++;
            }

            //writefln("level = %s", level);
            if (level == -1)
            {
                string[] paths;
                try
                {
                    foreach (string name; dirEntries(selections[sel], SpanMode.shallow))
                    {
                        paths ~= name;
                    }
                }
                catch (FileException e)
                {
                    return;
                }

                sort!("a < b")(paths);

                positions ~= 0;
                files ~= paths;
                level++;
                //writefln("0 paths added");
            }

            do
            {
                if (files[level].length == 0) break;
                string p = files[level][positions[level]]; 
                    //writefln("p=%s", p);
                string mime_type = mime(p);
                if (mime_type == "inode/directory")
                {
                    //writefln("directory");
                    string[] paths;

                    try
                    {
                        foreach (string name; dirEntries(p, SpanMode.shallow))
                        {
                            paths ~= name;
                        }
                    }
                    catch (FileException e)
                    {
                        return;
                    }

                    if (paths.length == 0)
                    {
                        break;
                    }

                    sort!("a < b")(paths);

                    positions ~= 0;
                    files ~= paths;
                    level++;
                }
                else if (mime_type.startsWith("text/"))
                {
                    //writefln("image!");
                    auto pathmnt = PathMnt(gs.lsblk, p);
                    text_viewer(gs, pathmnt);
                    found_text = true;
                    break;
                }
                else
                {
                    break;
                }
            } while (true);
        } while(sel0_count < 2 && !found_text);
    }
}

package void
text_prev(GlobalState gs)
{
    with (gs.text_viewer)
    {
        int seln_count = 0;
        bool found_text = false;
        do
        {
            if (sel >= 0 && level >= 0)
            {
                bool level_dec;
                do
                {
                    level_dec = false;
                    positions[level]--;
                    //writefln("positions[%s] = %s", level, positions[level]);
                    //writefln("files = %s", files);
                    if ( positions[level] < 0 )
                    {
                        //writefln("files[%s] exceeded", level);
                        files = files[0..$-1];
                        positions = positions[0..$-1];
                        level--;
                        level_dec = true;
                        if (level == -1)
                        {
                            //writefln("level == -1");
                            sel--;
                            if (sel < 0)
                            {
                                //writefln("sel = 0");
                                sel = selections.length-1;
                                seln_count++;
                            }
                        }
                    }
                } while (level_dec && level >= 0);
            }
            else if (sel == -1)
            {
                sel = selections.length-1;
                seln_count++;
            }

            //writefln("level = %s", level);
            if (level == -1)
            {
                string[] paths;
                try
                {
                    foreach (string name; dirEntries(selections[sel], SpanMode.shallow))
                    {
                        paths ~= name;
                    }
                }
                catch (FileException e)
                {
                    return;
                }

                sort!("a < b")(paths);

                positions ~= paths.length-1;
                files ~= paths;
                level++;
                //writefln("0 paths added");
            }

            do
            {
                if (files[level].length == 0) break;
                string p = files[level][positions[level]]; 
                    //writefln("p=%s", p);
                string mime_type = mime(p);
                if (mime_type == "inode/directory")
                {
                    //writefln("directory");
                    string[] paths;

                    try
                    {
                        foreach (string name; dirEntries(p, SpanMode.shallow))
                        {
                            paths ~= name;
                        }
                    }
                    catch (FileException e)
                    {
                        return;
                    }

                    if (paths.length == 0)
                    {
                        break;
                    }

                    sort!("a < b")(paths);

                    positions ~= paths.length-1;
                    files ~= paths;
                    level++;
                }
                else if (mime_type.startsWith("text/"))
                {
                    //writefln("image!");
                    auto pathmnt = PathMnt(gs.lsblk, p);
                    text_viewer(gs, pathmnt);
                    found_text = true;
                    break;
                }
                else
                {
                    break;
                }
            } while (true);
        } while(seln_count < 2 && !found_text);
    }
}
