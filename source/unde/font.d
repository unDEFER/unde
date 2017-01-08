module unde.font;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;
version(FreeType)
{
    import derelict.freetype.ft;
}

import unde.global_state;
import unde.lib;

import core.exception;
import core.memory;

import std.math;
import std.stdio;
import std.conv;
import std.string;

struct CharSize
{
    string chr;
    int size;
    SDL_Color color;
    size_t font;
}

struct LineSize
{
    string line;
    int size;
    int line_width;
    int line_height;
    SDL_Color color;
    ushort[] attrs;
    ssize_t start_pos;
    ssize_t end_pos;
}

enum Attr
{
    Black,
    Red,
    Green,
    Brown,
    Blue,
    Magenta,
    Cyan,
    White,
    Bold = 0x100,
    Underscore = 0x200,
    HalfBright = 0x400,
    Blink = 0x800,
    Color = 0x1000,
}

class Font
{
    SDL_Renderer *renderer;
    version(FreeType)
    {
        FT_Library  library;
        FT_Face[5] face;
    }
    TTF_Font *[16][5]font;
    SDL_Texture*[16] attr_textures;

    long last_chars_cache_use;
    Texture_Tick[CharSize] chars_cache;
    long last_lines_cache_use;
    Texture_Tick[LineSize] lines_cache;
    
    auto
    get_char_from_cache(in string chr, in int size, in SDL_Color color, size_t f = 0)
    {
        auto charsize = CharSize(chr.idup(), size, color, f);
        auto st = charsize in chars_cache;
        if (st)
        {
            st.tick = SDL_GetTicks();
            last_chars_cache_use = SDL_GetTicks();
        }
        else
        {
            version(FreeType)
            {
                auto glyph_index = FT_Get_Char_Index(face[f], to!dchar(chr), FT_LOAD_RENDER);//FT_Get_Char_Index( face[0], to!dchar(chr) );
            }
            else
            {
                int glyph_index;
                dchar dchr; wchar wchr;
                try
                {
                    dchr = to!dchar(chr);
                    wchr = to!wchar(dchr);
                    glyph_index = TTF_GlyphIsProvided(font[f][size], wchr);
                }
                catch (Exception e)
                {
                }
            }
            SDL_Surface *surface;
            if (glyph_index > 0)
            {
                if (size < 9)
                {
                    surface = TTF_RenderUTF8_Solid(
                            font[f][size], chr.toStringz(),
                            color );
                }
                else
                {
                    surface = TTF_RenderUTF8_Blended(
                            font[f][size], chr.toStringz(),
                            color );
                }
            }
            else
            {
                if (size < 9)
                {
                    surface = TTF_RenderUTF8_Solid(
                            font[4][size], chr.toStringz(),
                            color );
                }
                else
                {
                    surface = TTF_RenderUTF8_Blended(
                        font[4][size], chr.toStringz(),
                        color );
                }
            }

            auto texture =
                SDL_CreateTextureFromSurface(renderer, surface);

            if (surface)
            {
                chars_cache[charsize] = Texture_Tick(surface.w, surface.h, [], texture, SDL_GetTicks());
                SDL_FreeSurface(surface);
                last_chars_cache_use = SDL_GetTicks();
                st = charsize in chars_cache;
            }
        }

        return st;
    }

    /* EN: clear cache from old entries
       RU: очистить кеш от старых элементов */
    void
    clear_chars_cache()
    {
        int cleared = 0;
        foreach(k, v; chars_cache)
        {
            if (v.tick < last_chars_cache_use - 30_000)
            {
                cleared++;
                if (v.texture) SDL_DestroyTexture(v.texture);
                if ( !chars_cache.remove(k) )
                {
                    writefln("Can't remove chars cache key %s", k);
                }
                //writefln("v.tick = %s < %s. Remove key %s",
                //        v.tick, gs.last_pict_cache_use - 300_000, k);
            }
        }
        if (cleared) 
        {
            //writefln("Cleared %d objects from lines cache", cleared);
            GC.collect();
        }
    }

