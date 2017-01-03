module unde.viewers.text_viewer.events;

import unde.global_state;
import unde.lib;
import unde.tick;
import unde.marks;
import unde.viewers.text_viewer.lib;

import derelict.sdl2.sdl;

import std.stdio;
import std.string;
import std.math;

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
                string msg = format("local marks not implemented.");
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
            make_screenshot(gs);
            gs.finish=true;
            break;
        case SDL_SCANCODE_M:
            if (gs.shift)
                gs.unmark = true;
            else
                gs.mark = true;
            break;
        case SDL_SCANCODE_APOSTROPHE:
            gs.gomark = true;
            break;

        case SDL_SCANCODE_W:
            with (gs.text_viewer)
            {
                wraplines = !wraplines;
                if (wraplines)
                {
                    x = 0;
                }
                last_redraw = 0;
            }
            break;

        case SDL_SCANCODE_G:
            with (gs.text_viewer)
            {
                if (gs.shift)
                {
                    File file;
                    try {
                        file = File(path);
                    }
                    catch (Exception exp)
                    {
                        break;
                    }
                    rectsize.offset = file.size;
                    y = gs.screen.h;
                }
                else
                {
                    rectsize.offset = 0;
                    y = 0;
                    put_rectsize(gs);
                }
                last_redraw = 0;
            }
            break;

        case SDL_SCANCODE_PAGEUP:
            with (gs.text_viewer)
            {
                int line_height = cast(int)(round(SQRT2^^9)*1.2);
                y += gs.screen.h - 2*line_height;
            }
            break;

        case SDL_SCANCODE_PAGEDOWN:
            with (gs.text_viewer)
            {
                int line_height = cast(int)(round(SQRT2^^9)*1.2);
                y -= gs.screen.h - 2*line_height;
            }
            break;

        case SDL_SCANCODE_A:
            gs.selection_hash = null;
            calculate_selection_sub(gs);
            gs.dirty = true;
            break;

        case SDL_SCANCODE_UP:
            break;

        case SDL_SCANCODE_DOWN:
            break;

        case SDL_SCANCODE_LEFT:
            text_prev(gs);
            break; 

        case SDL_SCANCODE_RIGHT:
            text_next(gs);
            break; 

        case SDL_SCANCODE_LSHIFT:
            goto case;
        case SDL_SCANCODE_RSHIFT:
            gs.shift = true;
            break;

        default:
            break;
    }
}

void process_event(GlobalState gs, ref SDL_Event event)
{
    switch( event.type )
    {
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
                with (gs.text_viewer)
                {
                    if (gs.command_line.ctrl_mode ^ gs.command_line.ctrl)
                    {
                        if (mouse_offset > first_click)
                        {
                            start_selection = first_click;
                            end_selection = mouse_offset;
                        }
                        else
                        {
                            start_selection = mouse_offset;
                            end_selection = first_click;
                        }
                    }
                    else
                    {
                        if (!wraplines)
                            x += event.motion.xrel;
                        y += event.motion.yrel;
                    }
                    last_redraw = 0;
                }
            }
            gs.mouse_screen_x = event.motion.x;
            gs.mouse_screen_y = event.motion.y;
            gs.moved_while_click++;
            break;
            
        case SDL_MOUSEBUTTONDOWN:
            switch (event.button.button)
            {
                case SDL_BUTTON_LEFT:
                    gs.mouse_buttons |= unDE_MouseButtons.Left;
                    gs.moved_while_click = 0;
                    with (gs.text_viewer)
                    {
                        if (gs.command_line.ctrl_mode ^ gs.command_line.ctrl)
                        {
                            first_click = mouse_offset;
                        }
                    }
                    break;
                case SDL_BUTTON_MIDDLE:
                    gs.mouse_buttons |= unDE_MouseButtons.Middle;
                    break;
                case SDL_BUTTON_RIGHT:
                    gs.mouse_buttons |= unDE_MouseButtons.Right;
                    break;
                default:
                    break;
            }
            break;
            
        case SDL_MOUSEBUTTONUP:
            switch (event.button.button)
            {
                case SDL_BUTTON_LEFT:
                    with(gs.text_viewer)
                    {
                        gs.mouse_buttons &= ~unDE_MouseButtons.Left;
                        if (!gs.moved_while_click)
                        {
                            if (SDL_GetTicks() - gs.last_left_click < DOUBLE_DELAY)
                            {
                                gs.state = State.FileManager;
                                gs.dirty = true;
                            }
                            else if (gs.command_line.shift)
                            {
                                if (mouse_offset > first_click)
                                {
                                    end_selection = mouse_offset;
                                }
                                else
                                {
                                    start_selection = mouse_offset;
                                }
                                selection_to_buffer(gs);
                            }
                            else if (gs.command_line.ctrl_mode ^ gs.command_line.ctrl)
                            {
                                start_selection = -1;
                                end_selection = -1;
                                last_redraw = 0;
                            }
                            gs.last_left_click = SDL_GetTicks();
                        }
                        else if (gs.command_line.ctrl_mode ^ gs.command_line.ctrl)
                        {
                            if (mouse_offset > first_click)
                            {
                                start_selection = first_click;
                                end_selection = mouse_offset;
                            }
                            else
                            {
                                start_selection = mouse_offset;
                                end_selection = first_click;
                            }
                            last_redraw = 0;
                            selection_to_buffer(gs);
                        }
                    }
                    break;
                case SDL_BUTTON_MIDDLE:
                    gs.mouse_buttons &= ~unDE_MouseButtons.Middle;
                    break;
                case SDL_BUTTON_RIGHT:
                    gs.mouse_buttons &= ~unDE_MouseButtons.Right;

                    with (gs.text_viewer)
                    {
                        if (path in gs.selection_hash)
                            gs.selection_hash.remove(path);
                        else
                            /* EN: FIXME: Sort type of the directory maybe other
                               RU: ИСПРАВЬ_МЕНЯ: Сортировка директории может быть другой */
                            gs.selection_hash[path] = rectsize.rect(SortType.BySize);
                    }

                    break;
                default:
                    break;
            }
            break;

        case SDL_MOUSEWHEEL:
            with (gs.text_viewer)
            {
                if (gs.command_line.ctrl_mode ^ gs.command_line.ctrl)
                {
                    y += event.wheel.y * 40;
                }
                else
                {
                    fontsize += event.wheel.y;

                    if (fontsize < 5) fontsize = 5;
                    if (fontsize > 15) fontsize = 15;
                }
                last_redraw = 0;
            }
            break;
            
        case SDL_QUIT:
            /* Do something event.quit */
            gs.finish=true;
            break;
            
        default:
            //writeln("Ignored event: "~to!string(event.type));
            break;
    }
}
