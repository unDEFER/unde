module unde.file_manager.events;

import unde.global_state;
import unde.clickable;
import unde.lib;
import unde.file_manager.remove_paths;
import unde.file_manager.copy_paths;
import unde.file_manager.move_paths;
import unde.marks;
import unde.tick;
import unde.scan;
import unde.path_mnt;
import unde.slash;

import berkeleydb.all;
import derelict.sdl2.sdl;

import std.utf;
import std.stdio;
import std.string;
import std.conv;
import std.format;
import std.datetime;

import std.file;

private
void process_key_down(GlobalState gs, SDL_Scancode scancode)
{
    if (gs.mark || gs.gomark || gs.unmark)
    {
        string scancode_name = fromStringz(SDL_GetScancodeName(scancode)).idup();
        if (scancode_name.length == 1 &&
                (scancode_name >= "0" && scancode_name <= "9" ||
                scancode_name >= "A" && scancode_name <= "Z"))
        { 
            if (gs.shift || scancode_name >= "0" && scancode_name <= "9")
            {
                if (gs.mark)
                    mark(gs, scancode_name);
                else if (gs.unmark)
                    unmark(gs, scancode_name);
                else if (gs.gomark)
                    go_mark(gs, scancode_name);

                gs.dirty = true;
            }
            else
            {
                string msg = format("Only global marks (from 'A' to 'Z', not 'a' to 'z') works in file manager.");
                gs.messages ~= ConsoleMessage(
                        SDL_Color(0xFF, 0x00, 0x00, 0xFF),
                        msg,
                        SDL_GetTicks()
                        );
                writeln(msg);
            }
        }

        if ( scancode != SDL_SCANCODE_LSHIFT && scancode != SDL_SCANCODE_RSHIFT )
        {
            gs.mark=false;
            gs.gomark=false;
            gs.unmark=false;
            return;
        }
    }

    switch(scancode)
    { 
        case SDL_SCANCODE_Q:
            if (gs.current_path !in gs.enter_names)
                gs.finish=true;
            break;

        case SDL_SCANCODE_PRINTSCREEN:
            make_screenshot(gs);
            break;

        case SDL_SCANCODE_M:
            if (gs.current_path !in gs.enter_names)
            {
                if (gs.shift)
                    gs.unmark = true;
                else
                    gs.mark = true;
            }
            break;
        case SDL_SCANCODE_APOSTROPHE:
            if (gs.current_path !in gs.enter_names)
            {
                gs.gomark = true;
            }
            break;

        case SDL_SCANCODE_R:
            if (gs.current_path !in gs.enter_names)
            {
                rescan_path(gs, PathMnt(gs.lsblk, gs.full_current_path));
            }
            break;

        case SDL_SCANCODE_A:
            if (gs.current_path !in gs.enter_names)
            {
                gs.selection_hash = null;
                calculate_selection_sub(gs);
                gs.dirty = true;
            }
            break;

        case SDL_SCANCODE_LEFT:
            if (gs.current_path in gs.enter_names)
            {
                with(gs.enter_names[gs.current_path])
                {
                    if (pos > 0)
                        pos -= name.strideBack(pos);
                }
                gs.dirty = true;
            }
            break; 

        case SDL_SCANCODE_RIGHT:
            if (gs.current_path in gs.enter_names)
            {
                with(gs.enter_names[gs.current_path])
                {
                    if (pos < name.length)
                        pos += name.stride(pos);
                }
                gs.dirty = true;
            }
            break; 

        case SDL_SCANCODE_LSHIFT:
            goto case;
        case SDL_SCANCODE_RSHIFT:
            gs.shift = true;
            break;

        case SDL_SCANCODE_RETURN:
            if (gs.current_path in gs.enter_names)
            {
                with(gs.enter_names[gs.current_path])
                {
                    if (name != "")
                    {
                        final switch (type)
                        {
                            case NameType.CreateDirectory:
                                try{
                                    string path = gs.full_current_path ~ SL ~
                                        name;
                                    mkdir(path);
                                    gs.animation_info[path] =
                                        AnimationInfo();
                                    gs.animation_info[path].parent =
                                        gs.full_current_path;
                                    gs.animation_info[path].type =
                                        NameType.CreateDirectory;
                                    gs.dirty = true;
                                }
                                catch (FileException exp)
                                {
                                    string msg = format("Failed Create Directory: %s", exp.msg);
                                    gs.messages ~= ConsoleMessage(
                                            SDL_Color(0xFF, 0x00, 0x00, 0xFF),
                                            msg,
                                            SDL_GetTicks()
                                            );
                                    writeln(msg);
                                }
                                break;

                            case NameType.Copy:
                                goto case;
                            case NameType.Move:
                                string path = gs.full_current_path ~ SL ~
                                    name;
                                string[] selection = gs.selection_hash.keys;
                                try
                                {
                                    auto de = DirEntry(selection[0]);
                                    if (!de.isSymlink() && de.isDir())
                                    {
                                        selection[0] ~= SL;//It is the single entry
                                    }
                                }
                                catch(Exception e)
                                {
                                    // Ignore errors
                                }

                                if (type == NameType.Copy)
                                { 
                                    copy_paths(gs, selection.idup(), path, gs.shift_copy_or_move);
                                }
                                else
                                {
                                    move_paths(gs, selection.idup(), path, gs.shift_copy_or_move);
                                }
                                gs.animation_info[path] =
                                    AnimationInfo();
                                gs.animation_info[path].parent =
                                    gs.full_current_path;
                                gs.animation_info[path].type =
                                    type;
                                gs.animation_info[path].stage =
                                    1;
                                gs.dirty = true;
                                break;
                        }
                    }
                    goto case;
                }
            }
            break; 

        case SDL_SCANCODE_ESCAPE:
            SDL_StopTextInput();

            gs.redraw_fast = false;
            change_current_dir(gs, 
                    (ref RectSize rectsize)
                    {
                        rectsize.show_info = InfoType.None;
                        gs.enter_names.remove(gs.current_path);
                    } );

            if (SDL_GetTicks() - gs.last_escape < DOUBLE_DELAY)
            {
                gs.msg_stamp = Clock.currTime().toUnixTime() - 10;
                gs.dirty = true;
            }
            gs.last_escape = SDL_GetTicks();
            break;

        case SDL_SCANCODE_BACKSPACE:
            RectSize rectsize = getRectSize(gs);
            with(gs.enter_names[gs.current_path])
            {
                if ( (rectsize.show_info == InfoType.CreateDirectory ||
                            rectsize.show_info == InfoType.Copy ||
                            rectsize.show_info == InfoType.Move) &&
                       name > "" && pos > 0 )
                {
                    int sb = name.strideBack(pos);
                    name = (name[0..pos-sb] ~ name[pos..$]).idup();
                    pos -= sb;
                    gs.dirty = true;
                }
            }
            break;

        case SDL_SCANCODE_F5:
            goto case;
        case SDL_SCANCODE_F6:
            int copy_or_move_to_the_same_directory = 0;
            int copy_or_move_to_subdirectory = 0;
            foreach (selection; gs.selection_hash.byKey())
            {
                string parent = 
                    getParent(selection);
                if (parent == "") parent = SL;
                if (parent == gs.full_current_path)
                    copy_or_move_to_the_same_directory++;

                if ( gs.full_current_path.startsWith(selection) )
                    copy_or_move_to_subdirectory++;
            }

            if (copy_or_move_to_the_same_directory &&
                    gs.selection_hash.length > 1)
            {
                string msg;
                if (scancode == SDL_SCANCODE_F5)
                    msg = format("Copy to the same directory works only for exactly 1 selection");
                else
                    msg = format("Rename (move to the same directory) works only for exactly 1 selection");
                gs.messages ~= ConsoleMessage(
                        SDL_Color(0xFF, 0xFF, 0xFF, 0xFF),
                        msg,
                        SDL_GetTicks() );
                writeln(msg);
            }
            else if (copy_or_move_to_subdirectory)
            {
                string msg;
                if (scancode == SDL_SCANCODE_F5)
                    msg = format("Can't copy to a subdirectory");
                else
                    msg = format("Can't move to a subdirectory");
                gs.messages ~= ConsoleMessage(
                        SDL_Color(0xFF, 0x00, 0x00, 0xFF),
                        msg,
                        SDL_GetTicks() );
                writeln(msg);
            }
            else
            {
                if (copy_or_move_to_the_same_directory &&
                        gs.selection_hash.length == 1)
                {
                    gs.shift_copy_or_move = gs.shift;
                    string path = gs.selection_hash.keys[0];
                    gs.animation_info[path] =
                        AnimationInfo();
                    gs.animation_info[path].parent =
                        gs.full_current_path;
                    if (scancode == SDL_SCANCODE_F5)
                        gs.animation_info[path].type =
                            NameType.Copy;
                    else
                        gs.animation_info[path].type =
                            NameType.Move;

                    SDL_StartTextInput();
                    gs.redraw_fast = true;
                    change_current_dir(gs, 
                            (ref RectSize rectsize)
                            {
                                if (rectsize.show_info != 
                                      InfoType.CreateDirectory &&
                                        rectsize.show_info != InfoType.Copy &&
                                        rectsize.show_info != InfoType.Move)
                                {
                                    rectsize.show_info = InfoType.Copy;
                                    string name = 
                                        path[path.lastIndexOf(SL)+1..$];
                                    if (scancode == SDL_SCANCODE_F5)
                                        gs.enter_names[gs.current_path] =
                                            EnterName(NameType.Copy, name, 
                                                    cast(int)name.length);
                                    else
                                        gs.enter_names[gs.current_path] =
                                            EnterName(NameType.Move, name, 
                                                    cast(int)name.length);
                                }
                            } );
                }
                else
                {
                    // copy_or_move_paths algorithm wants SL at the end
                    string path = gs.full_current_path ~ SL;
                    if (scancode == SDL_SCANCODE_F5)
                        copy_paths(gs, gs.selection_hash.keys, path, gs.shift);
                    else
                        move_paths(gs, gs.selection_hash.keys, path, gs.shift);
                    gs.dirty = true;
                }
            }

            break;

        case SDL_SCANCODE_F7:
            SDL_StartTextInput();
            gs.redraw_fast = true;
            change_current_dir(gs, 
                    (ref RectSize rectsize)
                    {
                        if (rectsize.show_info != InfoType.CreateDirectory &&
                                rectsize.show_info != InfoType.Copy &&
                                rectsize.show_info != InfoType.Move)
                        {
                            rectsize.show_info = InfoType.CreateDirectory;
                            gs.enter_names[gs.current_path] = 
                                EnterName(NameType.CreateDirectory, "", 0);
                        }
                    } );
            break;

        case SDL_SCANCODE_F8:
            bool not_fit_on_screen = false;
            foreach(path, ref rect; gs.selection_hash)
            {
                SDL_Rect sdl_rect = rect.to_screen(gs.screen);

                if (sdl_rect.x < 0 || sdl_rect.y < 0 ||
                        (sdl_rect.x+sdl_rect.w) > gs.screen.w ||
                        (sdl_rect.y+sdl_rect.h) > gs.screen.h)
                {
                    not_fit_on_screen = true;
                    break;
                }
            }

            if (not_fit_on_screen)
            {
                string msg = format("Go (up) to directory which fully covers selection to confirm removing %d items",
                            gs.selection_hash.length);
                gs.messages ~= ConsoleMessage(
                        SDL_Color(0xFF, 0xFF, 0xFF, 0xFF),
                        msg,
                        SDL_GetTicks() );
                writeln(msg);
            }
            else
            {
                remove_paths(gs, gs.selection_hash.keys);
            }

            break;

        case SDL_SCANCODE_S:
            if (gs.current_path !in gs.enter_names)
            {
                change_current_dir(gs, 
                        (ref RectSize rectsize)
                        {
                            rectsize.sort = cast(SortType)( (rectsize.sort+1)%(SortType.max+1) );
                        } );
            }
            break;

        default:
            break;
    }
}

