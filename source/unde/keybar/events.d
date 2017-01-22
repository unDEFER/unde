module unde.keybar.events;

import unde.global_state;
import unde.lib;
import unde.tick;
import unde.keybar.lib;

import derelict.sdl2.sdl;

import std.stdio;
import std.string;
import std.math;
import std.conv;
import std.range.primitives;

import berkeleydb.all: ssize_t;

int process_modifiers_down(GlobalState gs, int scancode)
{
    int result = 0;
    switch(scancode)
    {
        case SDL_SCANCODE_LCTRL:
                gs.modifiers |= Modifiers.Left_Ctrl;
                break;
        case SDL_SCANCODE_RCTRL:
                gs.modifiers |= Modifiers.Right_Ctrl;
                break;
        case SDL_SCANCODE_LSHIFT:
                gs.modifiers |= Modifiers.Left_Shift;
                if (SDL_GetTicks() - gs.keybar.last_shift < DOUBLE_DELAY)
                {
                    result = 1;
                    gs.keybar.last_shift = 0;
                }
                else
                    gs.keybar.last_shift = SDL_GetTicks();
                break;
        case SDL_SCANCODE_RSHIFT:
                gs.modifiers |= Modifiers.Right_Shift;
                if (SDL_GetTicks() - gs.keybar.last_shift < DOUBLE_DELAY)
                {
                    result = 1;
                    gs.keybar.last_shift = 0;
                }
                else
                    gs.keybar.last_shift = SDL_GetTicks();
                break;
        case SDL_SCANCODE_LALT:
                gs.modifiers |= Modifiers.Left_Alt;
                break;
        case SDL_SCANCODE_RALT:
                gs.modifiers |= Modifiers.Right_Alt;
                break;
        case SDL_SCANCODE_CAPSLOCK:
                gs.modifiers |= Modifiers.CapsLock;
                break;
        case SDL_SCANCODE_LGUI:
                gs.modifiers |= Modifiers.Left_Win;
                break;
        case SDL_SCANCODE_RGUI:
                gs.modifiers |= Modifiers.Right_Win;
                break;
        case SDL_SCANCODE_SPACE:
                gs.modifiers |= Modifiers.Space;
                break;
        case SDL_SCANCODE_APPLICATION:
                gs.modifiers |= Modifiers.Menu;
                break;
        case SDL_SCANCODE_SCROLLLOCK:
                gs.modifiers |= Modifiers.ScrollLock;
                break;
        default:
                break;
    }

    if ((gs.modifiers & gs.keybar.changer) == gs.keybar.changer)
    {
        if (SDL_GetTicks() - gs.keybar.last_change < DOUBLE_DELAY)
        {
            result = 2;
            gs.keybar.last_change = 0;
        }
        else
        {
            gs.keybar.mode++;
            if (gs.keybar.mode >= gs.keybar.layout_modes.length)
                gs.keybar.mode = 0;
            gs.keybar.last_change = SDL_GetTicks();
        }
    }

    update_letters(gs);
    return result;
}

void process_modifiers_up(GlobalState gs, int scancode)
{
    switch(scancode)
    {
        case SDL_SCANCODE_LCTRL:
            gs.modifiers &= ~Modifiers.Left_Ctrl;
            break;
        case SDL_SCANCODE_RCTRL:
            gs.modifiers &= ~Modifiers.Right_Ctrl;
            break;
        case SDL_SCANCODE_LSHIFT:
            gs.modifiers &= ~Modifiers.Left_Shift;
            break;
        case SDL_SCANCODE_RSHIFT:
            gs.modifiers &= ~Modifiers.Right_Shift;
            break;
        case SDL_SCANCODE_LALT:
            gs.modifiers &= ~Modifiers.Left_Alt;
            break;
        case SDL_SCANCODE_RALT:
            gs.modifiers &= ~Modifiers.Right_Alt;
            break;
        case SDL_SCANCODE_CAPSLOCK:
            gs.modifiers &= ~Modifiers.CapsLock;
            break;
        case SDL_SCANCODE_LGUI:
            gs.modifiers &= ~Modifiers.Left_Win;
            break;
        case SDL_SCANCODE_RGUI:
            gs.modifiers &= ~Modifiers.Right_Win;
            break;
        case SDL_SCANCODE_SPACE:
            gs.modifiers &= ~Modifiers.Space;
            break;
        case SDL_SCANCODE_APPLICATION:
            gs.modifiers &= ~Modifiers.Menu;
            break;
        case SDL_SCANCODE_SCROLLLOCK:
            gs.modifiers &= ~Modifiers.ScrollLock;
            break;
        default:
            break;
    }
}

