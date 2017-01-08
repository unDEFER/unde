module unde.draw;

import unde.global_state;
import unde.lib;
import unde.scan;
import unde.file_manager.remove_paths;
import unde.file_manager.copy_paths;
import unde.file_manager.draw_path.draw_path;
import unde.marks;
import unde.file_manager.find_path;
import unde.file_manager.events;
import unde.viewers.image_viewer.lib;
import unde.viewers.text_viewer.lib;
import unde.command_line.lib;
import unde.keybar.lib;
import unde.tick;
import unde.path_mnt;
import unde.clickable;

import berkeleydb.all;
import core.thread;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;

import std.math;
import std.stdio;
import std.string;
import std.conv;
import std.container.slist;

enum unDE_Flags {
    Magnify   = 0x01,
    Unmagnify = 0x02,
    Left      = 0x04,
    Right     = 0x08,
    Up        = 0x10,
    Down      = 0x20,
}


class DrawPathFiber : Fiber
{
        GlobalState gs;
        CoordinatesPlusScale[] surface;
        int result;

        this(GlobalState gs, DbTxn txn, PathMnt path,
                DRect apply_rect,
                SortType sort,
                CoordinatesPlusScale[] surface)
        {
            this.gs = gs;
            this.txn = txn;
            this.path = path;
            this.apply_rect = apply_rect;
            this.sort = sort;
            this.surface = surface;

            super(&run, 65536);
        }

    private:
        DbTxn txn;
        PathMnt path;
        DRect apply_rect;
        SortType sort;

        void run()
        {
            result = draw_path(gs, txn, path, surface[0], apply_rect, sort);
            draw_marks(gs, surface[0]);
        }
}

/* EN: The difference of unDE_SDL_RenderCopy from SDL_RenderCopy is
    that x, y coordinates of srcrect, dstrect maybe negative
    and width, height maybe also more than texture or window size.
    And this works as expected.
   RU: Отличие unDE_SDL_RenderCopy от SDL_RenderCopy в том,
    что координвты x и y прямоугольников srcrect, dstrect могут
    быть отрицательными и ширина/высота также может выходить
    за рамки текстуры или окна и это работает как ожидается
 */
void unDE_RenderCopy(GlobalState gs,
        ref SDL_Rect srcrect, ref SDL_Rect dstrect)
{
    if (srcrect.x < 0)
    {
        dstrect.x = cast(int)(-srcrect.x*gs.surf.scale/gs.screen.scale);
        srcrect.x = 0;
    }
    if (srcrect.y < 0)
    {
        dstrect.y = cast(int)(-srcrect.y*gs.surf.scale/gs.screen.scale);
        srcrect.y = 0;
    }
    if ((srcrect.x+srcrect.w) > 2*gs.screen.w)
    {
        dstrect.w = cast(int)(gs.screen.w -
                (srcrect.x+srcrect.w - 2*gs.screen.w)*gs.surf.scale/gs.screen.scale);
        srcrect.w = cast(int)(2*gs.screen.w - srcrect.x);
    }
    if ((srcrect.y+srcrect.h) > 2*gs.screen.h)
    {
        dstrect.h = cast(int)(gs.screen.h -
                (srcrect.y+srcrect.h - 2*gs.screen.h)*gs.surf.scale/gs.screen.scale);
        srcrect.h = cast(int)(2*gs.screen.h - srcrect.y);
    }

    int r = SDL_RenderCopy(gs.renderer, gs.texture, &srcrect, &dstrect);
    if (r < 0)
    {
        writefln( "unDE_RenderCopy(): Error while render copy: %s", SDL_GetError().to!string() );
    }
}


/*RU: Рассчитать прямоугольник который занимает screen и surface
    и изменить размер surface если screen вышел за его пределы*/
