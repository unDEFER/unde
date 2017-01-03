module unde.file_manager.draw_path.draw_elements;

import unde.global_state;
import unde.lib;
import unde.viewers.image_viewer.lib;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;
import derelict.sdl2.image;

import std.stdio;
import std.conv;
import std.math;
import std.string;
import std.exception;
import std.utf;

package class SDL_Rect_With_Not_Visible_And_No_Draw
{
    SDL_Rect sdl_rect;
    bool not_visible;
    bool no_draw;
    bool current_path;
}

package SDL_Rect_With_Not_Visible_And_No_Draw
draw_rect_with_color_by_size(GlobalState gs, ref RectSize rectsize,
        SortType sort,
        ref CoordinatesPlusScale surf, bool selected = false,
        string path = "")
{
    if (rectsize.rect(sort).w == 0) rectsize.rect(sort).w = 1;
    if (rectsize.rect(sort).h == 0) rectsize.rect(sort).h = 1;
    //double density = cast(double)(rectsize.size)/(rectsize.w*rectsize.h);
    //double density_level = log10(density);
    uint color = 0x80FFFFFF;
    if (selected)
    {
        color = 0x800000FF;
    }
    else if (rectsize.size >= 0)
    {
        double size_level = log10(rectsize.size);

        SDL_Color rgba = gs.grad.getColor(size_level);
        /*writefln("%s. (%s / %sx%s) size_level=%.2f, color=(%d, %d, %d)",
                  path, rectsize.size, rectsize.w, rectsize.h,
                  size_level,
                  rgba.r, rgba.g, rgba.b);*/
        color = (0x80<<24) | (rgba.r<<16) | (rgba.g<<8) | rgba.b;
    }

    auto ret = new SDL_Rect_With_Not_Visible_And_No_Draw;

    /* EN: Calculate output square coordiantes for path
       RU: Расчитать координаты квадрата для пути */
    SDL_Rect sdl_rect = rectsize.rect(sort).to_screen(surf);
    /*writefln("surf_scale=%s", scale);
    writefln("%s rectsize(%s, %s, %s, %s) - sdl_rect(%s, %s, %s, %s)",
            path,
            rectsize.x, rectsize.y, rectsize.w, rectsize.h,
            sdl_rect.x, sdl_rect.y, sdl_rect.w, sdl_rect.h);*/

    /* EN: not visible if it go out of surface
       RU: не видимый если выходит за рамки surface'а */
    bool not_visible = (sdl_rect.x+sdl_rect.w)<0 || sdl_rect.x > gs.surf.w ||
        (sdl_rect.y+sdl_rect.h) < 0 || sdl_rect.y > gs.surf.h;
    //bool no_draw = (2*sdl_rect.w > width && 2*sdl_rect.h > height);

    SDL_Rect onscreen_rect = rectsize.rect(sort).to_screen(gs.screen);

    /* EN: no draw if too big and takes almost all screen
       RU: не рисовать, если занимает почти весь экран
         (т.е. прямоугольник исчезает при приближении) */
    bool no_draw = onscreen_rect.x < gs.screen.w/8 &&
        (onscreen_rect.x+onscreen_rect.w)>(gs.screen.w*7/8) ||
        onscreen_rect.y < gs.screen.h/8 &&
        (onscreen_rect.y+onscreen_rect.h)>(gs.screen.h*7/8) ||
        not_visible ||
        sdl_rect.w > 2000 || sdl_rect.h > 2000;

    bool current_path = (no_draw || not_visible) &&
        onscreen_rect.x <= gs.screen.w/2 && (onscreen_rect.x+onscreen_rect.w) >= (gs.screen.w*1/2) &&
        onscreen_rect.y <= gs.screen.h/2 && (onscreen_rect.y+onscreen_rect.h) >= (gs.screen.h*1/2);

    if ( current_path )
        gs.current_path_rect = rectsize.rect(sort);

    if (!no_draw && !not_visible)
    {
        SDL_Rect sdl_rect_dup = sdl_rect;
        unDE_RenderFillRect(gs.renderer, &sdl_rect_dup, color);
    }

    ret.sdl_rect = sdl_rect;
    ret.not_visible = not_visible;
    ret.no_draw = no_draw;
    ret.current_path = current_path;

    return ret;
}