    public SDL_Rect
    get_size_of_line(inout (char)[] text,
            int size, long line_width, int line_height,
            SDL_Color color)
    {
        text ~= " ";
        if (text.length > 0 && text[$-1] == '\r') text = text[0..$-1];
        int lines = 1;

        int line_ax = 0;
        int line_ay = 0;

        SDL_Rect rect = SDL_Rect(0, 0, 1, 1);
        for (size_t i = 0; i < text.length; i += text.mystride(i))
        {
            auto chrlen = text.mystride(i);
            if (i+chrlen >= text.length) chrlen = 1;
            string chr = text[i..i+chrlen].idup();
            //writefln("chr = %s", chr);
            auto st = get_char_from_cache(chr, size, color);
            if (!st) continue;

            if (line_width > 0)
            {
                if (line_ax + st.w > line_width || chr == "\n")
                {
                    if (line_ax > rect.w) rect.w = line_ax;
                    line_ax = 0;
                    line_ay += line_height;
                    lines++;
                    if (chr == "\n") continue;
                }
            }

            line_ax += st.w;
        }

        if (line_ax > rect.w) rect.w = line_ax;
        rect.h = lines*line_height;
        return rect;
    }

    public SDL_Rect
    get_size_of_line(int cols, int rows,
            int size, SDL_Color color)
    {
        SDL_Rect rect = SDL_Rect(0, 0, 1, 1);
        auto st = get_char_from_cache(" ", size, color);
        if (!st) return rect;

        rect.w = cols*st.w;
        rect.h = rows*st.h;

        return rect;
    }

    auto
    get_line_from_cache(string text, 
            int size, int line_width, int line_height, SDL_Color color, 
            ushort[] attrs = null, ssize_t start_pos=-1, ssize_t end_pos=-1)
    {
        auto linesize = LineSize(text.idup(), size, line_width, line_height, 
                color, attrs.dup(), start_pos, end_pos);
        auto tt = linesize in lines_cache;
        if (tt)
        {
            tt.tick = SDL_GetTicks();
            last_lines_cache_use = SDL_GetTicks();
        }
        else
        {
            auto rect = get_size_of_line(text, size, line_width, line_height, color);

            if (rect.w > 8192) rect.w = 8192;
            if (rect.h > 8192) rect.h = 8192;
            auto texture = SDL_CreateTexture(renderer,
                    SDL_PIXELFORMAT_ARGB8888,
                    SDL_TEXTUREACCESS_TARGET,
                    rect.w,
                    rect.h);
            if( !texture )
            {
                throw new Exception(format("get_line_from_cache: Error while creating texture: %s",
                        SDL_GetError().to!string() ));
            }

            auto old_texture = SDL_GetRenderTarget(renderer);
            int r = SDL_SetRenderTarget(renderer, texture);
            if (r < 0)
            {
                throw new Exception(format("get_line_from_cache: Error while set render target texture: %s",
                        SDL_GetError().to!string() ));
            }

            SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);
            r = SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0);
            if (r < 0)
            {
                writefln("Can't SDL_SetRenderDrawColor: %s",
                        to!string(SDL_GetError()));
            }
            r = SDL_RenderClear(renderer);
            if (r < 0)
            {
                throw new Exception(format("Error while clear renderer: %s",
                        SDL_GetError().to!string() ));
            }

            text ~= " ";
            if (text.length > 0 && text[$-1] == '\r') text = text[0..$-1];

            long line_ax = 0;
            long line_ay = 0;

            SDL_Rect[] chars = [];