CoordinatesPlusScale[]
calculate_rectangles_of_surf_and_screen_and_change_surf_size_if_needed(
        GlobalState gs, DrawPathFiber draw_path_fiber, ref bool redraw)
{
    DRect surf_rect = gs.surf.getRect();
    DRect scr_rect = gs.screen.getRect();

    int tries = 0;
    if ( draw_path_fiber is null &&
            ( (!scr_rect.In(surf_rect) ||
            gs.screen.scale < gs.surf.scale || 
            gs.screen.scale/gs.surf.scale > 2) || redraw || gs.dirty) )
    {
begin:
        tries++;
        redraw = false;
        gs.dirty = false;
        if (gs.selection_finish == 1 || 
                (gs.selection_finish == 0 && gs.selection_stage == 2))
        {
            gs.selection_lsof = cast(int)gs.selection_list.length;
            gs.selection_finish = 2;
        }

        int r = SDL_SetRenderTarget(gs.renderer, gs.surf_texture);
        if (r < 0)
        {
            throw new Exception(format("Error while set render target gs.surf_texture: %s",
                        SDL_GetError().to!string() ));
        }

        r = SDL_RenderClear(gs.renderer);
        if (r < 0)
        {
            throw new Exception(format("crosasacssin: Error while clear renderer: %s",
                    SDL_GetError().to!string() ));
        }

        r = SDL_SetRenderTarget(gs.renderer, null);
        if (r < 0)
        {
            throw new Exception(format("Error while restore render target: %s",
                    SDL_GetError().to!string() ));
        }

        auto surface = new CoordinatesPlusScale[1];
        surface[0].scale = gs.screen.scale/sqrt(2.0);

        surface[0].x = gs.screen.x - 
            surface[0].scale*(gs.screen.w*sqrt(2.0) - gs.screen.w)/2;
        surface[0].y = gs.screen.y - 
            surface[0].scale*(gs.screen.h*sqrt(2.0) - gs.screen.h)/2;
        surface[0].w = gs.surf.w;
        surface[0].h = gs.surf.h;

        {
            surf_rect = surface[0].getRect();
            if ((!scr_rect.In(surf_rect) ||
                        gs.screen.scale < surface[0].scale || 
                        gs.screen.scale/surface[0].scale > 2))
            {
                scr_rect = DRect(0, 0, 0, 0);
                gs.initScreenAndSurf();
                if (tries < 2)
                    goto begin;
            }
            assert(!(!scr_rect.In(surf_rect) ||
                        gs.screen.scale < surface[0].scale || 
                        gs.screen.scale/surface[0].scale > 2));
        }
        return surface;
    }
    else
        return null;
}

/* RU: рисовать "путь" не больше 100 мс и если успели дорисовать
    преобразовать surface в текстуру */
void draw_path_while_there_is_time_and_create_texture_if_it_is_finished(
        GlobalState gs, ref DrawPathFiber draw_path_fiber, ref bool redraw)
{
    int r = SDL_SetRenderTarget(gs.renderer, gs.surf_texture);
    if (r < 0)
    {
        throw new Exception(format("Error while set render target gs.surf_texture: %s",
                    SDL_GetError().to!string() ));
    }

    uint max_draw_tick = SDL_GetTicks() + 100;
    while (draw_path_fiber.state != Fiber.State.TERM &&
            (SDL_GetTicks() < max_draw_tick || 
             gs.texture == null) )
    {
        draw_path_fiber.call();
    }

    r = SDL_SetRenderTarget(gs.renderer, null);
    if (r < 0)
    {
        throw new Exception(format("Error while restore render target: %s",
                SDL_GetError().to!string() ));
    }

    if (draw_path_fiber.state == Fiber.State.TERM)
    {
        if (draw_path_fiber.result < 0)
            redraw = true;

        gs.surf = draw_path_fiber.surface[0];
        draw_path_fiber = null;

        gs.clickable_list = gs.new_clickable_list;
        gs.new_clickable_list = SList!Clickable();

        gs.double_clickable_list = gs.new_double_clickable_list;
        gs.new_double_clickable_list = SList!Clickable();

        gs.right_clickable_list = gs.new_right_clickable_list;
        gs.new_right_clickable_list = SList!Clickable();

        gs.double_right_clickable_list = gs.new_double_right_clickable_list;
        gs.new_double_right_clickable_list = SList!Clickable();

        gs.middle_clickable_list = gs.new_middle_clickable_list;
        gs.new_middle_clickable_list = SList!Clickable();

        if (gs.selection_finish == 2)
        {
            gs.selection_list = gs.selection_list[gs.selection_lsof..$];
            calculate_selection_sub(gs);
                
            gs.selection_lsof = 0;
            gs.selection_finish = 0;
            /*writefln("Selected:");
            foreach(key; gs.selection_hash.byKey())
            {
                writefln("%s", key);
            }*/
        }

        auto texture = gs.texture;
        gs.texture = gs.surf_texture;
        gs.surf_texture = texture;
    }
    else
    {
        process_events(gs);
    }
}

void draw_anim(GlobalState gs)
{
    foreach (path, ref created_directory; gs.animation_info)
    {
        if (created_directory.from_calculated &&
                created_directory.to_calculated)
        {
            with (created_directory)
            {
                if (frame >= 100)
                {
                    gs.animation_info.remove(path);
                    continue;
                }
                SDL_Rect rect;
                rect.x = from.x + (to.x - from.x)*cast(int)frame/100;
                rect.y = from.y + (to.y - from.y)*cast(int)frame/100;
                rect.w = from.w + (to.w - from.w)*cast(int)frame/100;
                rect.h = from.h + (to.h - from.h)*cast(int)frame/100;
                int r = SDL_RenderCopy(gs.renderer, gs.texture_white, null, &rect);
                if (r < 0)
                {
                    writefln( "draw_anim(): Error while render copy: %s", SDL_GetError().to!string() );
                }

                if (last_frame_time)
                {
                    frame += cast(double)(SDL_GetTicks() - last_frame_time)/10;
                }
                last_frame_time = SDL_GetTicks();
            }
        }
    }
}

