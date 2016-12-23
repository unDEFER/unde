module unde.command_line.lib;

import unde.global_state;
import unde.path_mnt;
import unde.lib;
import unde.slash;
import unde.font;
import unde.command_line.db;

import berkeleydb.all;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;

import core.exception;

import std.string;
import std.stdio;
import std.math;
import std.conv;
import std.utf;


private void
fix_bottom_line(GlobalState gs)
{
    //writefln("Fix Bottom Line");
    with (gs.command_line)
    {
        nav_cmd_id = 0;
        nav_out_id = 0;
        nav_skip_cmd_id = 0;

        cwd = gs.full_current_path;

        Dbc cursor = gs.db_commands.cursor(null, 0);
        scope(exit) cursor.close();

        Dbt key, data;

        ulong id = mouse_cmd_id > 0 ? mouse_cmd_id : 1;
        string ks = get_key_for_command(command_key(cwd, id));
        //writefln("SET RANGE: %s (cwd=%s, id=%X)", ks, cwd, id);
        key = ks;
        id = find_next_by_key(cursor, 0, id, key, data);

        //writefln("mouse_cmd_id=%s", mouse_cmd_id);
        if (id != 0)
        {
            /* The bottom command found */
            ulong y_off = 0;
            //writefln("y=%s, y_off=%s", y, y_off);
            do
            {
                string key_string = key.to!(string);
                command_key cmd_key;
                parse_key_for_command(key_string, cmd_key);
                if (cwd != cmd_key.cwd)
                {
                    id = 0;
                    break;
                }
                else
                {
                    //writefln("cmd_id=%s", id);
                    id = cmd_key.id;
                    string data_string = data.to!(string);
                    command_data cmd_data;
                    parse_data_for_command(data_string, cmd_data);

                    int line_height = cast(int)(round(SQRT2^^9)*1.2);
                    auto rt = gs.text_viewer.font.get_size_of_line(cmd_data.command, 
                            9, gs.screen.w-80, line_height, SDL_Color(0xFF,0x00,0xFF,0xFF));

                    int lines = rt.h / line_height;

                    auto rect = SDL_Rect();
                    rect.x = 40;
                    rect.y = cast(int)(y_off + 4);
                    rect.w = rt.w;
                    rect.h = rt.h;

                    if (cmd_key.id == mouse_cmd_id &&
                            (0 == mouse_out_id || fontsize < 5))
                    {
                        int ry = cast(int)(gs.mouse_screen_y - mouse_rel_y*rect.h);
                        y_off = ry - 4;
                    }

                    if (rect.y >= gs.screen.h + line_height && nav_skip_cmd_id == 0)
                    {
                        nav_skip_cmd_id = cmd_key.id;

                        if (fontsize < 5)
                        {
                            int line_height9 = cast(int)(round(SQRT2^^fontsize)*1.2);
                            y = y_off - gs.screen.h + line_height9*2 + 8;
                            //writefln("CMD y = %d", y);
                            break;
                        }
                    }
                    if (nav_skip_cmd_id > 0 && (nav_cmd_id > 0 || fontsize < 5) )
                        break;

                    y_off += line_height*lines;

                    /* Loop through all commands */
                    if (fontsize >= 5)
                    {
                        /* Try to find last output for command */
                        Dbc cursor2 = gs.db_command_output.cursor(null, 0);
                        scope(exit) cursor2.close();

                        Dbt key2, data2;
                        ulong out_id = cmd_key.id == mouse_cmd_id && mouse_out_id > 0 ? mouse_out_id : 1;
                        ks = get_key_for_command_out(command_out_key(cwd, cmd_key.id, out_id));
                        //writefln("SET RANGE: %s (cwd=%s, id=%X)", ks, cwd, id);
                        key2 = ks;
                        out_id = find_next_by_key(cursor2, 0, out_id, key2, data2);

                        //writefln("mouse_out_id=%s", mouse_out_id);
                        if (out_id > 0)
                        {
                            /* The last output found */
                            do
                            {
                                /* Loop through all outputs */
                                string key_string2 = key2.to!(string);
                                command_out_key cmd_key2;
                                parse_key_for_command_out(key_string2, cmd_key2);
                                //writefln("cmd_id=%s, out_id=%s", cmd_key2.cmd_id, cmd_key2.out_id);
                                if (cmd_key.id != cmd_key2.cmd_id)
                                {
                                    out_id = 0;
                                    break;
                                }
                                else
                                {
                                    //writefln("out_id=%s", cmd_key2.out_id);
                                    string data_string2 = data2.to!(string);
                                    command_out_data cmd_data2;
                                    parse_data_for_command_out(data_string2, cmd_data2);

                                    auto color = SDL_Color(0xFF,0xFF,0xFF,0xFF);
                                    if (cmd_data2.pipe == OutPipe.STDERR)
                                    {
                                        color = SDL_Color(0xFF,0x80,0x80,0xFF);
                                    }

                                    line_height = cast(int)(round(SQRT2^^fontsize)*1.2);
                                    rt = gs.text_viewer.font.get_size_of_line(cmd_data2.output, 
                                            fontsize, gs.screen.w-80, line_height, color);

                                    lines = rt.h / line_height - 1;
                                    if (cmd_data2.output[$-1] != '\n') lines++;

                                    rect = SDL_Rect();
                                    rect.x = 40;
                                    rect.y = cast(int)(y_off + 4);
                                    rect.w = rt.w;
                                    rect.h = rt.h;

                                    if (cmd_key2.cmd_id == mouse_cmd_id &&
                                            cmd_key2.out_id == mouse_out_id)
                                    {
                                        int ry = cast(int)(gs.mouse_screen_y - mouse_rel_y*rect.h);
                                        //writefln("y_off change from %s", y_off);
                                        y_off = ry - 4;
                                        //writefln("to %s (%s - %s)", y_off, gs.mouse_screen_y, mouse_rel_y*rect.h);
                                    }

                                        //writefln("rect.y = %s", rect.y);
                                    if (rect.y > gs.screen.h + line_height)
                                    {
                                        nav_cmd_id = cmd_key2.cmd_id;
                                        nav_out_id = cmd_key2.out_id;

                                        int line_height9 = cast(int)(round(SQRT2^^fontsize)*1.2);
                                        y = y_off - gs.screen.h + line_height9*2 + 8;
                                        //writefln("OUT y = %d", y);
                                        break;
                                    }

                                    y_off += line_height*lines;
                                }
                            }
                            while (cursor2.get(&key2, &data2, DB_NEXT) == 0);
                        }
                    }
                }
            }
            while (cursor.get(&key, &data, DB_NEXT) == 0);
        }
    }
}

