module unde.guitk.background;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;
import derelict.sdl2.image;

import std.stdio;
import std.string;

import unde.global_state;
import unde.guitk.lib;
import unde.keybar.lib;
import unde.lib;

class Background:UIEntry
{
    private SDL_Rect _rect;
    private UIPage _page;
    private bool _focus;

    private string label;
    private SDL_Color color;
    private int fontsize;
    
    this(UIPage page, GlobalState gs)
    {
        _page = page;
        _rect.x = 0;
        _rect.y = 0;
        _rect.w = gs.screen.w;
        _rect.h = gs.screen.h;
    }

    @property SDL_Rect rect() {return _rect;}
    
    void on_draw(GlobalState gs)
    {
        auto r = SDL_RenderCopy(gs.renderer, gs.texture_black, null, &_rect);
        if (r < 0)
        {
            writefln( "Background.on_draw(), 1: Error while render copy: %s",
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

    private void
    close_page(GlobalState gs)
    {
        _page.show = false;
    }

    void set_keybar(GlobalState gs)
    {
        gs.keybar.handlers.clear();
        gs.keybar.handlers_down.clear();
        gs.keybar.handlers_double.clear();

        gs.keybar.handlers[SDL_SCANCODE_ESCAPE] = KeyHandler(&close_page, "Close layouts settings", "Esc");
    }
}

