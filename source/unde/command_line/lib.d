module unde.command_line.lib;

import unde.global_state;
import unde.path_mnt;
import unde.lib;
import unde.slash;
import unde.font;

import berkeleydb.all;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;

import core.exception;

import std.string;
import std.stdio;
import std.math;
import std.conv;
import std.utf;

void
draw_command_line(GlobalState gs)
{
    if (!gs.command_line.enter) return;

    ulong y_off;

    string prompt = "$ ";
    int line_height = cast(int)(round(SQRT2^^9)*1.2);
    auto ptt = gs.text_viewer.font.get_line_from_cache(prompt, 
            9, gs.screen.w-80, line_height, SDL_Color(0x00,0xFF,0x00,0xFF));
    if (!ptt && !ptt.texture)
    {
        throw new Exception("Can't create text_surface: "~
                to!string(TTF_GetError()));
    }

    auto tt = gs.text_viewer.font.get_line_from_cache(gs.command_line.command, 
            9, gs.screen.w-80-ptt.w, line_height, SDL_Color(0xFF, 0xFF, 0xFF, 0xFF));
    if (!tt && !tt.texture)
    {
        throw new Exception("Can't create text_surface: "~
                to!string(TTF_GetError()));
    }

    auto lines = tt.h / line_height;
    y_off = gs.screen.h - line_height*3 - line_height*lines - 8;

    /* EN: render background of console messages
       RU: рендерим фон консоли сообщений */
    SDL_Rect rect;
    rect.x = 32;
    rect.y = cast(int)y_off;
    rect.w = gs.screen.w - 32*2;
    rect.h = cast(int)(line_height*lines + 8);

    int r = SDL_RenderCopy(gs.renderer, gs.texture_black, null, &rect);
    if (r < 0)
    {
        writefln( "draw_command_line(), 1: Error while render copy: %s",
                SDL_GetError().to!string() );
    }
    
    /* EN: Render prompt to screen
       RU: Рендерим приглашение на экран */
    auto i = 0;
    rect = SDL_Rect();
    rect.x = 40;
    rect.y = cast(int)(y_off + 4 + line_height*i);
    rect.w = ptt.w;
    rect.h = ptt.h;

    r = SDL_RenderCopy(gs.renderer, ptt.texture, null, &rect);
    if (r < 0)
    {
        writefln(
            "draw_command_line(), 2: Error while render copy: %s", 
            SDL_GetError().to!string() );
    }

    /* EN: Render text to screeb
       RU: Рендерим текст на экран */
    rect = SDL_Rect();
    rect.x = 40+ptt.w;
    rect.y = cast(int)(y_off + 4 + line_height*i);
    rect.w = tt.w;
    rect.h = tt.h;

    r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
    if (r < 0)
    {
        writefln(
            "draw_command_line(), 3: Error while render copy: %s", 
            SDL_GetError().to!string() );
    }

    with (gs.command_line)
    {
        rect = tt.chars[pos];
        rect.x += 40+ptt.w;
        rect.y += cast(int)(y_off + 4 + line_height*i);
        string chr = " ";
        if (pos < command.length)
            chr = command[pos..pos+command.stride(pos)];
        if (chr == "\n") chr = " ";

        r = SDL_RenderCopy(gs.renderer, gs.texture_cursor, null, &rect);
        if (r < 0)
        {
            writefln( "draw_command_line(), 4: Error while render copy: %s",
                    SDL_GetError().to!string() );
        }

        auto st = gs.text_viewer.font.get_char_from_cache(chr, 9, SDL_Color(0x00, 0x00, 0x20, 0xFF));
        if (!st) return;

        r = SDL_RenderCopy(gs.renderer, st.texture, null, &rect);
        if (r < 0)
        {
            writefln(
                "draw_command_line(), 5: Error while render copy: %s", 
                SDL_GetError().to!string() );
        }
    }
}