void
draw_command_line(GlobalState gs)
{
    with (gs.command_line)
    {
        if (SDL_GetTicks() - last_redraw > 200)
        {
            /* Setup texture render target */
            auto old_texture = SDL_GetRenderTarget(gs.renderer);
            int r = SDL_SetRenderTarget(gs.renderer, texture);
            if (r < 0)
            {
                throw new Exception(format("Error while set render target text_viewer.texture: %s",
                            fromStringz(SDL_GetError()) ));
            }

            SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);
            r = SDL_SetRenderDrawColor(gs.renderer, 0, 0, 0, 0);
            if (r < 0)
            {
                writefln("Can't SDL_SetRenderDrawColor: %s",
                        to!string(SDL_GetError()));
            }
redraw:
            r = SDL_RenderClear(gs.renderer);
            if (r < 0)
            {
                throw new Exception(format("Error while clear renderer: %s",
                            fromStringz(SDL_GetError()) ));
            }

            /* If terminal */
            if (gs.command_line.terminal)
            {
                if (font_changed)
                {
                    fix_bottom_line(gs);
                    font_changed = false;
                }

                /* Background */
                r = SDL_RenderCopy(gs.renderer, gs.texture_black, null, null);
                if (r < 0)
                {
                    writefln( "draw_command_line(), 1: Error while render copy: %s",
                            SDL_GetError().to!string() );
                }

                with (gs.command_line)
                {
                    cwd = gs.full_current_path;
                    Dbc cursor = gs.db_commands.cursor(null, 0);
                    scope(exit) cursor.close();

                    /* Try to find bottom command in commands history */
                    bool first_cmd_or_out = true;

                    Dbt key, data;
                    ulong id = find_prev_command(cursor, cwd, nav_skip_cmd_id,
                            key, data);
                    bool first_cmd = true;

                    if (id != 0)
                    {
                        /* The bottom command found */
                        int line_height9 = cast(int)(round(SQRT2^^fontsize)*1.2);
                        ulong y_off = y + gs.screen.h - line_height9*3 - 8;
                        //writefln("y=%s, y_off=%s", y, y_off);
                        do
                        {
                            /* Loop through all commands */
                            string key_string = key.to!(string);
                            command_key cmd_key;
                            parse_key_for_command(key_string, cmd_key);
                            if (cwd != cmd_key.cwd)
                            {
                                id = 0;
                                break;
                            }
                            else
                            {
                                if (fontsize >= 5)
                                {
                                    /* Try to find last output for command */
                                    Dbc cursor2 = gs.db_command_output.cursor(null, 0);
                                    scope(exit) cursor2.close();

                                    Dbt key2, data2;
                                    ulong out_id = cmd_key.id == nav_cmd_id ? nav_out_id : 0;
                                    out_id = find_prev_command_out(cursor2, cwd, cmd_key.id, out_id, key2, data2);

                                    if (out_id > 0)
                                    {
                                        /* The last output found */
                                        do
                                        {
                                            /* Loop through all outputs */
                                            string key_string2 = key2.to!(string);
                                            command_out_key cmd_key2;
                                            parse_key_for_command_out(key_string2, cmd_key2);
                                            //writefln("cmd_id=%s, out_id=%s", cmd_key2.cmd_id, cmd_key2.out_id);
                                            if (cmd_key.id != cmd_key2.cmd_id)
                                            {
                                                out_id = 0;
                                                break;
                                            }
                                            else
                                            {
                                                string data_string2 = data2.to!(string);
                                                command_out_data cmd_data2;
                                                parse_data_for_command_out(data_string2, cmd_data2);

                                                auto color = SDL_Color(0xFF,0xFF,0xFF,0xFF);
                                                if (cmd_data2.pipe == OutPipe.STDERR)
                                                {
                                                    color = SDL_Color(0xFF,0x80,0x80,0xFF);
                                                }
                                                int line_height = cast(int)(round(SQRT2^^fontsize)*1.2);
                                                auto rt = gs.text_viewer.font.get_size_of_line(cmd_data2.output, 
                                                        fontsize, gs.screen.w-80, line_height, color);

                                                int lines = rt.h / line_height - 1;
                                                if (cmd_data2.output.length > 0 && cmd_data2.output[$-1] != '\n') lines++;
                                                y_off -= line_height*lines;

                                                auto i = 0;
                                                auto rect = SDL_Rect();
                                                rect.x = 40;
                                                rect.y = cast(int)(y_off + 4 + line_height*i);
                                                rect.w = rt.w;
                                                rect.h = rt.h;

                                                if (rect.y < gs.screen.h && rect.y+rect.h > 0)
                                                {
                                                    auto tt = gs.text_viewer.font.get_line_from_cache(cmd_data2.output, 
                                                            fontsize, gs.screen.w-80, line_height, color,
                                                            cmd_data2.attrs);
                                                    if (!tt && !tt.texture)
                                                    {
                                                        throw new Exception("Can't create text_surface: "~
                                                                to!string(TTF_GetError()));
                                                    }
                                                    //assert(rt.w == tt.w && rt.h == tt.h, format("rt.w=%d, tt.w=%d, rt.h=%d, tt.h=%d",
                                                    //            rt.w, tt.w, rt.h, tt.h));

                                                    r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
                                                    if (r < 0)
                                                    {
                                                        writefln(
                                                                "draw_command_line(), 2: Error while render copy: %s", 
                                                                SDL_GetError().to!string() );
                                                        writefln("text: %s", cmd_data2.output);
                                                    }

                                                    if (nav_skip_cmd_id == 0 && first_cmd &&
                                                            cmd_data2.pos < tt.chars.length)
                                                    {
                                                        auto rect2= tt.chars[cmd_data2.pos];
                                                        rect2.x += 40;
                                                        rect2.y += cast(int)(y_off + 4 + line_height*i);
                                                        string chr = " ";
                                                        try
                                                        {
                                                        if (cmd_data2.pos < cmd_data2.output.length)
                                                            chr = cmd_data2.output[cmd_data2.pos..cmd_data2.pos+cmd_data2.output.stride(cmd_data2.pos)];
                                                        }
                                                        catch (UTFException exp)
                                                        {
                                                            chr = " ";
                                                        }
                                                        if (chr == "\n") chr = " ";

                                                        r = SDL_RenderCopy(gs.renderer, gs.texture_cursor, null, &rect2);
                                                        if (r < 0)
                                                        {
                                                            writefln( "draw_command_line(), 3: Error while render copy: %s",
                                                                    SDL_GetError().to!string() );
                                                        }

                                                        auto st = gs.text_viewer.font.get_char_from_cache(chr, fontsize, SDL_Color(0x00, 0x00, 0x20, 0xFF));
                                                        if (!st) return;

                                                        r = SDL_RenderCopy(gs.renderer, st.texture, null, &rect2);
                                                        if (r < 0)
                                                        {
                                                            writefln(
                                                                    "draw_command_line(), 4: Error while render copy: %s", 
                                                                    SDL_GetError().to!string() );
                                                            writefln("chr: %s", chr);
                                                        }
                                                    }
                                                }
                                                first_cmd = false;

                                                if (rect.y <= gs.mouse_screen_y && 
                                                        rect.y+rect.h-line_height >= gs.mouse_screen_y)
                                                {
                                                    mouse_cmd_id = cmd_key2.cmd_id;
                                                    mouse_out_id = cmd_key2.out_id;
                                                    mouse_rel_y = (cast(double)gs.mouse_screen_y-rect.y)/rect.h;
                                                    //writefln("OUT: mouse_cmd_id=%s, mouse_out_id=%s, out=%s",
                                                    //        mouse_cmd_id, mouse_out_id, cmd_data2.output);
                                                }

                                                if (rect.y > gs.screen.h)
                                                {
                                                    //writefln("tt.h=%s", tt.h);
                                                    //writefln("rect.y-gs.screen.h=%s", rect.y-gs.screen.h);
                                                    y -= rt.h - line_height;
                                                    nav_out_id = cmd_key2.out_id;
                                                    nav_cmd_id = cmd_key.id;
                                                    writefln("OUT UP");
                                                }

                                                //writefln("OUT: y=%s, first_cmd_or_out=%s, nav_out_id=%s, rect.y + rect.h=%s, gs.screen.h=%s",
                                                //        y, first_cmd_or_out, nav_out_id, rect.y + rect.h, gs.screen.h);
                                                if (y != 0 && first_cmd_or_out && nav_out_id > 0 && (rect.y + rect.h) < gs.screen.h)
                                                {
                                                    fix_bottom_line(gs);
                                                    goto redraw;
                                                }
                                                first_cmd_or_out = false;

                                                if (rect.y + rect.h < 0)
                                                    break;
                                            }
                                        }
                                        while (cursor2.get(&key2, &data2, DB_PREV) == 0);

                                    }
                                }

                                //writefln("Excellent");
                                id = cmd_key.id;
                                string data_string = data.to!(string);
                                command_data cmd_data;
                                parse_data_for_command(data_string, cmd_data);

                                int line_height = cast(int)(round(SQRT2^^9)*1.2);
                                auto rt = gs.text_viewer.font.get_size_of_line(cmd_data.command, 
                                        9, gs.screen.w-80, line_height, SDL_Color(0xFF,0x00,0xFF,0xFF));

                                int lines = rt.h / line_height;
                                y_off -= line_height*lines;

                                if (cmd_data.end == 0)
                                {
                                    auto tt = gs.text_viewer.font.get_char_from_cache(
                                            "⬤", 7, SDL_Color(0x00, 0xFF, 0x00, 0xFF));

                                    auto rect = SDL_Rect();
                                    rect.x = 30;
                                    rect.y = cast(int)(y_off + 4);
                                    rect.w = tt.w;
                                    rect.h = tt.h;

                                    r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
                                    if (r < 0)
                                    {
                                        writefln(
                                                "draw_command_line(), 5: Error while render copy: %s", 
                                                SDL_GetError().to!string() );
                                    }
                                }
                                else
                                {
                                    auto color = SDL_Color(0x00,0xFF,0x00,0xFF);
                                    if (cmd_data.status != 0) color = SDL_Color(0xFF,0x00,0x00,0xFF);

                                    auto tt = gs.text_viewer.font.get_line_from_cache(format("%d", cmd_data.status), 
                                            8, gs.screen.w-80, line_height, color);
                                    if (!tt && !tt.texture)
                                    {
                                        throw new Exception("Can't create text_surface: "~
                                                to!string(TTF_GetError()));
                                    }

                                    auto rect = SDL_Rect();
                                    rect.x = 30;
                                    rect.y = cast(int)(y_off + 4);
                                    rect.w = tt.w;
                                    rect.h = tt.h;

                                    r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
                                    if (r < 0)
                                    {
                                        writefln(
                                                "draw_command_line(), 6: Error while render copy: %s", 
                                                SDL_GetError().to!string() );
                                    }
                                }

                                auto i = 0;
                                auto rect = SDL_Rect();
                                rect.x = 55;
                                rect.y = cast(int)(y_off + 4 + line_height*i);
                                rect.w = rt.w;
                                rect.h = rt.h;

                                if (rect.y < gs.screen.h && rect.y+rect.h > 0)
                                {
                                    auto tt = gs.text_viewer.font.get_line_from_cache(cmd_data.command, 
                                            9, gs.screen.w-80, line_height, SDL_Color(0xFF,0x00,0xFF,0xFF));
                                    if (!tt && !tt.texture)
                                    {
                                        throw new Exception("Can't create text_surface: "~
                                                to!string(TTF_GetError()));
                                    }

                                    r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
                                    if (r < 0)
                                    {
                                        writefln(
                                                "draw_command_line(), 7: Error while render copy: %s", 
                                                SDL_GetError().to!string() );
                                    }
                                }

                                if (rect.y <= gs.mouse_screen_y && 
                                        rect.y+rect.h >= gs.mouse_screen_y)
                                {
                                    mouse_cmd_id = cmd_key.id;
                                    mouse_out_id = 0;
                                    mouse_rel_y = (cast(double)gs.mouse_screen_y-rect.y)/rect.h;
                                    //writefln("CMD: mouse_cmd_id=%s, mouse_out_id=%s, command=%s",
                                    //        mouse_cmd_id, mouse_out_id, cmd_data.command);
                                }

                                if (rect.y > gs.screen.h)
                                {
                                    y -= rt.h;
                                    nav_skip_cmd_id = cmd_key.id;
                                    //writefln("CMD UP");
                                }

                                //writefln("CMD: y=%s, first_cmd_or_out=%s, nav_skip_cmd_id=%s, rect.y + rect.h=%s, gs.screen.h=%s",
                                //        y, first_cmd_or_out, nav_skip_cmd_id, rect.y + rect.h, gs.screen.h);
                                if (y != 0 && first_cmd_or_out && nav_skip_cmd_id > 0 && (rect.y + rect.h) < gs.screen.h)
                                {
                                    fix_bottom_line(gs);
                                    goto redraw;
                                }

                                first_cmd_or_out = false;

                                if (rect.y + rect.h < 0)
                                    break;
                            }
                        }
                        while (cursor.get(&key, &data, DB_PREV) == 0);
                    }

                    if (first_cmd_or_out)
                    {
                        fix_bottom_line(gs);
                        //goto redraw;
                    }
                }
            }

            if (gs.command_line.enter)
            {
                ulong y_off;

                string prompt = "$ ";
                int line_height = cast(int)(round(SQRT2^^9)*1.2);
                auto ptt = gs.text_viewer.font.get_line_from_cache(prompt, 
                        9, gs.screen.w-80, line_height, SDL_Color(0x00,0xFF,0x00,0xFF));
                if (!ptt && !ptt.texture)
                {
                    throw new Exception("Can't create text_surface: "~
                            to!string(TTF_GetError()));
                }

                auto tt = gs.text_viewer.font.get_line_from_cache(gs.command_line.command, 
                        9, gs.screen.w-80-ptt.w, line_height, SDL_Color(0xFF, 0xFF, 0xFF, 0xFF));
                if (!tt && !tt.texture)
                {
                    throw new Exception("Can't create text_surface: "~
                            to!string(TTF_GetError()));
                }

                auto lines = tt.h / line_height;
                y_off = gs.screen.h - line_height*3 - line_height*lines - 8;

                /* EN: render background of console messages
                   RU: рендерим фон консоли сообщений */
                SDL_Rect rect;
                rect.x = 32;
                rect.y = cast(int)y_off;
                rect.w = gs.screen.w - 32*2;
                rect.h = cast(int)(line_height*lines + 8);

                r = SDL_RenderCopy(gs.renderer, gs.texture_black, null, &rect);
                if (r < 0)
                {
                    writefln( "draw_command_line(), 8: Error while render copy: %s",
                            SDL_GetError().to!string() );
                }
                
                /* EN: Render prompt to screen
                   RU: Рендерим приглашение на экран */
                auto i = 0;
                rect = SDL_Rect();
                rect.x = 40;
                rect.y = cast(int)(y_off + 4 + line_height*i);
                rect.w = ptt.w;
                rect.h = ptt.h;

                r = SDL_RenderCopy(gs.renderer, ptt.texture, null, &rect);
                if (r < 0)
                {
                    writefln(
                        "draw_command_line(), 9: Error while render copy: %s", 
                        SDL_GetError().to!string() );
                }

                /* EN: Render text to screeb
                   RU: Рендерим текст на экран */
                rect = SDL_Rect();
                rect.x = 40+ptt.w;
                rect.y = cast(int)(y_off + 4 + line_height*i);
                rect.w = tt.w;
                rect.h = tt.h;

                r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
                if (r < 0)
                {
                    writefln(
                        "draw_command_line(), 10: Error while render copy: %s", 
                        SDL_GetError().to!string() );
                }

                with (gs.command_line)
                {
                    //if (pos >= tt.chars.length) pos = tt.chars.length - 1;
                    rect = tt.chars[pos];
                    rect.x += 40+ptt.w;
                    rect.y += cast(int)(y_off + 4 + line_height*i);
                    string chr = " ";
                    if (pos < command.length)
                        chr = command[pos..pos+command.stride(pos)];
                    if (chr == "\n") chr = " ";

                    r = SDL_RenderCopy(gs.renderer, gs.texture_cursor, null, &rect);
                    if (r < 0)
                    {
                        writefln( "draw_command_line(), 11: Error while render copy: %s",
                                SDL_GetError().to!string() );
                    }

                    auto st = gs.text_viewer.font.get_char_from_cache(chr, 9, SDL_Color(0x00, 0x00, 0x20, 0xFF));
                    if (!st) return;

                    r = SDL_RenderCopy(gs.renderer, st.texture, null, &rect);
                    if (r < 0)
                    {
                        writefln(
                            "draw_command_line(), 12: Error while render copy: %s", 
                            SDL_GetError().to!string() );
                    }
                }
            }

            last_redraw = SDL_GetTicks();

            r = SDL_SetRenderTarget(gs.renderer, old_texture);
            if (r < 0)
            {
                throw new Exception(format("Error while restore render target: %s",
                        fromStringz(SDL_GetError()) ));
            }

            gs.text_viewer.font.clear_chars_cache();
            gs.text_viewer.font.clear_lines_cache();
        }

        int r = SDL_RenderCopy(gs.renderer, texture, null, null);
        if (r < 0)
        {
            writefln( "draw_text(): Error while render copy texture: %s", fromStringz(SDL_GetError()) );
        }
    }

}