            ssize_t index;
            ssize_t attrs_i;
                //writefln("text=%s", text);
                //writefln("attrs=%s", attrs);
            for (size_t i=0; i < text.length; i+=text.mystride(i), attrs_i++)
            {
                auto chrlen = text.mystride(i);
                if (i+chrlen >= text.length) chrlen = 1;
                string chr = text[i..i+chrlen].idup();
                SDL_Color real_color = color;
                ushort attr = (Attr.Black<<4 | Attr.White);
                if ( attrs && attrs_i < attrs.length )
                    attr = attrs[attrs_i];
                else
                    attr = Attr.Black<<4 | Attr.White;
                if (i >= start_pos && i <= end_pos)
                    attr = attr & 0x0F | (Attr.Blue << 4);
                if ( attr != (Attr.Black<<4 | Attr.White) && !(attr & Attr.Color) )
                {
                    switch (attr & 0x0F)
                    {
                        case Attr.Black:
                            real_color = SDL_Color(0x00, 0x00, 0x00, 0xFF);
                            break;
                        case Attr.Red:
                            real_color = SDL_Color(0xFF, 0x00, 0x00, 0xFF);
                            break;
                        case Attr.Green:
                            real_color = SDL_Color(0x00, 0xFF, 0x00, 0xFF);
                            break;
                        case Attr.Brown:
                            real_color = SDL_Color(0xFF, 0xFF, 0x30, 0xFF);
                            break;
                        case Attr.Blue:
                            real_color = SDL_Color(0x00, 0x00, 0xFF, 0xFF);
                            break;
                        case Attr.Magenta:
                            real_color = SDL_Color(0xFF, 0x00, 0xFF, 0xFF);
                            break;
                        case Attr.Cyan:
                            real_color = SDL_Color(0x00, 0xFF, 0xFF, 0xFF);
                            break;
                        case Attr.White:
                            real_color = SDL_Color(0xFF, 0xFF, 0xFF, 0xFF);
                            break;
                        default:
                            break;
                    }
                }
                auto st = get_char_from_cache(chr, size, real_color, (attr&Attr.Bold?1:0));
                if (!st) continue;

                SDL_Rect dst;
                dst.x = cast(int)line_ax;
                dst.y = cast(int)line_ay;
                dst.w = st.w;
                dst.h = st.h;

                chars.length = i+1;
                chars[i] = dst;

                if (line_width > 0)
                {
                    if (line_ax + st.w > line_width || chr == "\n")
                    {
                        line_ax = 0;
                        line_ay += line_height;
                        if (chr == "\n") continue;
                    }
                }
                /*writefln("%s - %s, %s, %s, %s",
                        line, dst.x, dst.y, dst.w, dst.h);*/

                dst.x = cast(int)line_ax;
                dst.y = cast(int)line_ay;
                dst.w = st.w;
                dst.h = st.h;

                if ( ((attr & 0xF0)>>4) != Attr.Black )
                {
                    r = SDL_RenderCopyEx(renderer, attr_textures[(attr & 0xF0)>>4], null, &dst, 0,
                                null, SDL_FLIP_NONE);
                    if (r < 0)
                    {
                        writefln( "draw_line(): Error while render copy: %s", SDL_GetError().to!string() );
                    }
                }

                r = SDL_RenderCopyEx(renderer, st.texture, null, &dst, 0,
                            null, SDL_FLIP_NONE);
                if (r < 0)
                {
                    writefln( "draw_line(): Error while render copy: %s", SDL_GetError().to!string() );
                }

                if (attr & Attr.Underscore)
                {
                    dst.y += dst.h - 2;
                    dst.h = 1;

                    r = SDL_RenderCopyEx(renderer, attr_textures[attr & 0xF], null, &dst, 0,
                                null, SDL_FLIP_NONE);
                    if (r < 0)
                    {
                        writefln( "draw_line(): Error while render copy: %s", SDL_GetError().to!string() );
                    }
                }

                line_ax += st.w;
            }

            r = SDL_SetRenderTarget(renderer, old_texture);
            if (r < 0)
            {
                throw new Exception(format("get_line_from_cache: Error while restore render target old_texture: %s",
                        SDL_GetError().to!string() ));
            }

