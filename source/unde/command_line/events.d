module unde.command_line.events;

import unde.global_state;
import unde.lib;
import unde.tick;
import unde.marks;
import unde.command_line.run;
import unde.command_line.lib;
import unde.file_manager.events;
import unde.keybar.lib;

import derelict.sdl2.sdl;

import std.stdio;
import std.string;
import std.utf;
import std.math;
import std.concurrency;
import std.functional;

enum CommandLineEventHandlerResult
{
    Pass,
    Block
}

void
turn_on_off_ctrl_mode(GlobalState gs)
{
    gs.command_line.ctrl_mode = !gs.command_line.ctrl_mode;
}

void
turn_off_terminal(GlobalState gs)
{
    gs.command_line.terminal = false;
    gs.keybar.handlers_double[SDL_SCANCODE_RETURN] = KeyHandler(toDelegate(&turn_on_terminal), "Open Terminal", "terminal.png");
    gs.keybar.handlers.remove(SDL_SCANCODE_ESCAPE);
}

void
turn_on_terminal(GlobalState gs)
{
    gs.command_line.terminal = true;
    gs.keybar.handlers_double.remove(SDL_SCANCODE_RETURN);
    gs.keybar.handlers[SDL_SCANCODE_ESCAPE] = KeyHandler(toDelegate(&turn_off_terminal), "Close terminal", "terminal.png");
}

void
turn_on_command_line(GlobalState gs)
{
    gs.command_line.just_started_input = true;
    writefln("Command line open");
    gs.command_line.enter = true;
    gs.keybar.input_mode = true;
    setup_keybar_command_line_default(gs);
}

void
turn_off_command_line(GlobalState gs)
{
    with (gs.command_line)
    {
        if (search_mode)
        {
            search_mode = false;
            search = "";
            pos = command.length;
        }
        else
        {
            if (!terminal || command_in_focus_id == 0)
            {
                gs.keybar.input_mode = false;
            }
            writefln("Command line close");
            enter = false;
            setup_keybar_filemanager_default(gs);
        }
    }
}

private void
command_line_left(GlobalState gs)
{
    with (gs.command_line)
    {
        if (search_mode && hist_pos == 0)
        {
            if (pos > 0)
                pos -= search.strideBack(pos);
        }
        else
        {
            if (pos > 0)
                pos -= command.strideBack(pos);
        }
    }
}

private void
command_line_right(GlobalState gs)
{
    with (gs.command_line)
    {
        if (search_mode && hist_pos == 0)
        {
            if (pos < search.length)
                pos += search.stride(pos);
        }
        else
        {
            if (pos < command.length)
                pos += command.stride(pos);
        }
    }
}

private void
command_line_backspace(GlobalState gs)
{
    with (gs.command_line)
    {
        if (search_mode && hist_pos == 0)
        {
            if ( search > "" && pos > 0 )
            {
                int sb = search.strideBack(pos);
                search = (search[0..pos-sb] ~ search[pos..$]).idup();
                pos -= sb;
            }
        }
        else
        {
            if ( command > "" && pos > 0 )
            {
                int sb = command.strideBack(pos);
                command = (command[0..pos-sb] ~ command[pos..$]).idup();
                pos -= sb;
            }
        }
    }
}

private void
command_line_tab(GlobalState gs)
{
    with (gs.command_line)
    {
        if (complete.length > 1 && complete[0] == '1')
        {
            command = command[0..pos] ~ complete[1..$] ~ command[pos..$];
            pos += complete[1..$].length;
        }
    }
}

private void
command_line_search_mode_on(GlobalState gs)
{
    with (gs.command_line)
    {
        search_mode = true;
        pos = 0;
        hist_pos = 0;
    }

    gs.keybar.handlers[SDL_SCANCODE_ESCAPE] = KeyHandler(toDelegate(&turn_off_command_line), "Cancel search mode", "Esc");
}

