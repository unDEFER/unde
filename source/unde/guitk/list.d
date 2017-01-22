module unde.guitk.list;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;
import derelict.sdl2.image;

import std.stdio;
import std.math;
import std.string;

import unde.global_state;
import unde.guitk.lib;
import unde.keybar.lib;
import unde.lib;
import unde.tick;

version(Windows)
{
import berkeleydb.all: ssize_t;
}

class List:UIEntry
{
    private SDL_Rect _rect;
    private UIPage _page;
    private bool _focus;
    string[] list;
    private bool[ssize_t] _selected;
    string filter;
    private int x;
    private int y;
    private ssize_t pos;
    private ssize_t mouse_pos;
    private int fontsize;
    private int line_height;
    private SDL_Color color;
    private bool wraplines;
    private int multiselect;

    this(UIPage page, SDL_Rect rect, string[] list, int multiselect = 2,
            SDL_Color color = SDL_Color(0xFF, 0xFF, 0xFF, 0xFF))
    {
        _page = page;
        _rect = rect;
        this.list = list;
        fontsize = 9;
        line_height = cast(int)(round(SQRT2^^fontsize)*1.2);
        this.multiselect = multiselect;
        this.color = color;
    }

    @property ref bool[ssize_t] selected() {return _selected;}

    @property SDL_Rect rect() {return _rect;}

    void delegate (GlobalState gs) pre_draw;
    
    void on_draw(GlobalState gs)
    {
        if (pre_draw) pre_draw(gs);
        /* Background */
        auto r = SDL_RenderCopy(gs.renderer, gs.texture_gray, null, &_rect);
        if (r < 0)
        {
            writefln( "List.on_draw(), 1: Error while render copy: %s",
                    SDL_GetError().fromStringz() );
        }

        if (y > 0)
        {
            int y_off = cast(int)(_rect.y + y);

            for (ssize_t i = pos-1; i >= 0; i--)
            {
                if (filter > "" && list[i].indexOf(filter) < 0)
                    continue;

                auto rect = gs.text_viewer.font.get_size_of_line(list[i],
                        fontsize,  wraplines ? _rect.w : 0, line_height, color);

                pos = i;
                y -= rect.h;
                y_off -= rect.h;

                if (y_off < _rect.y)
                {
                    break;
                }
            }
        }

        int y_off = cast(int)(_rect.y + y);

        for (ssize_t i = pos; i < list.length; i++)
        {
            if (filter > "" && list[i].indexOf(filter) < 0)
                continue;

            ssize_t start_pos = -1;
            ssize_t end_pos = -1;
            if (i in _selected)
            {
                start_pos = 0;
                end_pos = list[i].length-1;
            }
            auto tt = gs.text_viewer.font.get_line_from_cache(list[i], 
                    fontsize, wraplines ? _rect.w : 0, line_height, color,
                    null, start_pos, end_pos);
            if (!tt && !tt.texture)
            {
                throw new Exception("Can't create text_surface: "~
                        TTF_GetError().fromStringz().idup());
            }

            if (y_off + tt.h < _rect.y)
            {
                pos = i+1;
                y += tt.h;
                y_off += tt.h;
                continue;
            }

            SDL_RenderSetClipRect(gs.renderer, &_rect);

            SDL_Rect rect;
            rect.x = _rect.x + x;
            rect.y = y_off;
            rect.w = tt.w;
            rect.h = tt.h;

            if (gs.mouse_screen_x > rect.x && gs.mouse_screen_x < rect.x+rect.w &&
                    gs.mouse_screen_y > rect.y && gs.mouse_screen_y < rect.y+rect.h)
            {
                mouse_pos = i;
            }

            r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
            if (r < 0)
            {
                writefln(
                        "List.on_draw(), 2: Error while render copy: %s", 
                        SDL_GetError().fromStringz() );
            }

            SDL_RenderSetClipRect(gs.renderer, null);

            if (rect.y + rect.h > _rect.y + _rect.h)
            {
                break;
            }

            y_off += tt.h;
        }
    }

    void delegate (GlobalState gs, ssize_t pos) on_select;
    void delegate (GlobalState gs, ssize_t pos) on_deselect;

    void process_event(GlobalState gs, SDL_Event event)
    {
        switch (event.type)
        {
            case SDL_MOUSEMOTION:
                if (gs.mouse_buttons & unDE_MouseButtons.Left)
                {
                    if (!wraplines)
                        x += event.motion.xrel;
                    y += event.motion.yrel;
                }
                break;

            case SDL_MOUSEBUTTONDOWN:
                break;

            case SDL_MOUSEBUTTONUP:
                switch (event.button.button)
                {
                    case SDL_BUTTON_LEFT:
                        set_focus(gs);
                        break;

                    case SDL_BUTTON_RIGHT:
                        if (SDL_GetTicks() - gs.last_right_click < DOUBLE_DELAY)
                        {
                        }
                        else
                        {
                            switch (multiselect)
                            {
                                case 0:
                                    break;

                                case 1:
                                    _selected.clear();
                                    _selected[mouse_pos] = true;
                                    if (on_select)
                                        on_select(gs, mouse_pos);
                                    break;

                                case 2:
                                    if (mouse_pos in _selected)
                                    {
                                        _selected.remove(mouse_pos);
                                        if (on_deselect)
                                            on_deselect(gs, mouse_pos);
                                    }
                                    else
                                    {
                                        _selected[mouse_pos] = true;
                                        if (on_select)
                                            on_select(gs, mouse_pos);
                                    }
                                    break;

                                default:
                                    assert(0);
                            }
                        }
                        break;
                    default:
                        break;
                }
                break;

            case SDL_MOUSEWHEEL:
                break;
            default:
                break;
        }
    }

    @property UIPage page() {return _page;}

    @property ref bool focus() {return _focus;}

    void on_set_focus(GlobalState gs)
    {
    }

    void on_unset_focus(GlobalState gs)
    {
    }

    private void
    close_page(GlobalState gs)
    {
        _page.show = false;
    }

    private void
    change_wrap_mode(GlobalState gs)
    {
        wraplines = !wraplines;
        if (wraplines)
        {
            x = 0;
        }
    }

    void set_keybar(GlobalState gs)
    {
        gs.keybar.handlers.clear();
        gs.keybar.handlers_down.clear();
        gs.keybar.handlers_double.clear();

        gs.keybar.handlers[SDL_SCANCODE_ESCAPE] = KeyHandler(&close_page, "Close layouts settings", "Esc");
        gs.keybar.handlers[SDL_SCANCODE_W] = KeyHandler(&change_wrap_mode, "On/Off wrap lines", "Wrap");
    }
}

