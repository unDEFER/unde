module unde.clickable;

import unde.lib;
import unde.global_state;

import derelict.sdl2.sdl;
import std.stdio;
import std.container.slist;

class Clickable
{
    GlobalState gs;
    SDL_Rect rect;
    void delegate(GlobalState gs, int stage) event;

    this(GlobalState gs, SDL_Rect rect, void delegate(GlobalState gs, int stage) event)
    {
        this.gs = gs;
        this.rect = rect;
        this.event = event;
    }

    bool click(int x, int y, int stage)
    {
        double surf_x = (cast(double)x*gs.screen.scale -
                (gs.surf.x - gs.screen.x))/gs.surf.scale;
        double surf_y = (cast(double)y*gs.screen.scale -
                (gs.surf.y - gs.screen.y))/gs.surf.scale;
        bool res = surf_x > rect.x && surf_x < (rect.x+rect.w) &&
            surf_y > rect.y && surf_y < (rect.y+rect.h);
        if (res)
        {
            event(gs, stage);
        }
        return res;
    }
}

bool process_click(SList!Clickable clickable_list, int x, int y, int stage = 0)
{
    foreach(clickable; clickable_list[])
    {
        clickable.click(x, y, stage);
    }
    return true;
}
