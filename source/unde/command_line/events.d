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

enum CommandLineEventHandlerResult
{
    Pass,
    Block
}

private CommandLineEventHandlerResult
process_key_down(GlobalState gs, SDL_Scancode scancode)
{
    auto result = CommandLineEventHandlerResult.Pass;

    if (gs.command_line.enter)
    {
         result = CommandLineEventHandlerResult.Block;
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
            }
            break;
        case SDL_SCANCODE_ESCAPE:
            if (gs.command_line.enter)
            {
                SDL_StopTextInput();
                writefln("Command line close");
                gs.command_line.enter = false;
            }

            if (gs.command_line.terminal)
            {
                gs.command_line.terminal = false;
            }

            break;

        case SDL_SCANCODE_UP:
            if (gs.command_line.enter)
            {
                hist_up(gs);
            }
            break;

        case SDL_SCANCODE_DOWN:
            if (gs.command_line.enter)
            {
                hist_down(gs);
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
                        command = "";
                        pos = 0;
                        SDL_StopTextInput();
                        writefln("Command line close");
                        gs.command_line.enter = false;
                    }
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
                    y += event.motion.yrel;
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
                    break;
                case SDL_BUTTON_MIDDLE:
                    gs.mouse_buttons &= ~unDE_MouseButtons.Middle;
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
                while (event.wheel.y > 0)
                {
                    fontsize++;
                    event.wheel.y--;
                }
                while (event.wheel.y < 0)
                {
                    fontsize--;
                    event.wheel.y++;
                }

                font_changed = true;
                if (fontsize < 4) fontsize = 4;
                if (fontsize > 15) fontsize = 15;
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

    return result;
}
