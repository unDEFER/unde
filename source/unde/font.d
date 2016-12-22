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
}

struct LineSize
{
    string line;
    int size;
    int line_width;
    int line_height;
    SDL_Color color;
}

class Font
{
    SDL_Renderer *renderer;
    version(FreeType)
    {
        FT_Library  library;
        FT_Face[2] face;
    }
    TTF_Font *[16][2]font;

    long last_chars_cache_use;
    Texture_Tick[CharSize] chars_cache;
    long last_lines_cache_use;
    Texture_Tick[LineSize] lines_cache;
    
    auto
    get_char_from_cache(in string chr, in int size, in SDL_Color color)
    {
        auto charsize = CharSize(chr.idup(), size, color);
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
                auto glyph_index = FT_Get_Char_Index(face[0], to!dchar(chr), FT_LOAD_RENDER);//FT_Get_Char_Index( face[0], to!dchar(chr) );
            }
            else
            {
                int glyph_index;
                dchar dchr; wchar wchr;
                try
                {
                    dchr = to!dchar(chr);
                    wchr = to!wchar(dchr);
                    glyph_index = TTF_GlyphIsProvided(font[0][size], wchr);
                }
                catch (Exception e)
                {
                }
            }
            SDL_Surface *surface;
            if (glyph_index > 0)
            {
                surface = TTF_RenderUTF8_Blended(
                    font[0][size], chr.toStringz(),
                    color );
            }
            else
            {
                surface = TTF_RenderUTF8_Blended(
                    font[1][size], chr.toStringz(),
                    color );
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
            string chr = text[i..i+text.mystride(i)].idup();
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

    auto
    get_line_from_cache(string text, 
            int size, int line_width, int line_height, SDL_Color color)
    {
        auto linesize = LineSize(text.idup(), size, line_width, line_height, color);
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
            int lines = 1;

            long line_ax = 0;
            long line_ay = 0;

            SDL_Rect[] chars = [];

            ssize_t index;
            for (size_t i=0; i < text.length; i+=text.mystride(i))
            {
                string chr = text[i..i+text.mystride(i)];
                auto st = get_char_from_cache(chr, size, color);
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
                        lines++;
                        if (chr == "\n") continue;
                    }
                }
                /*writefln("%s - %s, %s, %s, %s",
                        line, dst.x, dst.y, dst.w, dst.h);*/

                dst.x = cast(int)line_ax;
                dst.y = cast(int)line_ay;
                dst.w = st.w;
                dst.h = st.h;

                r = SDL_RenderCopyEx(renderer, st.texture, null, &dst, 0,
                            null, SDL_FLIP_NONE);
                if (r < 0)
                {
                    writefln( "draw_line(): Error while render copy: %s", SDL_GetError().to!string() );
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

        // fonts with sizes 6, 8, 11, 16, 23, 32, 45, 64, 91, 128, 181
        foreach(i; 5..16)
        {
            version (linux)
            {
		version(Fedora)
		{
                font[0][i]=TTF_OpenFont(
                        "/usr/share/fonts/liberation/LiberationMono-Regular.ttf",
                        cast(int)round(SQRT2^^i));
		}
		else
		{
                font[0][i]=TTF_OpenFont(
                        "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
                        cast(int)round(SQRT2^^i));
		}
            }
            version (Windows)
            {
                font[0][i]=TTF_OpenFont(
                        "C:\\Windows\\Fonts\\cour.ttf",
                        cast(int)round(SQRT2^^i));
            }
            if(!font[0][i]) {
                throw new Exception(format("TTF_OpenFont: %s\n",
                        TTF_GetError().to!string()));
            }
        }

        version(FreeType)
        {
            err = FT_New_Face( library, toStringz("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf".dup), 0, &face[0] );
            if (err) 
            {
                throw new Exception(format("FT_Open_Face 1: %s\n",
                            err));
            }
        }

        foreach(i; 5..16)
        {
            version (linux)
            {
		version(Fedora)
		{
                font[1][i]=TTF_OpenFont(
                        "/usr/share/fonts/dejavu/DejaVuSans.ttf",
                        cast(int)round(SQRT2^^i));
		}
		else
		{
                font[1][i]=TTF_OpenFont(
                        "/usr/share/fonts/truetype/ancient-scripts/Symbola_hint.ttf",
                        cast(int)round(SQRT2^^i));
		}
            }
            version (Windows)
            {
		// Good fonts: MS GOTHIC, Segoe UI Emoji, Segoe UI Symbol
                font[1][i]=TTF_OpenFont(
                        "C:\\Windows\\Fonts\\seguisym.ttf",
                        cast(int)round(SQRT2^^i));
            }
            if(!font[1][i]) {
                throw new Exception(format("TTF_OpenFont: %s\n",
                        TTF_GetError().to!string()));
            }
        }

        version(FreeType)
        {
            err = FT_New_Face( library, toStringz("/usr/share/fonts/truetype/ancient-scripts/Symbola_hint.ttf".dup), 0, &face[0] );
            if (err) 
            {
                throw new Exception(format("FT_Open_Face 2: %s\n",
                            err));
            }
        }

    }

    ~this()
    {
        version(FreeType)
        {
            FT_Done_Face( face[0] );
            FT_Done_Face( face[1] );
        }

        foreach(i; 5..16)
        {
            TTF_CloseFont(font[0][i]);
        }

        foreach(i; 5..16)
        {
            TTF_CloseFont(font[1][i]);
        }

        TTF_Quit();
    }
}