            lines_cache[linesize] = Texture_Tick(rect.w, rect.h, chars, texture, SDL_GetTicks());
            last_lines_cache_use = SDL_GetTicks();
            tt = linesize in lines_cache;
        }

        return tt;
    }

    auto
    get_line_from_cache(dchar[] text, int cols, int rows,
            int size, int line_height, SDL_Color color, ushort[] attrs = null,
            ssize_t start_pos=-1, ssize_t end_pos=-1)
    {
        auto linesize = LineSize(to!(string)(text.idup()), size, cols*rows, 
                line_height, color, attrs.dup(), start_pos, end_pos);
        auto tt = linesize in lines_cache;
        if (tt)
        {
            tt.tick = SDL_GetTicks();
            last_lines_cache_use = SDL_GetTicks();
        }
        else
        {
            auto rect = get_size_of_line(cols, rows, size, color);

            if (rect.w > 8192) rect.w = 8192;
            if (rect.h > 8192) rect.h = 8192;
            auto texture = SDL_CreateTexture(renderer,
                    SDL_PIXELFORMAT_ARGB8888,
                    SDL_TEXTUREACCESS_TARGET,
                    rect.w,
                    rect.h);
            if( !texture )
            {
                throw new Exception(format("get_line_from_cache: Error while creating texture: %s",
                        SDL_GetError().to!string() ));
            }

            auto old_texture = SDL_GetRenderTarget(renderer);
            int r = SDL_SetRenderTarget(renderer, texture);
            if (r < 0)
            {
                throw new Exception(format("get_line_from_cache: Error while set render target texture: %s",
                        SDL_GetError().to!string() ));
            }

            SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);
            r = SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0);
            if (r < 0)
            {
                writefln("Can't SDL_SetRenderDrawColor: %s",
                        to!string(SDL_GetError()));
            }
            r = SDL_RenderClear(renderer);
            if (r < 0)
            {
                throw new Exception(format("Error while clear renderer: %s",
                        SDL_GetError().to!string() ));
            }

            long line_ax = 0;
            long line_ay = 0;

            SDL_Rect[] chars = [];
            chars.length = text.length;

            ssize_t index;
                //writefln("text=%s", text);
                //writefln("attrs=%s", attrs);
            for (size_t i=0; i < text.length; i++)
            {
                string chr = to!string(text[i]);
                SDL_Color real_color = color;
                ushort attr = (Attr.Black<<4 | Attr.White);
                if ( attrs )
                    attr = attrs[i];
                else attr = Attr.Black<<4 | Attr.White;
                if (i >= start_pos && i <= end_pos)
                    attr = attr & 0x0F | (Attr.Blue << 4);
                if ( attr != (Attr.Black<<4 | Attr.White) && !(attr & Attr.Color) )
                {
                    switch (attr & 0x0F)
                    {
                        case Attr.Black:
                            real_color = SDL_Color(0x00, 0x00, 0x00, 0xFF);
                            break;
                        case Attr.Red:
                            real_color = SDL_Color(0xFF, 0x00, 0x00, 0xFF);
                            break;
                        case Attr.Green:
                            real_color = SDL_Color(0x00, 0xFF, 0x00, 0xFF);
                            break;
                        case Attr.Brown:
                            real_color = SDL_Color(0xFF, 0xFF, 0x30, 0xFF);
                            break;
                        case Attr.Blue:
                            real_color = SDL_Color(0x80, 0x80, 0xFF, 0xFF);
                            break;
                        case Attr.Magenta:
                            real_color = SDL_Color(0xFF, 0x00, 0xFF, 0xFF);
                            break;
                        case Attr.Cyan:
                            real_color = SDL_Color(0x00, 0xFF, 0xFF, 0xFF);
                            break;
                        case Attr.White:
                            real_color = SDL_Color(0xFF, 0xFF, 0xFF, 0xFF);
                            break;
                        default:
                            break;
                    }
                }
                auto st = get_char_from_cache(chr, size, real_color, (attr&Attr.Bold?1:0));
                if (!st) continue;

                if (i > 0 && i%cols == 0)
                {
                    line_ax = 0;
                    line_ay += line_height;
                }

                SDL_Rect dst;
                dst.x = cast(int)line_ax;
                dst.y = cast(int)line_ay;
                dst.w = st.w;
                dst.h = st.h;

                chars[i] = dst;

                if ( ((attr & 0xF0)>>4) != Attr.Black )
                {
                    r = SDL_RenderCopyEx(renderer, attr_textures[(attr & 0xF0)>>4], null, &dst, 0,
                                null, SDL_FLIP_NONE);
                    if (r < 0)
                    {
                        writefln( "draw_line(): Error while render copy: %s", SDL_GetError().to!string() );
                    }
                }

                r = SDL_RenderCopyEx(renderer, st.texture, null, &dst, 0,
                            null, SDL_FLIP_NONE);
                if (r < 0)
                {
                    writefln( "draw_line(): Error while render copy: %s", SDL_GetError().to!string() );
                }

                if ( attr & Attr.Underscore )
                {
                    dst.y += dst.h - 4;
                    dst.h = 1;

                    r = SDL_RenderCopyEx(renderer, attr_textures[attr & 0xF], null, &dst, 0,
                                null, SDL_FLIP_NONE);
                    if (r < 0)
                    {
                        writefln( "draw_line(): Error while render copy: %s", SDL_GetError().to!string() );
                    }
                }

                line_ax += st.w;
            }

            r = SDL_SetRenderTarget(renderer, old_texture);
            if (r < 0)
            {
                throw new Exception(format("get_line_from_cache: Error while restore render target old_texture: %s",
                        SDL_GetError().to!string() ));
            }

            lines_cache[linesize] = Texture_Tick(rect.w, rect.h, chars, texture, SDL_GetTicks());
            last_lines_cache_use = SDL_GetTicks();
            tt = linesize in lines_cache;
        }

        return tt;
    }

    /* EN: clear cache from old entries
       RU: очистить кеш от старых элементов */
    void
    clear_lines_cache()
    {
        int cleared;
        foreach(k, v; lines_cache)
        {
            if (v.tick < last_lines_cache_use - 30_000)
            {
                cleared++;
                if (v.texture) SDL_DestroyTexture(v.texture);
                if (!lines_cache.remove(k))
                {
                    writefln("NOT DELETED key %s", k.line);
                    writefln("k in lines_cache %s", k in lines_cache);
                }
                //writefln("v.tick = %s < %s. Remove key %s",
                //        v.tick, last_lines_cache_use - 30_000, k);
            }
        }
        if (cleared) 
        {
            //writefln("Cleared %d objects from lines cache", cleared);
            GC.collect();
        }
    }

    this(SDL_Renderer *renderer)
    {
        this.renderer = renderer;

        version(FreeType)
        {
            DerelictFT.load();
            auto err = FT_Init_FreeType(&library);
            if (err != 0)
            {
                throw new Exception(format("FT_Init_FreeType: %s\n",
                            err));
            }
        }

        DerelictSDL2ttf.load();

        if(TTF_Init()==-1) {
            throw new Exception(format("TTF_Init: %s\n",
                        TTF_GetError().to!string()));
        }

        version (linux)
        {
            version(Fedora)
            {
                string[] font_list = ["/usr/share/fonts/liberation/LiberationMono-Regular.ttf",
                    "/usr/share/fonts/liberation/LiberationMono-Bold.ttf",
                    "/usr/share/fonts/liberation/LiberationMono-Italic.ttf",
                    "/usr/share/fonts/liberation/LiberationMono-BoldItalic.ttf",
                    "/usr/share/fonts/dejavu/DejaVuSans.ttf"];
            }
            else
            {
                string[] font_list = ["/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
                    "/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf",
                    "/usr/share/fonts/truetype/liberation/LiberationMono-Italic.ttf",
                    "/usr/share/fonts/truetype/liberation/LiberationMono-BoldItalic.ttf",
                    "/usr/share/fonts/truetype/ancient-scripts/Symbola_hint.ttf"];
            }
        }
        else version (Windows)
        {
            string[] font_list = ["C:\\Windows\\Fonts\\cour.ttf",
                "C:\\Windows\\Fonts\\cour.ttf",
                "C:\\Windows\\Fonts\\cour.ttf",
                "C:\\Windows\\Fonts\\cour.ttf",
		// Good fonts: MS GOTHIC, Segoe UI Emoji, Segoe UI Symbol
                "C:\\Windows\\Fonts\\seguisym.ttf"];
        }

        // fonts with sizes 6, 8, 11, 16, 23, 32, 45, 64, 91, 128, 181
        foreach(f, fontname; font_list)
        {
            foreach(i; 5..16)
            {
                font[f][i]=TTF_OpenFont(
                        fontname.toStringz(),
                        cast(int)round(SQRT2^^i));
                if(!font[f][i]) {
                    throw new Exception(format("TTF_OpenFont: %s\n",
                            TTF_GetError().to!string()));
                }
            }

            version(FreeType)
            {
                err = FT_New_Face( library, toStringz(fontname.dup), 0, &face[f] );
                if (err) 
                {
                    throw new Exception(format("FT_Open_Face 1: %s\n",
                                err));
                }
            }
        }

        SDL_Surface* surface = SDL_CreateRGBSurface(0,
                1,
                1,
                32, 0x00FF0000, 0X0000FF00, 0X000000FF, 0XFF000000);

        for (auto c = 0; c < 16; c++)
        {
            SDL_Color back_color;
            switch (c)
            {
                case Attr.Black:
                    back_color = SDL_Color(0x00, 0x00, 0x00, 0xFF);
                    break;
                case Attr.Red:
                    back_color = SDL_Color(0xFF, 0x00, 0x00, 0xFF);
                    break;
                case Attr.Green:
                    back_color = SDL_Color(0x00, 0xFF, 0x00, 0xFF);
                    break;
                case Attr.Brown:
                    back_color = SDL_Color(0x80, 0x80, 0x00, 0xFF);
                    break;
                case Attr.Blue:
                    back_color = SDL_Color(0x00, 0x00, 0xFF, 0xFF);
                    break;
                case Attr.Magenta:
                    back_color = SDL_Color(0xFF, 0x00, 0xFF, 0xFF);
                    break;
                case Attr.Cyan:
                    back_color = SDL_Color(0x00, 0x80, 0x80, 0xFF);
                    break;
                case Attr.White:
                    back_color = SDL_Color(0x80, 0x80, 0x80, 0xFF);
                    break;
                case 8+Attr.Black:
                    back_color = SDL_Color(0x00, 0x00, 0x00, 0xFF);
                    break;
                case 8+Attr.Red:
                    back_color = SDL_Color(0xFF, 0x00, 0x00, 0xFF);
                    break;
                case 8+Attr.Green:
                    back_color = SDL_Color(0x00, 0xFF, 0x00, 0xFF);
                    break;
                case 8+Attr.Brown:
                    back_color = SDL_Color(0x80, 0x80, 0x00, 0xFF);
                    break;
                case 8+Attr.Blue:
                    back_color = SDL_Color(0x00, 0x00, 0xFF, 0xFF);
                    break;
                case 8+Attr.Magenta:
                    back_color = SDL_Color(0xFF, 0x00, 0xFF, 0xFF);
                    break;
                case 8+Attr.Cyan:
                    back_color = SDL_Color(0x00, 0xFF, 0xFF, 0xFF);
                    break;
                case 8+Attr.White:
                    back_color = SDL_Color(0xFF, 0xFF, 0xFF, 0xFF);
                    break;
                default:
                    break;
            }

            (cast(uint*) surface.pixels)[0] = (back_color.a<<24) | 
                (back_color.r << 16) | (back_color.g << 8) | back_color.b;

            attr_textures[c] =
                SDL_CreateTextureFromSurface(renderer, surface);
        }

        SDL_FreeSurface(surface);
    }

    ~this()
    {
        version(FreeType)
        {
            foreach(f; 0..5)
            {
                FT_Done_Face( face[f] );
            }
        }

        foreach(f; 0..5)
        {
            foreach(i; 5..16)
            {
                TTF_CloseFont(font[f][i]);
            }
        }

        for (auto c = Attr.Black; c <= Attr.White; c++)
        {
            SDL_DestroyTexture(attr_textures[c]);
        }

        TTF_Quit();
    }
}
