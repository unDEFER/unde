module unde.guitk.label;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;
import derelict.sdl2.image;

import std.stdio;
import std.math;
import std.string;

import unde.global_state;
import unde.guitk.lib;

class Label:UIEntry
{
    private SDL_Rect _rect;
    private UIPage _page;
    private bool _focus;

    private string label;
    private SDL_Color color;
    private int fontsize;
    
    this(UIPage page, GlobalState gs, string label, int x, int y, int fontsize=9,
            SDL_Color color = SDL_Color(0xFF, 0xFF, 0xFF, 0xFF))
    {
        _page = page;
        this.label = label;
        this.fontsize = fontsize;
        this.color = color;

        _rect.x = x;
        _rect.y = y;

        int line_height = cast(int)(round(SQRT2^^fontsize)*1.2);

        auto tt = gs.text_viewer.font.get_line_from_cache(label, 
                fontsize, 0, line_height, color);
        if (!tt && !tt.texture)
        {
            throw new Exception("Can't create text_surface: "~
                    TTF_GetError().fromStringz().idup());
        }

        _rect.w = tt.w;
        _rect.h = tt.h;
    }

    @property SDL_Rect rect() {return _rect;}
    
    void on_draw(GlobalState gs)
    {
        int line_height = cast(int)(round(SQRT2^^fontsize)*1.2);

        auto tt = gs.text_viewer.font.get_line_from_cache(label, 
                fontsize, 0, line_height, color);
        if (!tt && !tt.texture)
        {
            throw new Exception("Can't create text_surface: "~
                    TTF_GetError().fromStringz().idup());
        }

        SDL_Rect rect;
        rect.x = _rect.x;
        rect.y = _rect.y;
        rect.w = tt.w;
        rect.h = tt.h;

        auto r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
        if (r < 0)
        {
            writefln(
                    "Label.on_draw() %s: Error while render copy: %s", 
                    label,
                    SDL_GetError().fromStringz() );
        }
    }

    void process_event(GlobalState gs, SDL_Event event)
    {
    }

    @property UIPage page() {return _page;}

    @property ref bool focus() {return _focus;}

    void on_set_focus(GlobalState gs)
    {
    }

    void on_unset_focus(GlobalState gs)
    {
    }

    void set_keybar(GlobalState gs)
    {
    }
}