private void
command_line_search_mode_off(GlobalState gs)
{
    with (gs.command_line)
    {
        search_mode = false;
    }
    gs.keybar.handlers[SDL_SCANCODE_ESCAPE] = KeyHandler(toDelegate(&turn_off_command_line), "Close command line", "command_line.png");
}

private void
command_line_delete(GlobalState gs)
{
    with (gs.command_line)
    {
        if ( command > "" && pos > 0 )
        {
            /*int sb = command.strideBack(pos);
              command = (command[0..pos-sb] ~ command[pos..$]).idup();
              pos -= sb;*/
        }
    }
}

private void
command_line_enter(GlobalState gs)
{
    with (gs.command_line)
    {
        if (gs.ctrl)
        {
            if (search_mode && hist_pos == 0)
            {
                search = (search[0..pos] ~
                        "\n" ~
                        search[pos..$]).idup();
            }
            else
            {
                command = (command[0..pos] ~
                        "\n" ~
                        command[pos..$]).idup();
            }
            pos++;
        }
        else
        {
            search_mode = false;
            search = "";
            run_command(gs, command);
            hist_cmd_id = 0;
            command = "";
            pos = 0;
            gs.keybar.input_mode = false;
            writefln("Command line close");
            gs.command_line.enter = false;
        }
    }
}

private auto
get_send_input(string input)
{
    return (GlobalState gs)
    {
        with (gs.command_line)
        {
            send(command_in_focus_tid, input);
        }
    };
}

private void
terminal_page_up(GlobalState gs)
{
    with (gs.command_line)
    {
        int line_height = cast(int)(round(SQRT2^^9)*1.2);
        y += gs.screen.h - 2*line_height;
        neg_y = 0;
    }
}

private void
terminal_page_down(GlobalState gs)
{
    with (gs.command_line)
    {
        int line_height = cast(int)(round(SQRT2^^9)*1.2);
        y -= gs.screen.h - 2*line_height;
        neg_y -= gs.screen.h - 2*line_height;
    }
}