package void
draw_center_rect_with_color(
        GlobalState gs,
        SDL_Rect_With_Not_Visible_And_No_Draw rnvnd,
        uint color)
{
    SDL_Rect sdl_rect = rnvnd.sdl_rect;
    sdl_rect.x = sdl_rect.x+sdl_rect.w/3;
    sdl_rect.y = sdl_rect.y+sdl_rect.h/3;
    sdl_rect.w /= 3;
    sdl_rect.h /= 3;

    if (!rnvnd.no_draw && !rnvnd.not_visible)
    {
        SDL_Rect sdl_rect_dup = sdl_rect;
        unDE_RenderFillRect(gs.renderer, &sdl_rect_dup, color);
    }
}

/* EN: draw picture - interface element
   RU: рисует картинку - элемент интерфейса */
/*
package SDL_Rect
draw_interface_picture(GlobalState gs,
        string path,
        int x, int y,
        double scale,
        in ref SDL_Rect rect)
{
    immutable int text_size = 1024;

    x = x * rect.w/text_size;
    y = y * rect.h/text_size;

    auto st = get_image_from_cache(gs, path);
    
    SDL_Rect dst;
    if (st && st.texture)
    {
        dst.x = rect.x + x;
        dst.y = rect.y + y;
        dst.w = cast(int)(st.w*rect.w*scale/1024.0);
        dst.h = cast(int)(st.h*rect.h*scale/1024.0);

        int r = SDL_RenderCopyEx(gs.renderer, st.texture, null, &dst, 0,
                    null, SDL_FLIP_NONE);
        if (r < 0)
        {
            writefln( "draw_interface_picture(%s): Error while render copy: %s", 
                    path, SDL_GetError().to!string() );
        }
    }
    else
    {
        writefln("Can't load %s: %s",
                path,
                to!string(IMG_GetError()));
    }
    return dst;
}
*/

package SDL_Rect
draw_button(GlobalState gs,
        int x, int y,
        int w, int h,
        in ref SDL_Rect rect)
{
    immutable int text_size = 1024;

    x = x * rect.w/text_size;
    y = y * rect.h/text_size;

    SDL_Rect dst;
    dst.x = rect.x + x;
    dst.y = rect.y + y;
    dst.w = cast(int)(w*rect.w/1024.0);
    dst.h = cast(int)(h*rect.h/1024.0);

    unDE_RenderFillRect(gs.renderer, &dst, 0xFF000080);

    return dst;
}

/* EN: draw file-picture
   RU: рисует файл-картинку */
