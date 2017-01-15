module unde.guitk.lib;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;
import derelict.sdl2.image;

import unde.global_state;

interface UIEntry
{
    @property SDL_Rect rect();
    void on_draw(GlobalState gs);
    void process_event(GlobalState gs, SDL_Event event);
    @property UIPage page();
    @property ref bool focus();
    void on_set_focus(GlobalState gs);
    void on_unset_focus(GlobalState gs);
    void set_keybar(GlobalState gs);

    final void unset_focus(GlobalState gs)
    {
        on_unset_focus(gs);
        focus = false;
        page.focused = null;
    }

    final void set_focus(GlobalState gs)
    {
        if (page.focused)
            page.focused.unset_focus(gs);
        focus = true;
        page.focused = this;
        on_set_focus(gs);
    }
}

class UIPage
{
    bool show;
    private UIEntry[] entries;
    UIEntry focused;

    void on_draw(GlobalState gs)
    {
        foreach (entry; entries)
        {
            entry.on_draw(gs);
        }
    }

    void add_entry(GlobalState gs, UIEntry entry)
    {
        entries ~= entry;
        if (!focused) entry.set_focus(gs);
    }

    void process_event(GlobalState gs, SDL_Event event)
    {
        foreach (entry; entries)
        {
            switch(event.type)
            {
                case SDL_MOUSEMOTION:
                    goto case;
                case SDL_MOUSEBUTTONDOWN:
                    goto case;
                case SDL_MOUSEBUTTONUP:
                    goto case;
                case SDL_MOUSEWHEEL:
                    if (gs.mouse_screen_x > entry.rect.x &&
                            gs.mouse_screen_x < entry.rect.x + entry.rect.w &&
                            gs.mouse_screen_y > entry.rect.y &&
                            gs.mouse_screen_y < entry.rect.y + entry.rect.h)
                        entry.process_event(gs, event);
                    break;
                case SDL_TEXTINPUT:
                    if (entry.focus)
                    {
                        entry.process_event(gs, event);
                    }
                    break;
                default:
                    entry.process_event(gs, event);
            }
        }
    }

    void set_keybar(GlobalState gs)
    {
        if (focused)
            focused.set_keybar(gs);
    }
}