void process_event(GlobalState gs, ref SDL_Event event, KeyHandler *kh)
{
    switch( event.type )
    {
        case SDL_KEYDOWN:
            int res = process_modifiers_down(gs, event.key.keysym.scancode);

            with(gs.keybar)
            {
                if (input_mode && !kh)
                {
                    ButtonPos* buttonpos = event.key.keysym.scancode in buttonpos_by_scan;
                    if (buttonpos || res)
                    {
                        string chr;
                        if (res)
                           chr = "" ~ char.init ~ res.to!string();
                        else if (buttonpos)
                           chr = (*letters)[buttonpos.i][buttonpos.pos];
                        if (chr == "Spc")
                            chr = " ";
                        if (chr.walkLength == 1 && "↑←↓→".indexOf(chr) < 0 || res)
                        {
                            gs.keybar.last_change = 0;
                            gs.keybar.last_shift = 0;
                            SDL_Event sevent;
                            sevent.type = SDL_TEXTINPUT;
                            sevent.text.text = to_char_array_z!32(chr);
                            unde.tick.process_event(gs, sevent);
                        }
                    }
                }
            }
            break;
        case SDL_KEYUP:
            process_modifiers_up(gs, event.key.keysym.scancode);
            break;

        case SDL_MOUSEMOTION:
            gs.mouse_screen_x = event.motion.x;
            gs.mouse_screen_y = event.motion.y;
            gs.moved_while_click++;
            break;
            
        case SDL_MOUSEBUTTONDOWN:
            ssize_t i = -1;
            switch (event.button.button)
            {
                case SDL_BUTTON_LEFT:
                    gs.mouse_buttons |= unDE_MouseButtons.Left;
                    i = 0;
                    break;
                case SDL_BUTTON_RIGHT:
                    gs.mouse_buttons |= unDE_MouseButtons.Right;
                    i = 1;
                    break;
                case SDL_BUTTON_MIDDLE:
                    gs.mouse_buttons |= unDE_MouseButtons.Middle;
                    i = 2;
                    break;
                default:
                    break;
            }

            if (i >= 0)
            {
                gs.moved_while_click = 0;
                with(gs.keybar)
                {
                    if (pos >= 0)
                    {
                        //ushort omodifiers = gs.modifiers;
                        process_modifiers_down(gs, (*scans_cur)[i][pos]);
                        /*if (omodifiers == gs.modifiers)
                            gs.last_mouse_down = 0;
                        else
                            gs.last_mouse_down = SDL_GetTicks();*/
                        KeyHandler* keyhandler = scans[i][pos] in gs.keybar.handlers_down;
                        if (keyhandler)
                        {
                            keyhandler.handler(gs);
                        }
                        else if (input_mode)
                        {
                            string chr = (*letters)[i][pos];
                            if (chr == "Spc")
                                chr = " ";
                            if (chr.walkLength == 1 && "↑←↓→".indexOf(chr) < 0)
                            {
                                SDL_Event sevent;
                                sevent.type = SDL_TEXTINPUT;
                                sevent.text.text = to_char_array_z!32(chr);
                                unde.tick.process_event(gs, sevent);
                            }
                        }
                    }
                }
            }

            break;
            
        case SDL_MOUSEBUTTONUP:

            ssize_t i = -1;
            long *last_click;
            switch (event.button.button)
            {
                case SDL_BUTTON_LEFT:
                    gs.mouse_buttons &= ~unDE_MouseButtons.Left;
                    i = 0;
                    last_click = &gs.last_left_click;
                    break;
                case SDL_BUTTON_RIGHT:
                    gs.mouse_buttons &= ~unDE_MouseButtons.Right;
                    i = 1;
                    last_click = &gs.last_right_click;
                    break;
                case SDL_BUTTON_MIDDLE:
                    gs.mouse_buttons &= ~unDE_MouseButtons.Middle;
                    i = 2;
                    last_click = &gs.last_middle_click;
                    break;
                default:
                    break;
            }

            if ( i >= 0 )
            {
                if (!gs.moved_while_click)
                {
                    with(gs.keybar)
                    {
                        if (pos >= 0)
                        {
                            //if (SDL_GetTicks() - gs.last_mouse_down > DOUBLE_DELAY/2)
                                process_modifiers_up(gs, (*scans_cur)[i][pos]);

                            KeyHandler* keyhandler;
                            if (SDL_GetTicks() - *last_click < DOUBLE_DELAY)
                                keyhandler = scans[i][pos] in gs.keybar.handlers_double;
                            if (keyhandler)
                                keyhandler.handler(gs);
                            keyhandler = scans[i][pos] in gs.keybar.handlers;
                            if (keyhandler)
                                keyhandler.handler(gs);
                            *last_click = SDL_GetTicks();
                        }
                    }
                }
            }

            break;

        case SDL_MOUSEWHEEL:
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