package bool
draw_picture(GlobalState gs,
        in ref SDL_Rect_With_Not_Visible_And_No_Draw rnvnd,
        in string p,
        in bool fast,
        ref int ret)
{
    Texture_Tick *st;
    /* EN: Get picture from cache or load it from file
       RU: Получить картинку из кеша или загрузить из файла */
    if ( !p.endsWith(".xcf") )
    {
        with (gs.image_viewer)
        {
            st = p in image_cache;
            if (st)
            {
                //writefln("Get from cache %s", p);
                st.tick = SDL_GetTicks();
                last_image_cache_use = SDL_GetTicks();
            }
            else if (!fast)
            {
                //writefln("Load image %s", p);
                long tick1 = SDL_GetTicks();
                auto surface = IMG_Load(p.toStringz());
                long tick2 = SDL_GetTicks();
                //writefln("%.3f s", (cast(double)tick2-tick1)/1000);
                if (surface)
                {
                    auto image_texture =
                        SDL_CreateTextureFromSurface(gs.renderer, surface);

                    image_cache[p] = Texture_Tick(surface.w, surface.h, [], image_texture, SDL_GetTicks());
                    SDL_FreeSurface(surface);
                    last_image_cache_use = SDL_GetTicks();
                    st = p in image_cache;
                    //writefln("Add to cache %s", p);
                }

                if (tick2-tick1 > 100)
                {
                    ret = -1;
                }
            }
        }
    }

    if (st && st.texture)
    {
        SDL_Rect dst;
        /* EN: Calculate output rectangle:
           RU: Рассчитать выходной прямоугольник: */
        /* EN: If output square for path more than picture
           RU: Если выходной квадрат для пути больше картинки */
        if (rnvnd.sdl_rect.w > st.w && rnvnd.sdl_rect.h > st.h)
        {
            /* EN: If square of path takes width less 512
               RU: Если квадрат пути занимает по ширине меньше 512 */
            if (rnvnd.sdl_rect.w < 512)
            {
                /* EN: Draw picture at the centre without scaling
                   RU: Рисуем картинку по центру без увеличения */
                dst.x = rnvnd.sdl_rect.x + (rnvnd.sdl_rect.w-st.w)/2;
                dst.y = rnvnd.sdl_rect.y + (rnvnd.sdl_rect.h-st.h)/2;
                dst.w = st.w;
                dst.h = st.h;
            }
            /* EN: If the picture less by width and height 512
               RU: Если сама картинка меньше по высоте и ширине 512 */
            else if ( st.w < 512 && st.h < 512 )
            {
                /* EN: Scale up and center picture
                   RU: Отцентрировать и увеличить картинку, учитывая
                    что при размере выходного квадрата <= 512 (см. выше)
                    она имеет масштаб 100% */
                dst.x = cast(int)(rnvnd.sdl_rect.x +
                        (rnvnd.sdl_rect.w-st.w*rnvnd.sdl_rect.w/512.0)/2);
                dst.y = cast(int)(rnvnd.sdl_rect.y +
                        (rnvnd.sdl_rect.h-st.h*rnvnd.sdl_rect.w/512.0)/2);
                dst.w = cast(int)(st.w*rnvnd.sdl_rect.w/512.0);
                dst.h = cast(int)(st.h*rnvnd.sdl_rect.w/512.0);
            }
            else
            {
                goto other;
            }
        }
        else
        {
        other:
            if (st.w > st.h)
            {
                /* EN: Center and scale down picture to take all width
                    of path square
                   RU: Отцентрировать и уменьшить картинку так, чтобы
                    она заняла всю ширину квадрата */
                dst.x = rnvnd.sdl_rect.x;
                dst.y = rnvnd.sdl_rect.y+
                    (rnvnd.sdl_rect.h-rnvnd.sdl_rect.h*st.h/st.w)/2;
                dst.w = rnvnd.sdl_rect.w;
                dst.h = rnvnd.sdl_rect.h*st.h/st.w;
            }
            else
            {
                /* EN: Center and scale down picture to take all height
                    of path square
                   RU: Отцентрировать и уменьшить картинку так, чтобы
                    она заняла всю высоту квадрата */
                dst.x = rnvnd.sdl_rect.x+
                    (rnvnd.sdl_rect.w-rnvnd.sdl_rect.w*st.w/st.h)/2;
                dst.y = rnvnd.sdl_rect.y;
                dst.w = rnvnd.sdl_rect.w*st.w/st.h;
                dst.h = rnvnd.sdl_rect.h;
            }
        }

        int r = SDL_RenderCopyEx(gs.renderer, st.texture, null, &dst, 0,
                    null, SDL_FLIP_NONE);
        if (r < 0)
        {
            writefln( "draw_picture(%s): Error while render copy: %s", 
                    p, SDL_GetError().to!string() );
        }

        return true;
    }
    else
        return false;
}