void
hist_up(GlobalState gs)
{
    with (gs.command_line)
    {
        cwd = gs.full_current_path;
        Dbc cursor = gs.db_commands.cursor(null, 0);
        scope(exit) cursor.close();

        Dbt key, data;
        ulong id = find_prev_command(cursor, cwd, hist_cmd_id,
                key, data);

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
                string data_string = data.to!(string);
                command_data cmd_data;
                parse_data_for_command(data_string, cmd_data);

                if (hist_pos == 0)
                {
                    edited_command = command;
                }
                hist_pos++;
                command = cmd_data.command.idup();
                pos = command.length;
                //writefln("Excellent");
                //writefln("cmd_data.command=%s", cmd_data.command);
                //writefln("pos=%s", pos);
            }
        }

        if (id == 0)
        {
            hist_pos = 0;
            command = edited_command;
            pos = command.length;
        }

        hist_cmd_id = id;
    }
}

void
hist_down(GlobalState gs)
{
    with (gs.command_line)
    {
        cwd = gs.full_current_path;
        Dbc cursor = gs.db_commands.cursor(null, 0);
        scope(exit) cursor.close();

        Dbt key, data;
        ulong id = find_next_command(cursor, cwd, hist_cmd_id,
                key, data);

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
                //writefln("Excellent");
                id = cmd_key.id;
                string data_string = data.to!(string);
                command_data cmd_data;
                parse_data_for_command(data_string, cmd_data);

                if (hist_pos == 0)
                {
                    edited_command = command;
                }
                hist_pos++;
                command = cmd_data.command.idup();
                pos = command.length;
            }
        }

        if (id == 0)
        {
            hist_pos = 0;
            command = edited_command;
            pos = command.length;
        }

        gs.command_line.hist_cmd_id = id;
    }
}
