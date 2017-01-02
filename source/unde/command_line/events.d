module unde.command_line.events;

import unde.global_state;
import unde.lib;
import unde.tick;
import unde.marks;
import unde.command_line.run;
import unde.command_line.lib;

import derelict.sdl2.sdl;

import std.stdio;
import std.string;
import std.utf;
import std.math;
import std.concurrency;

enum CommandLineEventHandlerResult
{
    Pass,
    Block
}

private CommandLineEventHandlerResult
process_key_down(GlobalState gs, SDL_Scancode scancode)
{
    auto result = CommandLineEventHandlerResult.Pass;

    if (gs.command_line.enter || gs.command_line.command_in_focus_id > 0)
    {
         result = CommandLineEventHandlerResult.Block;
    }

    with (gs.command_line)
    {
        if (command_in_focus_id > 0)
        {
            if (gs.command_line.ctrl)
            {
                char[] scancode_name = fromStringz(SDL_GetScancodeName(scancode)).dup();
                if (scancode_name >= "A" && scancode_name <= "Z" ||
                        scancode_name == "[" || scancode_name == "]")
                {
                    scancode_name[0] -= 'A'-1;
                    writefln("Send %d", scancode_name[0]);
                    send(command_in_focus_tid, scancode_name.idup());
                }
            }
        }
    }

    switch(scancode)
    { 
        case SDL_SCANCODE_SEMICOLON:
            if (gs.command_line.ctrl)
            {
                gs.command_line.just_started_input = true;
                SDL_StartTextInput();
                writefln("Command line open");
                result = CommandLineEventHandlerResult.Block;
                gs.command_line.enter = true;
                gs.ctrl=false;
            }
            break;
        case SDL_SCANCODE_ESCAPE:
            with (gs.command_line)
            {
                if (enter)
                {
                    SDL_StopTextInput();
                    writefln("Command line close");
                    gs.command_line.enter = false;
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B";
                    send(command_in_focus_tid, input);
                }
                else if (gs.command_line.terminal)
                {
                    gs.command_line.terminal = false;
                }
            }

            break;

        case SDL_SCANCODE_LEFT:
            with (gs.command_line)
            {
                if (enter)
                {
                    if (pos > 0)
                        pos -= command.strideBack(pos);
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[D";
                    send(command_in_focus_tid, input);
                }
            }
            break; 

        case SDL_SCANCODE_RIGHT:
            with (gs.command_line)
            {
                if (enter)
                {
                    if (pos < command.length)
                        pos += command.stride(pos);
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[C";
                    send(command_in_focus_tid, input);
                }
            }
            break; 

        case SDL_SCANCODE_UP:
            with (gs.command_line)
            {
                if (enter)
                {
                    hist_up(gs);
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[A";
                    send(command_in_focus_tid, input);
                }
            }
            break;

        case SDL_SCANCODE_DOWN:
            with (gs.command_line)
            {
                if (enter)
                {
                    hist_down(gs);
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[B";
                    send(command_in_focus_tid, input);
                }
            }
            break;

        case SDL_SCANCODE_BACKSPACE:
            with (gs.command_line)
            {
                if (enter)
                {
                    if ( command > "" && pos > 0 )
                    {
                        int sb = command.strideBack(pos);
                        command = (command[0..pos-sb] ~ command[pos..$]).idup();
                        pos -= sb;
                    }
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x08";
                    send(command_in_focus_tid, input);
                }
            }
            break;

        case SDL_SCANCODE_INSERT:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[2~";
                    send(command_in_focus_tid, input);
                }
            }
            break;

        case SDL_SCANCODE_HOME:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[7~";
                    send(command_in_focus_tid, input);
                }
            }
            break;

        case SDL_SCANCODE_END:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[8~";
                    send(command_in_focus_tid, input);
                }
            }
            break;

        case SDL_SCANCODE_TAB:
            with (gs.command_line)
            {
                if (enter)
                {
                    if (complete.length > 1 && complete[0] == '1')
                    {
                        command = command[0..pos] ~ complete[1..$] ~ command[pos..$];
                        pos += complete[1..$].length;
                    }
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\t";
                    send(command_in_focus_tid, input);
                }
            }
            break;

        case SDL_SCANCODE_F1:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[11~";
                    send(command_in_focus_tid, input);
                }
            }
            break;
        case SDL_SCANCODE_F2:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[12~";
                    send(command_in_focus_tid, input);
                }
            }
            break;
        case SDL_SCANCODE_F3:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[13~";
                    send(command_in_focus_tid, input);
                }
            }
            break;
        case SDL_SCANCODE_F4:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[14~";
                    send(command_in_focus_tid, input);
                }
            }
            break;
        case SDL_SCANCODE_F5:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[15~";
                    send(command_in_focus_tid, input);
                }
            }
            break;

        case SDL_SCANCODE_F6:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[17~";
                    send(command_in_focus_tid, input);
                }
            }
            break;
        case SDL_SCANCODE_F7:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[18~";
                    send(command_in_focus_tid, input);
                }
            }
            break;
        case SDL_SCANCODE_F8:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[19~";
                    send(command_in_focus_tid, input);
                }
            }
            break;
        case SDL_SCANCODE_F9:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[20~";
                    send(command_in_focus_tid, input);
                }
            }
            break;
        case SDL_SCANCODE_F10:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[21~";
                    send(command_in_focus_tid, input);
                }
            }
            break;

        case SDL_SCANCODE_F11:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[23~";
                    send(command_in_focus_tid, input);
                }
            }
            break;
        case SDL_SCANCODE_F12:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[24~";
                    send(command_in_focus_tid, input);
                }
            }
            break;

        case SDL_SCANCODE_PAGEUP:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (shift)
                {
                    int line_height = cast(int)(round(SQRT2^^9)*1.2);
                    y += gs.screen.h - 2*line_height;
                    neg_y = 0;
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[5~";
                    send(command_in_focus_tid, input);
                }
            }
            break;

        case SDL_SCANCODE_PAGEDOWN:
            with (gs.command_line)
            {
                if (enter)
                {
                }
                else if (shift)
                {
                    int line_height = cast(int)(round(SQRT2^^9)*1.2);
                    y -= gs.screen.h - 2*line_height;
                    neg_y -= gs.screen.h - 2*line_height;
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[6~";
                    send(command_in_focus_tid, input);
                }
            }
            break;

        case SDL_SCANCODE_DELETE:
            with (gs.command_line)
            {
                if (enter)
                {
                    if ( command > "" && pos > 0 )
                    {
                        /*int sb = command.strideBack(pos);
                        command = (command[0..pos-sb] ~ command[pos..$]).idup();
                        pos -= sb;*/
                    }
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\x1B[3~";
                    send(command_in_focus_tid, input);
                }
            }
            break;

        case SDL_SCANCODE_RETURN:
            with (gs.command_line)
            {
                if (enter)
                {
                    if (shift || ctrl)
                    {
                        command = (command[0..pos] ~
                                "\n" ~
                                command[pos..$]).idup();
                        pos++;
                    }
                    else
                    {
                        run_command(gs, command);
                        hist_cmd_id = 0;
                        command = "";
                        pos = 0;
                        SDL_StopTextInput();
                        writefln("Command line close");
                        gs.command_line.enter = false;
                    }
                }
                else if (command_in_focus_id > 0)
                {
                    string input = "\n";
                    send(command_in_focus_tid, input);
                }

                if (SDL_GetTicks() - last_enter < DOUBLE_DELAY)
                {
                    terminal = true;
                }

                last_enter = SDL_GetTicks();
            }
            break;

        case SDL_SCANCODE_LCTRL:
            goto case;
        case SDL_SCANCODE_RCTRL:
            gs.command_line.ctrl = true;
            break;

        case SDL_SCANCODE_LSHIFT:
            goto case;
        case SDL_SCANCODE_RSHIFT:
            gs.command_line.shift = true;
            break;

        default:
            break;
    }

    //writefln("%s", result);
    return result;
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

                    command = (command[0..pos] ~
                        input ~
                        command[pos..$]).idup();
                    pos += input.length;
                }
                else if (command_in_focus_id > 0)
                {
                    char[] input = fromStringz(cast(char*)event.text.text);
                    send(command_in_focus_tid, input.idup());
                }
            }
            break;

        case SDL_KEYDOWN:
            result = process_key_down(gs, event.key.keysym.scancode);
            break;

        case SDL_KEYUP:
            if (gs.command_line.enter)
            {
                 result = CommandLineEventHandlerResult.Block;
            }
            switch(event.key.keysym.scancode)
            { 
                case SDL_SCANCODE_LCTRL:
                    goto case;
                case SDL_SCANCODE_RCTRL:
                    if (SDL_GetTicks() - gs.command_line.last_ctrl < DOUBLE_DELAY)
                    {
                        gs.command_line.ctrl_mode ^= 1;
                    }
                    gs.command_line.last_ctrl = SDL_GetTicks();
                    gs.command_line.ctrl = false;
                    break;
                case SDL_SCANCODE_LSHIFT:
                    goto case;
                case SDL_SCANCODE_RSHIFT:
                    gs.command_line.shift = false;
                    break;
                default:
                    /* Ignore key */
                    break;
            }
            break;
            
        case SDL_MOUSEMOTION:
            if (gs.mouse_buttons & unDE_MouseButtons.Left)
            {
                with (gs.command_line)
                {
                    if (ctrl_mode ^ ctrl)
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
                        if (ctrl_mode ^ ctrl)
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
                                if (shift)
                                {
                                    writefln("Shift!");
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
                                else if (ctrl_mode ^ ctrl)
                                {
                                    start_selection = CmdOutPos();
                                    end_selection = CmdOutPos();
                                }
                                else if (SDL_GetTicks() - last_left_click < DOUBLE_DELAY)
                                {
                                    command_in_focus_id = 0;
                                    SDL_StopTextInput();
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
                                        SDL_StartTextInput();
                                    }
                                    else
                                    {
                                        command_in_focus_id = 0;
                                        SDL_StopTextInput();
                                    }
                                }
                                last_left_click = SDL_GetTicks();
                            }
                            else if (ctrl_mode ^ ctrl)
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
                        if (enter)
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
            break;

        case SDL_MOUSEWHEEL:
            with (gs.command_line)
            {
                if (terminal)
                {
                    if (ctrl_mode ^ ctrl)
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