package SDL_Rect
draw_line(GlobalState gs, string text, 
        double x, double y, int size, const SDL_Rect rect)
{
    if (text.length > 0 && text[$-1] == '\r') text = text[0..$-1];

    immutable int text_size = 1024;

    x = x * rect.w/text_size;
    y = y * rect.h/text_size;

    int line_height = cast(int)(round(SQRT2^^size)*1.2);
    auto tt = gs.text_viewer.font.get_line_from_cache(text, 
            size, 0, line_height, SDL_Color(255, 255, 255, 255));
    if (!tt && !tt.texture)
    {
        /*throw new Exception("Can't create text_surface: "~
                to!string(TTF_GetError()));*/
        return SDL_Rect();
    }

    auto text_texture = tt.texture;

    long line_ax = cast(long)(x + rect.x);
    long line_ay = cast(long)(y + rect.y);
    /*if (line_x == 0 && line_y == 0)
    {
        writefln("sdl_rect.x=%s, line_ax=%s\n",
                rnvnd.sdl_rect.x, line_ax);
    }*/

    SDL_Rect src;
    src.x = 0;
    src.y = 0;
    src.w = (tt.w > 2*text_size) ?
        2*text_size :
        tt.w;
    src.h = tt.h;

    SDL_Rect dst;
    dst.x = cast(int)line_ax;
    dst.y = cast(int)line_ay;
    dst.w = (tt.w > 2*text_size) ?
        cast(int)(rect.w) :
        cast(int)(tt.w*rect.w/text_size/2.0);
    dst.h =
        cast(int)(tt.h*rect.h/text_size/2.0);
    /*writefln("%s - %s, %s, %s, %s",
            line, dst.x, dst.y, dst.w, dst.h);*/

    int r = SDL_RenderCopyEx(gs.renderer, text_texture, null, &dst, 0,
                null, SDL_FLIP_NONE);
    if (r < 0)
    {
        writefln( "draw_line(%s): Error while render copy: %s", text, SDL_GetError().to!string() );
    }

    return dst;
}

/* RU: Попытаться найти плохой UTF-8 символ в буфере */
private void
try_find_bad_utf8_character(in ubyte[] buf, 
        out bool wrongSymbolFound,
        out int reason)
{
    int sizeofsymbol = 0;

    foreach(b; buf)
    {
        if (sizeofsymbol > 0)
        {
            if ((b & 0b11000000) == 0b10000000)
            {
                sizeofsymbol--;
            }
            else
            {
                reason = 1;
                wrongSymbolFound = true;
                break;
            }
        }
        else
        {
            if ((b & 0x10000000) == 0)
            {
                if (b < 32 && b != 0x0a && b != 0x0d && b != 0x09)
                {
                    reason = 2;
                    wrongSymbolFound = true;
                    break;
                }
            }
            else if ((b & 0b11100000) == 0b11000000)
            {
                sizeofsymbol = 1;
            }
            else if ((b & 0b11110000) == 0b11100000)
            {
                sizeofsymbol = 2;
            }
            else if ((b & 0b11111000) == 0b11110000)
            {
                sizeofsymbol = 3;
            }
            else if ((b & 0b11111100) == 0b11111000)
            {
                sizeofsymbol = 4;
            }
            else if ((b & 0b11111110) == 0b11111100)
            {
                sizeofsymbol = 5;
            }
            else
            {
                reason = 3;
                wrongSymbolFound = true;
                break;
            }
        }
    }
}