void draw_messages(GlobalState gs)
{
    ssize_t first = -1;
    int line = 24;
    ulong y_off;
    foreach(i, mes; gs.messages)
    {
        if (SDL_GetTicks() - mes.from < 5000)
        {
            if (first == -1) 
            {
                first = i;

                y_off = gs.screen.h - line*3 - line*(gs.messages.length - first) - 8;

                /* EN: render background of console messages
                   RU: рендерим фон консоли сообщений */
                SDL_Rect rect;
                rect.x = 32;
                rect.y = cast(int)y_off;
                rect.w = gs.screen.w - 32*2;
                rect.h = cast(int)(line*(gs.messages.length - first) + 8);

                int r = SDL_RenderCopy(gs.renderer, gs.texture_black, null, &rect);
                if (r < 0)
                {
                    writefln( "draw_messages(), 1: Error while render copy: %s",
                            SDL_GetError().to!string() );
                }
            }

            if (mes.texture == null && mes.message != "")
            {
                int line_height = cast(int)(round(SQRT2^^9)*1.2);
                auto tt = gs.text_viewer.font.get_line_from_cache(mes.message, 
                        9, gs.screen.w - 80, line_height, mes.color);
                if (!tt && !tt.texture)
                {
                    throw new Exception("Can't create text_surface: "~
                            to!string(TTF_GetError()));
                }

                mes.w = tt.w;
                mes.h = tt.h;

                mes.texture = tt.texture;
            }

            if (mes.texture != null)
            {
                /* EN: Render text to screeb
                   RU: Рендерим текст на экран */
                SDL_Rect rect;
                rect.x = 40;
                rect.y = cast(int)(y_off + 4 + line*(i-first));
                rect.w = mes.w;
                rect.h = mes.h;

                int r = SDL_RenderCopy(gs.renderer, mes.texture, null, &rect);
                if (r < 0)
                {
                    writefln(
                        "draw_messages(), 2: Error while render copy: %s", 
                        SDL_GetError().to!string() );
                }
            }
        }
        else
        {
            SDL_DestroyTexture(mes.texture);
        }
    }
    if (first > 0)
        gs.messages = gs.messages[first..$];
}

void draw_screen(GlobalState gs, DbTxn txn)
{
    SDL_SetRenderDrawColor(gs.renderer, 0, 0, 0, 0);
    SDL_RenderClear(gs.renderer);

    static DrawPathFiber draw_path_fiber;
    static bool redraw;

    check_scanners(gs);

    final switch (gs.state)
    {
        case State.FileManager:
            auto new_surface_coordinates =
            calculate_rectangles_of_surf_and_screen_and_change_surf_size_if_needed(
                    gs, draw_path_fiber, redraw);
            if (new_surface_coordinates)
            {
                find_path(gs, txn, new_surface_coordinates[0], gs.path, gs.apply_rect, gs.sort);
                //writefln("find_path: path=%s", gs.path);
                draw_path_fiber = new DrawPathFiber(
                        gs, txn, gs.path, gs.apply_rect, gs.sort,
                        new_surface_coordinates);
            }

            if (draw_path_fiber !is null)
            {
                draw_path_while_there_is_time_and_create_texture_if_it_is_finished(
                        gs, draw_path_fiber, redraw);
            }

            SDL_Rect srcrect;
            srcrect.x = cast(int)((gs.screen.x - gs.surf.x)/gs.surf.scale);
            srcrect.y = cast(int)((gs.screen.y - gs.surf.y)/gs.surf.scale);
            srcrect.w = cast(int)(gs.screen.w*gs.screen.scale/gs.surf.scale);
            srcrect.h = cast(int)(gs.screen.h*gs.screen.scale/gs.surf.scale);

            SDL_Rect dstrect;
            dstrect.x = 0;
            dstrect.y = 0;
            dstrect.w = gs.screen.w;
            dstrect.h = gs.screen.h;

            unDE_RenderCopy(gs, srcrect, dstrect);

            draw_anim(gs);
            break;

        case State.ImageViewer:
            draw_image(gs);
            break;

        case State.TextViewer:
            draw_text(gs);
            break;
    }

    setup_keybar(gs);
    draw_messages(gs);
    draw_command_line(gs);
    draw_keybar(gs);
    remark_desktop(gs);

    SDL_SetRenderTarget(gs.renderer, null);
    SDL_RenderPresent(gs.renderer);
}
