module unde.viewers.text_viewer.events;

import unde.global_state;
import unde.lib;
import unde.tick;
import unde.viewers.text_viewer.lib;
import unde.file_manager.events;
import unde.command_line.events;
import unde.keybar.lib;
import unde.translations.lib;

import derelict.sdl2.sdl;

import std.stdio;
import std.string;
import std.math;
import std.functional;

private void
change_wrap_mode(GlobalState gs)
{
    with (gs.text_viewer)
    {
        wraplines = !wraplines;
        if (wraplines)
        {
            x = 0;
        }
        last_redraw = 0;
    }
}

private void
go_to_beginning_or_to_the_end(GlobalState gs)
{
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
                return;
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
}

private void
textviewer_page_up(GlobalState gs)
{
    with (gs.text_viewer)
    {
        int line_height = cast(int)(round(SQRT2^^9)*1.2);
        y += gs.screen.h - 2*line_height;
    }
}

private void
textviewer_page_down(GlobalState gs)
{
    with (gs.text_viewer)
    {
        int line_height = cast(int)(round(SQRT2^^9)*1.2);
        y -= gs.screen.h - 2*line_height;
    }
}

void process_event(GlobalState gs, ref SDL_Event event)
{
    switch( event.type )
    {
        case SDL_MOUSEMOTION:
            if (gs.mouse_buttons & unDE_MouseButtons.Left)
            {
                with (gs.text_viewer)
                {
                    if (gs.command_line.ctrl_mode ^ gs.ctrl)
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
                        if (gs.command_line.ctrl_mode ^ gs.ctrl)
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
            if (gs.mouse_screen_x < gs.screen.w)
            {
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
                                else if (gs.shift)
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
                                else if (gs.command_line.ctrl_mode ^ gs.ctrl)
                                {
                                    start_selection = -1;
                                    end_selection = -1;
                                    last_redraw = 0;
                                }
                                gs.last_left_click = SDL_GetTicks();
                            }
                            else if (gs.command_line.ctrl_mode ^ gs.ctrl)
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
            }
            break;

        case SDL_MOUSEWHEEL:
            with (gs.text_viewer)
            {
                if (gs.command_line.ctrl_mode ^ gs.ctrl)
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

void
setup_keybar_textviewer_default(GlobalState gs)
{
    gs.keybar.handlers.clear();
    gs.keybar.handlers_down.clear();
    gs.keybar.handlers_double.clear();

    gs.keybar.handlers[SDL_SCANCODE_Q] = KeyHandler(toDelegate(&quit), _("Quit"), "exit.png");
    gs.keybar.handlers[SDL_SCANCODE_PRINTSCREEN] = KeyHandler(toDelegate(&make_screenshot), _("Make screenshot"), "Prt Sc");
    gs.keybar.handlers[SDL_SCANCODE_M] = KeyHandler(toDelegate(&mark), _("Make Mark"), "mark.png");
    gs.keybar.handlers[SDL_SCANCODE_APOSTROPHE] = KeyHandler(toDelegate(&gomark), _("Go To Mark"), "gomark.png");
    gs.keybar.handlers[SDL_SCANCODE_A] = KeyHandler(toDelegate(&deselect_all), _("Clear selection"), "deselect.png");
    gs.keybar.handlers_down[SDL_SCANCODE_LSHIFT] = KeyHandler(toDelegate(&setup_keybar_textviewer_shift), "", "Shift");
    gs.keybar.handlers_down[SDL_SCANCODE_RSHIFT] = KeyHandler(toDelegate(&setup_keybar_textviewer_shift), "", "");
    gs.keybar.handlers[SDL_SCANCODE_LEFT] = KeyHandler(toDelegate(&text_prev), _("Next Text"), "←");
    gs.keybar.handlers[SDL_SCANCODE_RIGHT] = KeyHandler(toDelegate(&text_next), _("Prev Text"), "→");
    gs.keybar.handlers[SDL_SCANCODE_W] = KeyHandler(toDelegate(&change_wrap_mode), _("On/Off wrap lines"), "Wrap");
    gs.keybar.handlers[SDL_SCANCODE_G] = KeyHandler(toDelegate(&go_to_beginning_or_to_the_end), _("Go To Beginining"), "Begin");
    gs.keybar.handlers[SDL_SCANCODE_PAGEUP] = KeyHandler(toDelegate(&textviewer_page_up), _("Page Up"), "PgUp");
    gs.keybar.handlers[SDL_SCANCODE_PAGEDOWN] = KeyHandler(toDelegate(&textviewer_page_down), _("Page Down"), "PgD");
    gs.keybar.handlers_double[SDL_SCANCODE_LCTRL] = KeyHandler(toDelegate(&turn_on_off_ctrl_mode), _("Ctrl Mode"), "Ctrl");
    gs.keybar.handlers_double[SDL_SCANCODE_RCTRL] = KeyHandler(toDelegate(&turn_on_off_ctrl_mode), "", "");
}

void
setup_keybar_textviewer_shift(GlobalState gs)
{
    gs.keybar.handlers.clear();
    gs.keybar.handlers_down.clear();
    gs.keybar.handlers_double.clear();

    gs.keybar.handlers[SDL_SCANCODE_M] = KeyHandler(toDelegate(&unmark), _("Delete Mark"), "unmark.png");
    gs.keybar.handlers[SDL_SCANCODE_G] = KeyHandler(toDelegate(&go_to_beginning_or_to_the_end), _("Go To End"), "End");
    gs.keybar.handlers[SDL_SCANCODE_LSHIFT] = KeyHandler(toDelegate(&setup_keybar_textviewer_default), "", "Shift");
    gs.keybar.handlers[SDL_SCANCODE_RSHIFT] = KeyHandler(toDelegate(&setup_keybar_textviewer_default), "", "");
}
