module unde.guitk.textarea;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;
import derelict.sdl2.image;

import std.stdio;
import std.math;
import std.string;
import std.utf;

import unde.global_state;
import unde.guitk.lib;
import unde.keybar.lib;
import unde.lib;
import unde.command_line.lib;
import unde.tick;

class TextArea:UIEntry
{
    private SDL_Rect _rect;
    private UIPage _page;
    private bool _focus;
    private string _text;
    private int fontsize;
    private int line_height;
    private ssize_t pos;
    private SDL_Color color;
    private ssize_t mouse_pos;
    private ssize_t first_click;
    private ssize_t start_selection = -1;
    private ssize_t end_selection = -1;

    @property SDL_Rect rect() {return _rect;}
    @property ref string text() {return _text;}

    this(UIPage page, SDL_Rect rect,
            SDL_Color color = SDL_Color(0xFF, 0xFF, 0xFF, 0xFF))
    {
        _page = page;
        _rect = rect;
        fontsize = 9;
        line_height = cast(int)(round(SQRT2^^fontsize)*1.2);
        this.color = color;
    }
    
    void on_draw(GlobalState gs)
    {
        /* Background */
        auto r = SDL_RenderCopy(gs.renderer, gs.texture_gray, null, &_rect);
        if (r < 0)
        {
            writefln( "List.on_draw(), 1: Error while render copy: %s",
                    SDL_GetError().to!string() );
        }

        auto tt = gs.text_viewer.font.get_line_from_cache(_text, 
                fontsize, _rect.w, line_height, color, null,
                start_selection, end_selection);
        if (!tt && !tt.texture)
        {
            throw new Exception("Can't create text_surface: "~
                    to!string(TTF_GetError()));
        }

        int x_limit = _rect.x+_rect.w;
        int y_limit = _rect.y+_rect.h;

        SDL_Rect rect;
        rect.x = _rect.x;
        rect.y = _rect.y;
        rect.w = (rect.x+tt.w < x_limit) ? tt.w : x_limit - rect.x;
        rect.h = (rect.y+tt.h < y_limit) ? tt.h : y_limit - rect.y;

        SDL_Rect src;
        src.x = 0;
        src.y = 0;
        src.w = (rect.x+tt.w < x_limit) ? tt.w : x_limit - rect.x;
        src.h = (rect.y+tt.h < y_limit) ? tt.h : y_limit - rect.y;

        mouse_pos = get_position_by_chars(
                gs.mouse_screen_x - rect.x,
                gs.mouse_screen_y - rect.y, tt.chars);

        r = SDL_RenderCopy(gs.renderer, tt.texture, &src, &rect);
        if (r < 0)
        {
            writefln(
                    "List.on_draw(), 2: Error while render copy: %s", 
                    SDL_GetError().to!string() );
        }

        /* Render cursor */
        if (_focus && pos < tt.chars.length)
        {
            rect = tt.chars[pos];
            rect.x += _rect.x;
            rect.y += _rect.y;
            if (rect.x < x_limit && rect.y < y_limit)
            {
                string chr = " ";
                if (pos < _text.length)
                    chr = _text[pos..pos+_text.stride(pos)];
                if (chr == "\n") chr = " ";

                r = SDL_RenderCopy(gs.renderer, gs.texture_cursor, null, &rect);
                if (r < 0)
                {
                    writefln( "draw_command_line(), 11: Error while render copy: %s",
                            SDL_GetError().to!string() );
                }

                auto st = gs.text_viewer.font.get_char_from_cache(chr, fontsize, SDL_Color(0x00, 0x00, 0x20, 0xFF));
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
    }

    void selection_to_buffer(GlobalState gs)
    {
        string selection = _text[start_selection..end_selection + _text.mystride(end_selection)];
        SDL_SetClipboardText(selection.toStringz());
    }

    void shift_selected(GlobalState gs)
    {
        if (start_selection < 0 || end_selection < 0) return;
        string converted;
        for (ssize_t i=start_selection; i < end_selection + _text.mystride(end_selection); i+=_text.stride(i))
        {
            string chr = _text[i..i+_text.stride(i)];
            if (chr.toLower() == chr)
            {
                chr = chr.toUpper();
            }
            else
                chr = chr.toLower();

            converted ~= chr;
        }

        _text = _text[0..start_selection] ~ converted ~ _text[end_selection + _text.mystride(end_selection)..$];
    }

    bool find_chr(string chr, string[][3] *letters, ref ButtonPos buttonpos)
    {
        for (buttonpos.i = 0; buttonpos.i < 3; buttonpos.i++)
        {
            for (buttonpos.pos = 0; buttonpos.pos <
                    (*letters)[buttonpos.i].length; buttonpos.pos++)
            {
                if ((*letters)[buttonpos.i][buttonpos.pos] == chr)
                    return true;
            }
        }
        return false;
    }

    void change_layout_selected(GlobalState gs)
    {
        if (start_selection < 0 || end_selection < 0) return;
        string converted;
        for (ssize_t i=start_selection; i < end_selection + _text.mystride(end_selection); i+=_text.stride(i))
        {
            string chr = _text[i..i+_text.stride(i)];

            ssize_t prev_mode = gs.keybar.mode-1;
            if (prev_mode < 0)
                prev_mode = gs.keybar.layout_modes.length - 1;

            ButtonPos buttonpos;
            auto letters = &gs.keybar.layout_modes[prev_mode].letters;
            if (find_chr(chr, letters, buttonpos))
            {
                letters = &gs.keybar.layout_modes[gs.keybar.mode].letters;
                chr = (*letters)[buttonpos.i][buttonpos.pos];
            }
            letters = &gs.keybar.layout_modes[prev_mode].letters_shift;
            if (find_chr(chr, letters, buttonpos))
            {
                letters = &gs.keybar.layout_modes[gs.keybar.mode].letters_shift;
                chr = (*letters)[buttonpos.i][buttonpos.pos];
            }
            letters = &gs.keybar.layout_modes[prev_mode].letters_altgr;
            if (find_chr(chr, letters, buttonpos))
            {
                letters = &gs.keybar.layout_modes[gs.keybar.mode].letters_altgr;
                chr = (*letters)[buttonpos.i][buttonpos.pos];
            }
            letters = &gs.keybar.layout_modes[prev_mode].letters_shift_altgr;
            if (find_chr(chr, letters, buttonpos))
            {
                letters = &gs.keybar.layout_modes[gs.keybar.mode].letters_shift_altgr;
                chr = (*letters)[buttonpos.i][buttonpos.pos];
            }

            converted ~= chr;
        }

        _text = _text[0..start_selection] ~ converted ~ _text[end_selection + _text.mystride(end_selection)..$];
        end_selection = start_selection + converted.length;
        end_selection -= _text.mystrideBack(end_selection);
        if (pos > start_selection) pos = _text.length;
    }

    void delegate(GlobalState gs) on_change;

    void process_event(GlobalState gs, SDL_Event event)
    {
        switch( event.type )
        {
            case SDL_TEXTINPUT:
                char[] input = fromStringz(cast(char*)event.text.text);
                if (input[0] == char.init)
                {
                    if (input[1] == '1')
                    {
                        shift_selected(gs);
                    }
                    else
                    {
                        change_layout_selected(gs);
                    }
                }
                else
                {
                    _text = 
                        (_text[0..pos] ~
                        input ~
                        _text[pos..$]).idup();
                    pos += input.length;
                }
                if (on_change)
                    on_change(gs);
                break;

            case SDL_MOUSEMOTION:
                if (gs.mouse_buttons & unDE_MouseButtons.Left)
                {
                    if (mouse_pos > first_click)
                    {
                        start_selection = first_click;
                        end_selection = mouse_pos;
                    }
                    else
                    {
                        start_selection = mouse_pos;
                        end_selection = first_click;
                    }
                }
                break;
                
            case SDL_MOUSEBUTTONDOWN:
                switch (event.button.button)
                {
                    case SDL_BUTTON_LEFT:
                        first_click = mouse_pos;
                        break;
                    case SDL_BUTTON_MIDDLE:
                        break;
                    case SDL_BUTTON_RIGHT:
                        break;
                    default:
                        break;
                }
                break;

            case SDL_MOUSEBUTTONUP:
                switch (event.button.button)
                {
                    case SDL_BUTTON_LEFT:
                        if (!gs.moved_while_click)
                        {
                            if (SDL_GetTicks() - gs.last_left_click < DOUBLE_DELAY)
                            {
                            }
                            else
                            {
                                set_focus(gs);
                                start_selection = -1;
                                end_selection = -1;
                            }
                        }
                        else
                        {
                            if (_text == "")
                            {
                                start_selection = -1;
                                end_selection = -1;
                            }
                            else
                            {
                                if (mouse_pos > first_click)
                                {
                                    start_selection = first_click;
                                    end_selection = mouse_pos;
                                }
                                else
                                {
                                    start_selection = mouse_pos;
                                    end_selection = first_click;
                                }
                                if (end_selection + _text.mystride(end_selection) > _text.length)
                                    end_selection = _text.length - 1 - _text.mystrideBack(_text.length-1);
                                selection_to_buffer(gs);
                            }
                        }
                        break;
                    case SDL_BUTTON_MIDDLE:
                        char* clipboard = SDL_GetClipboardText();
                        if (clipboard)
                        {
                            string buffer = clipboard.fromStringz().idup();

                            _text = 
                                (_text[0..pos] ~
                                 buffer ~
                                 _text[pos..$]).idup();
                            pos += buffer.length;
                            if (on_change)
                                on_change(gs);
                        }
                        break;
                    default:
                        break;
                }
                break;

            default:
                break;
        }
    }

    @property UIPage page() {return _page;}

    @property ref bool focus() {return _focus;}

    void on_set_focus(GlobalState gs)
    {
        gs.keybar.input_mode = true;
    }

    void on_unset_focus(GlobalState gs)
    {
        gs.keybar.input_mode = false;
    }

    private void
    close_page(GlobalState gs)
    {
        _page.show = false;
    }

    private void
    left(GlobalState gs)
    {
        if (pos > 0)
            pos -= _text.strideBack(pos);
    }

    private void
    right(GlobalState gs)
    {
        if (pos < _text.length)
            pos += _text.stride(pos);
    }

    private void
    backscape(GlobalState gs)
    {
        if (_text > "" && pos > 0 )
        {
            int sb = _text.strideBack(pos);
            _text = (_text[0..pos-sb] ~ _text[pos..$]).idup();
            pos -= sb;
            if (on_change)
                on_change(gs);
        }
    }

    void set_keybar(GlobalState gs)
    {
        gs.keybar.handlers.clear();
        gs.keybar.handlers_down.clear();
        gs.keybar.handlers_double.clear();

        gs.keybar.handlers[SDL_SCANCODE_ESCAPE] = KeyHandler(&close_page, "Close layouts settings", "Esc");
        gs.keybar.handlers_down[SDL_SCANCODE_LEFT] = KeyHandler(&left, "Left", "←");
        gs.keybar.handlers_down[SDL_SCANCODE_RIGHT] = KeyHandler(&right, "Right", "→");
        gs.keybar.handlers_down[SDL_SCANCODE_BACKSPACE] = KeyHandler(&backscape, "Backspace", "<--");
    }
}

