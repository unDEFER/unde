module unde.tick;

import unde.global_state;
import unde.lib;

static import unde.file_manager.events;
static import unde.viewers.image_viewer.events;
static import unde.viewers.text_viewer.events;
static import unde.command_line.events;
import unde.command_line.events: CommandLineEventHandlerResult;

import derelict.sdl2.sdl;
import berkeleydb.all;

enum unDE_MouseButtons {
    Left = 0x01,
    Middle = 0x02,
    Right = 0x04,
}

void make_tick(GlobalState gs)
{
    
}

RectSize getRectSize(GlobalState gs)
{
    RectSize rectsize;
    Dbt key, data;
    key = gs.current_path;
    auto res = gs.db_map.get(null, &key, &data);
    if (res == 0)
    {
        rectsize = data.to!(RectSize);
    }
    return rectsize;
}

void change_current_dir(GlobalState gs, void delegate (ref RectSize rectsize) change_rectsize)
{
    Dbt key, data;
    key = gs.current_path;
    auto res = gs.db_map.get(null, &key, &data);
    if (res == 0)
    {
        RectSize rectsize;
        rectsize = data.to!(RectSize);

        change_rectsize(rectsize);

        data = rectsize;
        res = gs.db_map.put(null, &key, &data);
        if (res != 0)
            throw new Exception("Path info to map-db not written");
    }
    gs.dirty = true;
}

void process_events(GlobalState gs)
{
    /* Our SDL event placeholder. */
    SDL_Event event;

    /* Grab all the events off the queue. */
    while( SDL_PollEvent( &event ) )
    {
        auto result = unde.command_line.events.process_event(gs, event);
        if (result == CommandLineEventHandlerResult.Pass)
        {
            final switch (gs.state)
            {
                case State.FileManager:
                    unde.file_manager.events.process_event(gs, event);
                    break;
                case State.ImageViewer:
                    unde.viewers.image_viewer.events.process_event(gs, event);
                    break;
                case State.TextViewer:
                    unde.viewers.text_viewer.events.process_event(gs, event);
                    break;
            }
        }
    }
}

void
make_screenshot(GlobalState gs) { 
    SDL_Surface *screenshot; 
    screenshot = SDL_CreateRGBSurface(SDL_SWSURFACE,
            gs.screen.w, 
            gs.screen.h, 
            32, 0x00FF0000, 0X0000FF00, 0X000000FF, 0XFF000000); 
    SDL_RenderReadPixels(gs.renderer, null, SDL_PIXELFORMAT_ARGB8888, 
            screenshot.pixels, screenshot.pitch);
    SDL_SaveBMP(screenshot, "screenshot.bmp"); 
    SDL_FreeSurface(screenshot); 

    //SDL_SaveBMP(gs.surface, "surface.bmp"); 
}