package void
draw_text_file(GlobalState gs,
        in ref SDL_Rect_With_Not_Visible_And_No_Draw rnvnd,
        in string path,
        ref int ret)
{
    File file;
    try {
        file = File(path);
    }
    catch (Exception exp)
    {
        return;
    }

    ubyte[] buf;
    bool wrongSymbolFound = false;
    int reason = 0;

    try {
        buf = file.byChunk(4096).front();
        try_find_bad_utf8_character(buf, wrongSymbolFound, reason);
    }
    catch (ErrnoException)
    {
        reason = 4;
        wrongSymbolFound = true;
    }

    /*if (path.endsWith(".brs"))
    {
        writefln("reason=%s, wrongSymbolFound=%s", reason, wrongSymbolFound);
    }*/

    if (!wrongSymbolFound && !path.endsWith(".pdf") && !path.endsWith(".ps"))
    {
        try{
            file.seek(0);
            long lines = 0;
            foreach(line; file.byLine())
            {
                double line_y = 18*lines;
                double line_x = 0;
                if (line_y+18 > 1024)
                {
                    break;
                }

                if (line == "")
                {
                    lines++;
                    continue;
                }

                draw_line(gs, line.idup(), line_x, line_y, 10, rnvnd.sdl_rect);

                lines++;
            }

            //return;
        }
        catch(UTFException exc)
        {
            //return;
        }
    }
}

package void
draw_direntry_name(GlobalState gs, string name,
        in ref SDL_Rect_With_Not_Visible_And_No_Draw rnvnd,
        bool force=false)
{
    try{
        if (name > "" && (!rnvnd.no_draw || force))
        {
            int size = rnvnd.sdl_rect.w/16;
            int f = cast(int)(floor(log2(size)*2)+2);
            if (f < 5) return;
            if (f > 14) f = 14;

            //writefln("name=%s", name);
            /* EN: Render text
               RU: Рендерим текст */
            int line_height = cast(int)(round(SQRT2^^f)*1.2);
            auto tt = gs.text_viewer.font.get_line_from_cache(name, 
                    f, rnvnd.sdl_rect.w, line_height, SDL_Color(255, 255, 255, 255));
            if (!tt && !tt.texture)
            {
                throw new Exception("Can't create text_surface: "~
                        to!string(TTF_GetError()));
            }

            auto ttb = gs.text_viewer.font.get_line_from_cache(name, 
                    f, rnvnd.sdl_rect.w, line_height, SDL_Color(0, 0, 0, 255));
            if (!tt && !tt.texture)
            {
                throw new Exception("Can't create text_surface: "~
                        to!string(TTF_GetError()));
            }

            auto text_texture = tt.texture;
            auto text_texture_black = ttb.texture;

            /* EN: Rerender if it's too wide
               RU: Перерендериваем меньшим шрифтом, если
                    надпись слишком велика */
            /*
            while ( text_surface.w > rnvnd.sdl_rect.w && f > 6 )
            {
                f--;
                SDL_FreeSurface(text_surface);
                text_surface = TTF_RenderUTF8_Blended(
                        gs.text_viewer.font.font[0][f], name.toStringz(),
                        SDL_Color(255, 255, 255, 255));
                if (!text_surface)
                {
                    throw new Exception("Can't create text_surface: "~
                            to!string(TTF_GetError()));
                }
            }*/

            /* EN: calculate output coordinates
               RU: расчитывает выходные координаты */
            SDL_Rect sdl_rect;
            sdl_rect.x = cast(int)(rnvnd.sdl_rect.x +
                    (rnvnd.sdl_rect.w - tt.w)/2);
            sdl_rect.y = cast(int)(rnvnd.sdl_rect.y +
                    (rnvnd.sdl_rect.h - tt.h)/2);
            sdl_rect.w = tt.w+1;
            sdl_rect.h = tt.h+1;

            /* EN: Draw
               RU: Рисуем */
            auto r = SDL_RenderCopyEx(gs.renderer, text_texture_black, null, &sdl_rect, 0,
                        null, SDL_FLIP_NONE);
            if (r < 0)
            {
                writefln( "draw_direntry_name(): Error while render copy: %s", SDL_GetError().to!string() );
            }

            sdl_rect.x -= 1;
            sdl_rect.y -= 1;

            r = SDL_RenderCopyEx(gs.renderer, text_texture, null, &sdl_rect, 0,
                        null, SDL_FLIP_NONE);
            if (r < 0)
            {
                writefln( "draw_direntry_name(): Error while render copy: %s", SDL_GetError().to!string() );
            }


        }
    } catch (Exception e)
    {
    }
}

