module unde.viewers.image_viewer.events;

import unde.global_state;
import unde.lib;
import unde.tick;
import unde.viewers.image_viewer.lib;
import unde.file_manager.events;
import unde.keybar.lib;
import unde.translations.lib;

import derelict.sdl2.sdl;

import std.stdio;
import std.string;
import std.functional;

void rotate(GlobalState gs)
{
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
}

void process_event(GlobalState gs, ref SDL_Event event)
{
    switch( event.type )
    {
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
            if (gs.mouse_screen_x < gs.screen.w)
            {
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

void
setup_keybar_imageviewer_default(GlobalState gs)
{
    gs.keybar.handlers.clear();
    gs.keybar.handlers_down.clear();
    gs.keybar.handlers_double.clear();

    gs.keybar.handlers[SDL_SCANCODE_Q] = KeyHandler(toDelegate(&quit), _("Quit"), "exit.png");
    gs.keybar.handlers[SDL_SCANCODE_PRINTSCREEN] = KeyHandler(toDelegate(&make_screenshot), _("Make screenshot"), "Prt Sc");
    gs.keybar.handlers[SDL_SCANCODE_M] = KeyHandler(toDelegate(&mark), _("Make Mark"), "mark.png");
    gs.keybar.handlers[SDL_SCANCODE_APOSTROPHE] = KeyHandler(toDelegate(&gomark), _("Go To Mark"), "gomark.png");
    gs.keybar.handlers[SDL_SCANCODE_A] = KeyHandler(toDelegate(&deselect_all), _("Clear selection"), "deselect.png");
    gs.keybar.handlers_down[SDL_SCANCODE_LSHIFT] = KeyHandler(toDelegate(&setup_keybar_imageviewer_shift), "", "Shift");
    gs.keybar.handlers_down[SDL_SCANCODE_RSHIFT] = KeyHandler(toDelegate(&setup_keybar_imageviewer_shift), "", "");
    gs.keybar.handlers[SDL_SCANCODE_LEFT] = KeyHandler(toDelegate(&image_prev), _("Next Image"), "←");
    gs.keybar.handlers[SDL_SCANCODE_RIGHT] = KeyHandler(toDelegate(&image_next), _("Prev Image"), "→");
    gs.keybar.handlers[SDL_SCANCODE_0] = KeyHandler(toDelegate(&setup_0_scale), _("Fit on the screen"), "0");
    gs.keybar.handlers[SDL_SCANCODE_1] = KeyHandler(toDelegate(&setup_1_scale), _("100% Scale"), "100%");
    gs.keybar.handlers[SDL_SCANCODE_R] = KeyHandler(toDelegate(&rotate), _("Rotate right"), "rotate_right.png");
}

void
setup_keybar_imageviewer_shift(GlobalState gs)
{
    gs.keybar.handlers.clear();
    gs.keybar.handlers_down.clear();
    gs.keybar.handlers_double.clear();

    gs.keybar.handlers[SDL_SCANCODE_M] = KeyHandler(toDelegate(&unmark), _("Delete Mark"), "unmark.png");
    gs.keybar.handlers[SDL_SCANCODE_R] = KeyHandler(toDelegate(&rotate), _("Rotate left"), "rotate_left.png");
    gs.keybar.handlers[SDL_SCANCODE_LSHIFT] = KeyHandler(toDelegate(&setup_keybar_imageviewer_default), "", "Shift");
    gs.keybar.handlers[SDL_SCANCODE_RSHIFT] = KeyHandler(toDelegate(&setup_keybar_imageviewer_default), "", "");
}

