module unde.viewers.image_viewer.events;

import unde.global_state;
import unde.lib;
import unde.tick;
import unde.marks;
import unde.viewers.image_viewer.lib;

import derelict.sdl2.sdl;

import std.stdio;
import std.string;

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

        case SDL_SCANCODE_LEFT:
            image_prev(gs);
            break; 

        case SDL_SCANCODE_RIGHT:
            image_next(gs);
            break; 

        case SDL_SCANCODE_0:
            setup_0_scale(gs);
            break; 

        case SDL_SCANCODE_1:
            setup_1_scale(gs);
            break; 

        case SDL_SCANCODE_A:
            gs.selection_hash = null;
            calculate_selection_sub(gs);
            gs.dirty = true;
            break;

        case SDL_SCANCODE_R:
            with (gs.image_viewer)
            {
                if (gs.shift)
                {
                    rectsize.angle -= 90;
                    if (rectsize.angle <= -89)
                    {
                        rectsize.angle = 270;
                    } 
                }
                else
                {
                    rectsize.angle += 90;
                    if (rectsize.angle >= 359)
                    {
                        rectsize.angle = 0;
                    } 
                }

                rectsize.type = FileType.Image;
                put_rectsize(gs);
            }
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
                with (gs.image_viewer)
                {
                    if (texture_tick && texture_tick.texture)
                    {
                        rect.x += event.motion.xrel;
                        rect.y += event.motion.yrel;
                    }
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
                    gs.mouse_buttons &= ~unDE_MouseButtons.Left;
                    if (!gs.moved_while_click)
                    {
                        if (SDL_GetTicks() - gs.last_left_click < DOUBLE_DELAY)
                        {
                            gs.state = State.FileManager;
                            gs.dirty = true;
                        }
                        else
                        {
                        }
                        gs.last_left_click = SDL_GetTicks();
                    }
                    break;
                case SDL_BUTTON_MIDDLE:
                    gs.mouse_buttons &= ~unDE_MouseButtons.Middle;
                    break;
                case SDL_BUTTON_RIGHT:
                    gs.mouse_buttons &= ~unDE_MouseButtons.Right;

                    with (gs.image_viewer)
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
            with (gs.image_viewer)
            {
                if (texture_tick && texture_tick)
                {
                    int mouse_center_x = gs.mouse_screen_x-rect.x;
                    int mouse_center_y = gs.mouse_screen_y-rect.y;
                    int oldw = rect.w;
                    int oldh = rect.h;

                    while (event.wheel.y > 0)
                    {
                        rect.w = cast(int)(rect.w * 1.0905);
                        rect.h = cast(int)(rect.h * 1.0905);
                        event.wheel.y--;
                    }

                    if (oldw > 20 && oldh > 20)
                    {
                        while (event.wheel.y < 0)
                        {
                            rect.w = cast(int)(rect.w / 1.0905);
                            rect.h = cast(int)(rect.h / 1.0905);
                            event.wheel.y++;
                        }
                    }

                    int mouse_center_x2 = mouse_center_x * rect.w/oldw;
                    int mouse_center_y2 = mouse_center_y * rect.h/oldh;
                    rect.x = gs.mouse_screen_x - mouse_center_x2;
                    rect.y = gs.mouse_screen_y - mouse_center_y2;
                }
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