CommandLineEventHandlerResult
process_event(GlobalState gs, ref SDL_Event event)
{
    auto result = CommandLineEventHandlerResult.Pass;

    if (gs.command_line.terminal)
    {
         result = CommandLineEventHandlerResult.Block;
    }

    switch( event.type )
    {
        case SDL_TEXTINPUT:
            with (gs.command_line)
            {
                if (enter)
                {
                    char[] input = fromStringz(cast(char*)event.text.text);

                    if (just_started_input && input == ";")
                    {
                        just_started_input = false;
                        return CommandLineEventHandlerResult.Block;
                    }
                    just_started_input = false;

                    if (search_mode && hist_pos == 0)
                    {
                        search = (search[0..pos] ~
                            input ~
                            search[pos..$]).idup();
                    }
                    else
                    {
                        command = (command[0..pos] ~
                            input ~
                            command[pos..$]).idup();
                    }
                    pos += input.length;
                    last_redraw = 0;
                }
                else if (command_in_focus_id > 0)
                {
                    char[] input = fromStringz(cast(char*)event.text.text);
                    send(command_in_focus_tid, input.idup());
                }
            }
            break;

        case SDL_MOUSEMOTION:
            if (gs.mouse_buttons & unDE_MouseButtons.Left)
            {
                with (gs.command_line)
                {
                    if (ctrl_mode ^ gs.ctrl)
                    {
                        if (mouse > first_click)
                        {
                            start_selection = first_click;
                            end_selection = mouse;
                        }
                        else
                        {
                            start_selection = mouse;
                            end_selection = first_click;
                        }
                    }
                    else
                    {
                        y += event.motion.yrel;
                        if (event.motion.yrel > 0)
                            neg_y = 0;
                        else
                            neg_y += event.motion.yrel;
                    }
                    last_redraw = 0;
                }
            }
            gs.mouse_screen_x = event.motion.x;
            gs.mouse_screen_y = event.motion.y;
            gs.command_line.moved_while_click++;
            break;
            
        case SDL_MOUSEBUTTONDOWN:
            switch (event.button.button)
            {
                case SDL_BUTTON_LEFT:
                    gs.mouse_buttons |= unDE_MouseButtons.Left;
                    gs.command_line.moved_while_click = 0;
                    with (gs.command_line)
                    {
                        if (ctrl_mode ^ gs.ctrl)
                        {
                            first_click = mouse;
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
                        with (gs.command_line)
                        {
                            gs.mouse_buttons &= ~unDE_MouseButtons.Left;
                            if (terminal)
                            {
                                if (!moved_while_click)
                                {
                                    if (gs.shift)
                                    {
                                        if (mouse > first_click)
                                        {
                                            end_selection = mouse;
                                        }
                                        else
                                        {
                                            start_selection = mouse;
                                        }
                                        selection_to_buffer(gs);
                                    }
                                    else if (on_click !is null)
                                    {
                                        on_click();
                                    }
                                    else if (ctrl_mode ^ gs.ctrl)
                                    {
                                        start_selection = CmdOutPos();
                                        end_selection = CmdOutPos();
                                    }
                                    else if (SDL_GetTicks() - last_left_click < DOUBLE_DELAY)
                                    {
                                        command_in_focus_id = 0;
                                        gs.keybar.input_mode = false;
                                    }
                                    else
                                    {
                                        //writefln("mouse_cmd_id=%s", mouse_cmd_id);
                                        auto ptid = mouse.cmd_id in gs.tid_by_command_id;
                                        if (ptid)
                                        {
                                            writefln("Command in Focus");
                                            command_in_focus_tid = *ptid;
                                            command_in_focus_id = mouse.cmd_id;
                                            enter = false;
                                            gs.keybar.input_mode = true;
                                        }
                                        else
                                        {
                                            command_in_focus_id = 0;
                                            if (!enter)
                                            {
                                                gs.keybar.input_mode = false;
                                            }
                                        }
                                    }
                                    last_left_click = SDL_GetTicks();
                                }
                                else if (ctrl_mode ^ gs.ctrl)
                                {
                                    if (mouse > first_click)
                                    {
                                        start_selection = first_click;
                                        end_selection = mouse;
                                    }
                                    else
                                    {
                                        start_selection = mouse;
                                        end_selection = first_click;
                                    }
                                    selection_to_buffer(gs);
                                }
                            }
                        }
                        break;
                    case SDL_BUTTON_MIDDLE:
                        gs.mouse_buttons &= ~unDE_MouseButtons.Middle;
                        with (gs.command_line)
                        {
                            if (enter && gs.mouse_screen_x < gs.screen.w)
                            {
                               char* clipboard = SDL_GetClipboardText();
                                if (clipboard)
                                {
                                    string buffer = clipboard.fromStringz().idup();

                                    command = (command[0..pos] ~
                                            buffer ~
                                            command[pos..$]).idup();
                                    pos += buffer.length;
                                }
                            }
                            else if (command_in_focus_id > 0)
                            {
                                char* clipboard = SDL_GetClipboardText();
                                if (clipboard)
                                {
                                    string buffer = clipboard.fromStringz().idup();
                                    send(command_in_focus_tid, buffer);
                                }
                            }
                        }
                        break;
                    case SDL_BUTTON_RIGHT:
                        gs.mouse_buttons &= ~unDE_MouseButtons.Right;
                        break;
                    default:
                        break;
                }
            }
            break;

        case SDL_MOUSEWHEEL:
            with (gs.command_line)
            {
                if (terminal)
                {
                    if (ctrl_mode ^ gs.ctrl)
                    {
                        y += event.wheel.y * 40;
                        if (event.wheel.y > 0)
                            neg_y = 0;
                        else
                            neg_y += event.wheel.y * 40;
                    }
                    else
                    {
                        fontsize += event.wheel.y;

                        font_changed = true;
                        if (fontsize < 4) fontsize = 4;
                        if (fontsize > 15) fontsize = 15;
                    }
                    last_redraw = 0;

                    update_winsize(gs);
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

    return result;
}

void
setup_keybar_command_line_default(GlobalState gs)
{
    gs.keybar.handlers.clear();
    gs.keybar.handlers_down.clear();
    gs.keybar.handlers_double.clear();
    if (gs.command_line.search_mode)
    {
        gs.keybar.handlers[SDL_SCANCODE_ESCAPE] = KeyHandler(toDelegate(&turn_off_command_line), "Finish search mode", "Esc");
    }
    else
    {
        gs.keybar.handlers[SDL_SCANCODE_ESCAPE] = KeyHandler(toDelegate(&turn_off_command_line), "Close command line", "command_line.png");
    }
    gs.keybar.handlers_down[SDL_SCANCODE_LEFT] = KeyHandler(toDelegate(&command_line_left), "Left", "←");
    gs.keybar.handlers_down[SDL_SCANCODE_RIGHT] = KeyHandler(toDelegate(&command_line_right), "Right", "→");
    gs.keybar.handlers[SDL_SCANCODE_UP] = KeyHandler(toDelegate(&hist_up), "Search history backward", "↑");
    gs.keybar.handlers[SDL_SCANCODE_DOWN] = KeyHandler(toDelegate(&hist_down), "Search history forward", "↓");
    gs.keybar.handlers_down[SDL_SCANCODE_BACKSPACE] = KeyHandler(toDelegate(&command_line_backspace), "Backspace", "<--");
    gs.keybar.handlers[SDL_SCANCODE_TAB] = KeyHandler(toDelegate(&command_line_tab), "Autocomplete", "Tab");
    gs.keybar.handlers_down[SDL_SCANCODE_DELETE] = KeyHandler(toDelegate(&command_line_delete), "Delete", "Del");
    gs.keybar.handlers[SDL_SCANCODE_RETURN] = KeyHandler(toDelegate(&command_line_enter), "Run Command", "Run");
    //gs.keybar.handlers_down[SDL_SCANCODE_LCTRL] = KeyHandler(toDelegate(&command_line_ctrl_down), "Some commands", "Ctrl");
    //gs.keybar.handlers[SDL_SCANCODE_LCTRL] = KeyHandler(toDelegate(&command_line_ctrl_up), "", "Ctrl");
}

void
setup_keybar_command_line_ctrl(GlobalState gs)
{
    setup_keybar_command_line_default(gs);
    gs.keybar.handlers_down[SDL_SCANCODE_R] = KeyHandler(toDelegate(&command_line_search_mode_on), "Search mode", "Srch");
    gs.keybar.handlers[SDL_SCANCODE_RETURN] = KeyHandler(toDelegate(&command_line_enter), "New line", "\\n");
    //gs.keybar.handlers_down[SDL_SCANCODE_APOSTROPHE] = KeyHandler(toDelegate(&gomark), "Go To Mark", "gomark.png");
}

void
setup_keybar_terminal(GlobalState gs)
{
    gs.keybar.handlers.clear();
    gs.keybar.handlers_down.clear();
    gs.keybar.handlers_double.clear();

    gs.keybar.handlers[SDL_SCANCODE_Q] = KeyHandler(toDelegate(&quit), "Quit", "exit.png");
    gs.keybar.handlers[SDL_SCANCODE_PRINTSCREEN] = KeyHandler(toDelegate(&make_screenshot), "Make screenshot", "Prt Sc");
    gs.keybar.handlers[SDL_SCANCODE_APOSTROPHE] = KeyHandler(toDelegate(&gomark), "Go To Mark", "gomark.png");
    if (gs.shift)
    {
        gs.keybar.handlers[SDL_SCANCODE_PAGEUP] = KeyHandler(toDelegate(&terminal_page_up), "Page Up", "PgUp");
        gs.keybar.handlers[SDL_SCANCODE_PAGEDOWN] = KeyHandler(toDelegate(&terminal_page_down), "Page Down", "PgD");
    }
    gs.keybar.handlers_double[SDL_SCANCODE_LCTRL] = KeyHandler(toDelegate(&turn_on_off_ctrl_mode), "Ctrl Mode", "Ctrl");
    gs.keybar.handlers_double[SDL_SCANCODE_RCTRL] = KeyHandler(toDelegate(&turn_on_off_ctrl_mode), "", "");
    gs.keybar.handlers_down[SDL_SCANCODE_LCTRL] = KeyHandler(toDelegate(&setup_keybar_terminal_ctrl), "", "Ctrl");
    gs.keybar.handlers_down[SDL_SCANCODE_RCTRL] = KeyHandler(toDelegate(&setup_keybar_terminal_ctrl), "", "");
    gs.keybar.handlers[SDL_SCANCODE_ESCAPE] = KeyHandler(toDelegate(&turn_off_terminal), "Close terminal", "Esc");
}

void
setup_keybar_terminal_ctrl(GlobalState gs)
{
    gs.keybar.handlers.clear();
    gs.keybar.handlers_down.clear();
    gs.keybar.handlers_double.clear();

    gs.keybar.handlers[SDL_SCANCODE_Q] = KeyHandler(toDelegate(&restart), "Restart", "exit.png");
    gs.keybar.handlers[SDL_SCANCODE_SEMICOLON] = KeyHandler(toDelegate(&turn_on_command_line), "Command line", "command_line.png");
    gs.keybar.handlers[SDL_SCANCODE_APOSTROPHE] = KeyHandler(toDelegate(&gomark), "Go To Mark", "gomark.png");
    gs.keybar.handlers[SDL_SCANCODE_LCTRL] = KeyHandler(toDelegate(&setup_keybar_terminal), "", "Ctrl");
    gs.keybar.handlers[SDL_SCANCODE_RCTRL] = KeyHandler(toDelegate(&setup_keybar_terminal), "", "");
}

void
setup_keybar_terminal_command_focus_in(GlobalState gs)
{
    gs.keybar.handlers.clear();
    gs.keybar.handlers_down.clear();
    gs.keybar.handlers_double.clear();

    if (gs.ctrl)
    {
        for (SDL_Scancode i = SDL_SCANCODE_A; i <= SDL_SCANCODE_Z; i++)
        {
            string letter = fromStringz(SDL_GetScancodeName(i)).idup();
            char[] scancode_name = fromStringz(SDL_GetScancodeName(i)).dup();
            scancode_name[0] -= 'A'-1;
            gs.keybar.handlers_down[i] = KeyHandler(get_send_input(scancode_name.idup()), "Ctrl+"~letter, letter);
        }
        foreach(i; [SDL_SCANCODE_LEFTBRACKET, SDL_SCANCODE_RIGHTBRACKET])
        {
            string letter = fromStringz(SDL_GetScancodeName(i)).idup();
            char[] scancode_name = fromStringz(SDL_GetScancodeName(i)).dup();
            scancode_name[0] -= 'A'-1;
            gs.keybar.handlers_down[i] = KeyHandler(get_send_input(scancode_name.idup()), "Ctrl+"~letter, letter);
        }
        gs.keybar.handlers_down[SDL_SCANCODE_SEMICOLON] = KeyHandler(toDelegate(&turn_on_command_line), "Command line", "command_line.png");
        //gs.keybar.handlers_down[SDL_SCANCODE_APOSTROPHE] = KeyHandler(toDelegate(&gomark), "Go To Mark", "gomark.png");
    }

    if (gs.shift)
    {
        gs.keybar.handlers[SDL_SCANCODE_PAGEUP] = KeyHandler(toDelegate(&terminal_page_up), "Page Up", "PgUp");
        gs.keybar.handlers[SDL_SCANCODE_PAGEDOWN] = KeyHandler(toDelegate(&terminal_page_down), "Page Down", "PgD");
    }

    gs.keybar.handlers_down[SDL_SCANCODE_ESCAPE] = KeyHandler(get_send_input("\x1B"), "", "Esc");
    gs.keybar.handlers_down[SDL_SCANCODE_LEFT] = KeyHandler(get_send_input("\x1B[D"), "", "←");
    gs.keybar.handlers_down[SDL_SCANCODE_RIGHT] = KeyHandler(get_send_input("\x1B[C"), "", "→");
    gs.keybar.handlers_down[SDL_SCANCODE_UP] = KeyHandler(get_send_input("\x1B[A"), "", "↑");
    gs.keybar.handlers_down[SDL_SCANCODE_DOWN] = KeyHandler(get_send_input("\x1B[B"), "", "↓");
    gs.keybar.handlers_down[SDL_SCANCODE_BACKSPACE] = KeyHandler(get_send_input("\x08"), "", "<--");
    gs.keybar.handlers_down[SDL_SCANCODE_INSERT] = KeyHandler(get_send_input("\x1B[2~"), "", "Ins");
    gs.keybar.handlers_down[SDL_SCANCODE_HOME] = KeyHandler(get_send_input("\x1B[7~"), "", "Home");
    gs.keybar.handlers_down[SDL_SCANCODE_END] = KeyHandler(get_send_input("\x1B[8~"), "", "End");
    gs.keybar.handlers_down[SDL_SCANCODE_TAB] = KeyHandler(get_send_input("\t"), "", "Tab");

    gs.keybar.handlers_down[SDL_SCANCODE_F1] = KeyHandler(get_send_input("\x1B[11~"), "", "F1");
    gs.keybar.handlers_down[SDL_SCANCODE_F2] = KeyHandler(get_send_input("\x1B[12~"), "", "F2");
    gs.keybar.handlers_down[SDL_SCANCODE_F3] = KeyHandler(get_send_input("\x1B[13~"), "", "F3");
    gs.keybar.handlers_down[SDL_SCANCODE_F4] = KeyHandler(get_send_input("\x1B[14~"), "", "F4");
    gs.keybar.handlers_down[SDL_SCANCODE_F5] = KeyHandler(get_send_input("\x1B[15~"), "", "F5");

    gs.keybar.handlers_down[SDL_SCANCODE_F6] = KeyHandler(get_send_input("\x1B[17~"), "", "F6");
    gs.keybar.handlers_down[SDL_SCANCODE_F7] = KeyHandler(get_send_input("\x1B[18~"), "", "F7");
    gs.keybar.handlers_down[SDL_SCANCODE_F8] = KeyHandler(get_send_input("\x1B[19~"), "", "F8");
    gs.keybar.handlers_down[SDL_SCANCODE_F9] = KeyHandler(get_send_input("\x1B[20~"), "", "F9");
    gs.keybar.handlers_down[SDL_SCANCODE_F10] = KeyHandler(get_send_input("\x1B[21~"), "", "F10");

    gs.keybar.handlers_down[SDL_SCANCODE_F11] = KeyHandler(get_send_input("\x1B[23~"), "", "F11");
    gs.keybar.handlers_down[SDL_SCANCODE_F12] = KeyHandler(get_send_input("\x1B[24~"), "", "F12");

    gs.keybar.handlers_down[SDL_SCANCODE_PAGEUP] = KeyHandler(get_send_input("\x1B[5~"), "", "PgUp");
    gs.keybar.handlers_down[SDL_SCANCODE_PAGEDOWN] = KeyHandler(get_send_input("\x1B[6~"), "", "PgD");
    gs.keybar.handlers_down[SDL_SCANCODE_DELETE] = KeyHandler(get_send_input("\x1B[3~"), "", "Del");
    gs.keybar.handlers_down[SDL_SCANCODE_RETURN] = KeyHandler(get_send_input("\n"), "", "Enter");
}