void process_event(GlobalState gs, ref SDL_Event event)
{
    switch( event.type )
    {
        case SDL_TEXTINPUT:
            RectSize rectsize = getRectSize(gs);
            if (rectsize.show_info == InfoType.CreateDirectory ||
                    rectsize.show_info == InfoType.Copy ||
                    rectsize.show_info == InfoType.Move)
            {
                with(gs.enter_names[gs.current_path])
                {
                    char[] input = fromStringz(cast(char*)event.text.text);
                    name = 
                        (name[0..pos] ~
                        input ~
                        name[pos..$]).idup();
                    pos += input.length;
                    gs.dirty = true;
                }
            }
            break;

        case SDL_KEYDOWN:
            process_key_down(gs, event.key.keysym.scancode);
            break;

        case SDL_KEYUP:
            switch(event.key.keysym.scancode)
            { 
                case SDL_SCANCODE_LSHIFT:
                    goto case;
                case SDL_SCANCODE_RSHIFT:
                    gs.shift = false;
                    break;
                default:
                    /* Ignore key */
                    break;
            }
            break;
            
        case SDL_MOUSEMOTION:
            if (gs.mouse_buttons & unDE_MouseButtons.Left)
            {
                gs.screen.x -= cast(double)(event.motion.xrel)*gs.screen.scale;
                gs.screen.y -= cast(double)(event.motion.yrel)*gs.screen.scale;
            }

            gs.mousex = event.motion.x * gs.screen.scale + gs.screen.x;
            gs.mousey = event.motion.y * gs.screen.scale + gs.screen.y;
            gs.mouse_screen_x = event.motion.x;
            gs.mouse_screen_y = event.motion.y;
            gs.moved_while_click++;

            if (gs.mouse_buttons & unDE_MouseButtons.Right)
            {
                process_click(gs.right_clickable_list, gs.mouse_screen_x, gs.mouse_screen_y, 1);
            }
            break;
            
        case SDL_MOUSEBUTTONDOWN:
            switch (event.button.button)
            {
                case SDL_BUTTON_LEFT:
                    gs.mouse_buttons |= unDE_MouseButtons.Left;
                    gs.moved_while_click = 0;
                    break;
                case SDL_BUTTON_MIDDLE:
                    gs.mouse_buttons |= unDE_MouseButtons.Middle;
                    break;
                case SDL_BUTTON_RIGHT:
                    gs.mouse_buttons |= unDE_MouseButtons.Right;
                    process_click(gs.right_clickable_list, gs.mouse_screen_x, gs.mouse_screen_y, 0);
                    break;
                default:
                    break;
            }
            break;
            
        case SDL_MOUSEBUTTONUP:
            switch (event.button.button)
            {
                case SDL_BUTTON_LEFT:
                    gs.mouse_buttons &= ~unDE_MouseButtons.Left;
                    if (!gs.moved_while_click)
                    {
                        if (SDL_GetTicks() - gs.last_left_click < DOUBLE_DELAY)
                        {
                            process_click(gs.double_clickable_list, gs.mouse_screen_x, gs.mouse_screen_y);
                        }
                        else
                        {
                            process_click(gs.clickable_list, gs.mouse_screen_x, gs.mouse_screen_y);
                        }
                        gs.last_left_click = SDL_GetTicks();
                    }
                    break;
                case SDL_BUTTON_MIDDLE:
                    gs.mouse_buttons &= ~unDE_MouseButtons.Middle;
                    process_click(gs.middle_clickable_list, gs.mouse_screen_x, gs.mouse_screen_y, 2);
                    break;
                case SDL_BUTTON_RIGHT:
                    gs.mouse_buttons &= ~unDE_MouseButtons.Right;
                    if (SDL_GetTicks() - gs.last_right_click < DOUBLE_DELAY)
                    {
                        process_click(gs.double_right_clickable_list, gs.mouse_screen_x, gs.mouse_screen_y);
                    }
                    process_click(gs.right_clickable_list, gs.mouse_screen_x, gs.mouse_screen_y, 2);
                    gs.last_right_click = SDL_GetTicks();
                    break;
                default:
                    break;
            }
            break;

        case SDL_MOUSEWHEEL:
            while (event.wheel.y > 0)
            {
                gs.screen.scale /= 1.0905;
                event.wheel.y--;
            }
            while (event.wheel.y < 0)
            {
                gs.screen.scale *= 1.0905;
                event.wheel.y++;
            }
            gs.screen.x = gs.mousex - gs.mouse_screen_x*gs.screen.scale;
            gs.screen.y = gs.mousey - gs.mouse_screen_y*gs.screen.scale;
            //writeln("scale=", scale);
            break;
            
        case SDL_JOYAXISMOTION:
            /* Do something with event.jaxis */
            break;
            
        case SDL_JOYBALLMOTION:
            /* Do something with event.jball */
            break;
            
        case SDL_JOYHATMOTION:
            /* Do something with event.jhat */
            break;
            
        case SDL_JOYBUTTONDOWN:
            /* Do something with event.jbutton */
            break;
            
        case SDL_JOYBUTTONUP:
            /* Do something event.jbutton */
            break;

        case SDL_QUIT:
            /* Do something event.quit */
            gs.finish=true;
            break;
            
        case SDL_SYSWMEVENT:
            /* Do something with event.syswm */
            break;
            
        case SDL_WINDOWEVENT:
            /*if (event.window.event == SDL_WINDOWEVENT_RESIZED)
                diz_setvideomode(event.window.data1, event.window.data2, 
                  dizvideomode.flags & SDL_WINDOW_FULLSCREEN_DESKTOP);*/
            break;
        default:
            writeln("Ignored event: "~to!string(event.type));
            break;
    }
}
