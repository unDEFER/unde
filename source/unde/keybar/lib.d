module unde.keybar.lib;

import berkeleydb.all;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;
import derelict.sdl2.image;

import unde.global_state;
import unde.font;
import unde.viewers.image_viewer.lib;
import unde.command_line.lib;
import unde.slash;

import std.stdio;
import std.string;
import std.math;
import std.range.primitives;
import std.file;
import std.algorithm.sorting;
import std.process;
import core.stdc.locale;
import core.sys.windows.windows;

struct KeyHandler
{
    void delegate (GlobalState gs) handler;
    string description;
    string icon;
}

struct ButtonParms
{
    SDL_Rect rect;
    SDL_Color color;
}

struct Layout
{
    string short_name;
    string name;

    string[][3] letters;
    string[][3] letters_shift;
    string[][3] letters_altgr;
    string[][3] letters_shift_altgr;
}

enum LayoutChanger
{
    Ctrl_Shift = Modifiers.Left_Ctrl | Modifiers.Left_Shift,
    LeftAlt = Modifiers.Left_Alt,
    RightAlt = Modifiers.Right_Alt,
    CapsLock = Modifiers.CapsLock,
    Shift_CapsLock = Modifiers.Left_Shift | Modifiers.CapsLock,
    Alt_CapsLock = Modifiers.Left_Alt | Modifiers.CapsLock,
    Both_Shift = Modifiers.Left_Shift | Modifiers.Right_Shift,
    Both_Alt = Modifiers.Left_Alt | Modifiers.Right_Alt,
    Both_Ctrl = Modifiers.Left_Ctrl | Modifiers.Right_Ctrl,
    RightCtrl_RightShift = Modifiers.Right_Ctrl | Modifiers.Right_Shift,
    Alt_Ctrl = Modifiers.Left_Alt | Modifiers.Left_Ctrl,
    Alt_Shift = Modifiers.Left_Alt | Modifiers.Left_Shift,
    Alt_Space = Modifiers.Left_Alt | Modifiers.Space,
    Menu = Modifiers.Menu,
    LeftWin = Modifiers.Left_Win,
    Win_Space = Modifiers.Left_Win | Modifiers.Space,
    RightWin = Modifiers.Right_Win,
    LeftShift = Modifiers.Left_Shift,
    RightShift = Modifiers.Right_Shift,
    LeftCtrl = Modifiers.Left_Ctrl,
    RightCtrl = Modifiers.Right_Ctrl,
    ScrollLock = Modifiers.ScrollLock
}

struct ButtonPos
{
    ushort i;
    ushort pos;
}

class KeyBar_Buttons
{
    private
    SDL_Renderer *renderer;

    bool input_mode;

    string[] layout_names;
    Layout[string] layouts;
    Layout*[] layout_modes;
    ssize_t mode;
    LayoutChanger changer;
    long last_change;
    long last_shift;

    string[][3] *letters;

    KeyHandler[int] handlers;
    KeyHandler[int] handlers_down;
    KeyHandler[int] handlers_double;
    SDL_Scancode[][3] *scans_cur;
    SDL_Scancode[][3] scans;
    SDL_Scancode[][3] scans_altgr;
    ButtonPos[SDL_Scancode] buttonpos_by_scan;
    ButtonPos[SDL_Scancode] buttonpos_by_scan_altgr;

    string[] layout_changer_names;
    LayoutChanger[] layout_changer_values;

    bool keybar_settings_needed;

    SDL_Rect[] buttons;
    ssize_t pos;
    this(GlobalState gs, SDL_Renderer *renderer, string start_cwd)
    {
        this.renderer = renderer;
        buttons = 
            [SDL_Rect(0,0,32,32), SDL_Rect(32,0,32,32), SDL_Rect(64,0,32,32), SDL_Rect(96,0,32,32), SDL_Rect(128,0,32,32), SDL_Rect(160,0,32,32), 
             SDL_Rect(0,32,40,32), SDL_Rect(40,32,32,32), SDL_Rect(72,32,32,32), SDL_Rect(104,32,32,32), SDL_Rect(136,32,32,32), SDL_Rect(168,32,24,32),
             SDL_Rect(0,64,48,32), SDL_Rect(48,64,32,32), SDL_Rect(80,64,32,32), SDL_Rect(112,64,32,32), SDL_Rect(144,64,32,32), SDL_Rect(176,64,16,32),
             SDL_Rect(0,96,32,32), SDL_Rect(32,96,32,32), SDL_Rect(64,96,32,32), SDL_Rect(96,96,32,32), SDL_Rect(128,96,32,32), SDL_Rect(160,96,32,32),
             SDL_Rect(0,128,48,16), SDL_Rect(48,128,32,16), SDL_Rect(80,128,32,16), SDL_Rect(112,128,32,16), SDL_Rect(144,128,48,16)];

        scans[0] = [SDL_SCANCODE_1, SDL_SCANCODE_2, SDL_SCANCODE_3, SDL_SCANCODE_4, SDL_SCANCODE_5, SDL_SCANCODE_6, 
            SDL_SCANCODE_Q, SDL_SCANCODE_W, SDL_SCANCODE_E, SDL_SCANCODE_R, SDL_SCANCODE_T, SDL_SCANCODE_Y, 
            SDL_SCANCODE_A, SDL_SCANCODE_S, SDL_SCANCODE_D, SDL_SCANCODE_F, SDL_SCANCODE_G, SDL_SCANCODE_H, 
            SDL_SCANCODE_LSHIFT, SDL_SCANCODE_Z, SDL_SCANCODE_X, SDL_SCANCODE_C, SDL_SCANCODE_V, SDL_SCANCODE_B, 
            SDL_SCANCODE_LCTRL, SDL_SCANCODE_LALT, SDL_SCANCODE_LGUI, SDL_SCANCODE_MENU, SDL_SCANCODE_SPACE
        ];

        scans[1] = [SDL_SCANCODE_EQUALS, SDL_SCANCODE_MINUS, SDL_SCANCODE_0, SDL_SCANCODE_9, SDL_SCANCODE_8, SDL_SCANCODE_7, 
            SDL_SCANCODE_RIGHTBRACKET, SDL_SCANCODE_LEFTBRACKET, SDL_SCANCODE_P, SDL_SCANCODE_O, SDL_SCANCODE_I, SDL_SCANCODE_U, 
            SDL_SCANCODE_APOSTROPHE, SDL_SCANCODE_SEMICOLON, SDL_SCANCODE_L, SDL_SCANCODE_K, SDL_SCANCODE_J, 0, 
            SDL_SCANCODE_RSHIFT, SDL_SCANCODE_SLASH, SDL_SCANCODE_PERIOD, SDL_SCANCODE_COMMA, SDL_SCANCODE_M, SDL_SCANCODE_N, 
            SDL_SCANCODE_RCTRL, SDL_SCANCODE_RALT, SDL_SCANCODE_RGUI, 0, 0
        ];

        scans[2] = [SDL_SCANCODE_ESCAPE, SDL_SCANCODE_BACKSPACE, SDL_SCANCODE_KP_ENTER, SDL_SCANCODE_INSERT, SDL_SCANCODE_HOME, SDL_SCANCODE_PAGEUP, 
            SDL_SCANCODE_GRAVE, SDL_SCANCODE_BACKSLASH, SDL_SCANCODE_UP, SDL_SCANCODE_DELETE, SDL_SCANCODE_END, SDL_SCANCODE_PAGEDOWN, 
            SDL_SCANCODE_TAB, SDL_SCANCODE_LEFT, SDL_SCANCODE_DOWN, SDL_SCANCODE_RIGHT, SDL_SCANCODE_KP_MINUS, SDL_SCANCODE_KP_PLUS, 
            SDL_SCANCODE_NUMLOCKCLEAR, SDL_SCANCODE_KP_DIVIDE, SDL_SCANCODE_KP_MULTIPLY, SDL_SCANCODE_PRINTSCREEN, SDL_SCANCODE_SCROLLLOCK, SDL_SCANCODE_PAUSE, 
            0, 0, 0, 0, SDL_SCANCODE_RETURN
        ];

        scans_altgr[0] = [SDL_SCANCODE_1, SDL_SCANCODE_2, SDL_SCANCODE_3, SDL_SCANCODE_4, SDL_SCANCODE_5, SDL_SCANCODE_6, 
            SDL_SCANCODE_Q, SDL_SCANCODE_W, SDL_SCANCODE_E, SDL_SCANCODE_R, SDL_SCANCODE_T, SDL_SCANCODE_Y, 
            SDL_SCANCODE_A, SDL_SCANCODE_S, SDL_SCANCODE_D, SDL_SCANCODE_F, SDL_SCANCODE_G, SDL_SCANCODE_H, 
            SDL_SCANCODE_LSHIFT, SDL_SCANCODE_Z, SDL_SCANCODE_X, SDL_SCANCODE_C, SDL_SCANCODE_V, SDL_SCANCODE_B, 
            SDL_SCANCODE_LCTRL, SDL_SCANCODE_LALT, SDL_SCANCODE_LGUI, SDL_SCANCODE_MENU, SDL_SCANCODE_SPACE
        ];

        scans_altgr[1] = [SDL_SCANCODE_EQUALS, SDL_SCANCODE_MINUS, SDL_SCANCODE_0, SDL_SCANCODE_9, SDL_SCANCODE_8, SDL_SCANCODE_7, 
            SDL_SCANCODE_RIGHTBRACKET, SDL_SCANCODE_LEFTBRACKET, SDL_SCANCODE_P, SDL_SCANCODE_O, SDL_SCANCODE_I, SDL_SCANCODE_U, 
            SDL_SCANCODE_APOSTROPHE, SDL_SCANCODE_SEMICOLON, SDL_SCANCODE_L, SDL_SCANCODE_K, SDL_SCANCODE_J, SDL_SCANCODE_H, 
            SDL_SCANCODE_RSHIFT, SDL_SCANCODE_SLASH, SDL_SCANCODE_PERIOD, SDL_SCANCODE_COMMA, SDL_SCANCODE_M, SDL_SCANCODE_N, 
            SDL_SCANCODE_RCTRL, SDL_SCANCODE_RALT, SDL_SCANCODE_RGUI, 0, 0
        ];

        scans_altgr[2] = [SDL_SCANCODE_KP_1, SDL_SCANCODE_KP_2, SDL_SCANCODE_KP_3, SDL_SCANCODE_KP_4, SDL_SCANCODE_KP_5, SDL_SCANCODE_KP_6, 
            SDL_SCANCODE_GRAVE, SDL_SCANCODE_BACKSLASH, SDL_SCANCODE_KP_7, SDL_SCANCODE_KP_8, SDL_SCANCODE_KP_9, SDL_SCANCODE_KP_0, 
            SDL_SCANCODE_F1, SDL_SCANCODE_F2, SDL_SCANCODE_F3, SDL_SCANCODE_F4, SDL_SCANCODE_F5, SDL_SCANCODE_F6, 
            SDL_SCANCODE_F7, SDL_SCANCODE_F8, SDL_SCANCODE_F9, SDL_SCANCODE_F10, SDL_SCANCODE_F11, SDL_SCANCODE_F12, 
            0, 0, 0, 0, SDL_SCANCODE_KP_PERIOD
        ];

        for (ssize_t i=0; i < 3; i++)
        {
            for (ssize_t pos=0; pos < scans[i].length; pos++)
            {
                if (scans[i][pos] > 0)
                    buttonpos_by_scan[scans[i][pos]] = ButtonPos(cast(ushort) i, cast(ushort) pos);
                if (scans_altgr[i][pos] > 0)
                    buttonpos_by_scan_altgr[scans_altgr[i][pos]] = ButtonPos(cast(ushort) i, cast(ushort) pos);
            }
        }

        layout_changer_names = ["Ctrl + Shift", "Left Alt", "Right Alt",
            "Caps Lock", "Left Shift + Caps Lock", "Left Alt + Caps Lock",
            "Both Shift", "Both Alt", "Both Ctrl", "Right Ctrl + Right Shift",
            "Left Alt + Left Ctrl", "Left Alt + Left Shift", "Left Alt + Space",
            "Menu", "Left Win", "Left Win + Space", "Right Win",
            "Left Shift", "Right Shift", "Left Ctrl", "Right Ctrl",
            "Scroll Lock"];

        with (LayoutChanger)
        {
            layout_changer_values = [ Ctrl_Shift, LeftAlt, RightAlt, 
                CapsLock, Shift_CapsLock, Alt_CapsLock,
                Both_Shift, Both_Alt, Both_Ctrl, RightCtrl_RightShift,
                Alt_Ctrl, Alt_Shift, Alt_Space,
                Menu, LeftWin, Win_Space, RightWin,
                LeftShift, RightShift, LeftCtrl, RightCtrl,
                ScrollLock];
        }

        assert(layout_changer_names.length == layout_changer_values.length);

        read_layouts(gs, start_cwd);
        SDL_StopTextInput();
    }

    long last_buttons_cache_use;
    Texture_Tick[ButtonParms] button_cache;

    auto
    get_button_from_cache(SDL_Rect rect, SDL_Color color)
    {
        auto butparm = ButtonParms(rect, color);
        auto tt = butparm in button_cache;
        if (tt)
        {
            tt.tick = SDL_GetTicks();
            last_buttons_cache_use = SDL_GetTicks();
        }
        else
        {
            SDL_Surface* surface = SDL_CreateRGBSurface(0,
                    rect.w,
                    rect.h,
                    32, 0x00ff0000, 0x0000ff00, 0x000000ff, 0xff000000);

            SDL_Rect dst = SDL_Rect(0,0,rect.w,rect.h);
            SDL_FillRect(surface, &dst, 0xff000000);

            dst.x += 1;
            dst.y += 1;
            dst.w -= 2;
            dst.h -= 2;

            SDL_FillRect(surface, &dst,
                    (color.a<<24) | (color.r<<16) | 
                    (color.g<<8)  | color.b);

            auto texture =
                SDL_CreateTextureFromSurface(renderer, surface);

            button_cache[butparm] = Texture_Tick(rect.w, rect.h, [], texture, SDL_GetTicks());
            last_buttons_cache_use = SDL_GetTicks();
            tt = butparm in button_cache;
        }

        return tt;
    }

    void
    read_layouts(GlobalState gs, string start_cwd)
    {
        string layouts_dir = start_cwd~SL~"layouts"~SL;
        if (!exists(layouts_dir))
        {
            layouts_dir = "/usr/share/unde/layouts/";
            if (!exists(layouts_dir))
            {
                new Exception("Not found .layouts or /usr/share/unde/layouts/");
            }
        }

        foreach(filename; dirEntries(layouts_dir, SpanMode.breadth))
        {
            if (filename.isDir) continue;

            File file = File(filename);

            Layout layout;
            ssize_t sl2 = filename.lastIndexOf(SL);
            ssize_t sl1 = filename[0..sl2].lastIndexOf(SL);
            layout.short_name = filename[sl1+1..sl2]~"("~filename[sl2+1..$]~")";
            string[][3] *letters;
            ssize_t i = 0;

            foreach(line; file.byLine())
            {
                if (line.startsWith("Name="))
                    layout.name = line[5..$].idup();
                if (line == "Letters:")
                {
                    i = 0;
                    letters = &layout.letters;
                }
                if (line == "Letters_Shift:")
                {
                    i = 0;
                    letters = &layout.letters_shift;
                }
                if (line == "Letters_Altgr:")
                {
                    i = 0;
                    letters = &layout.letters_altgr;
                }
                if (line == "Letters_Shift_Altgr:")
                {
                    i = 0;
                    letters = &layout.letters_shift_altgr;
                }
                if (line == "[]")
                    i++;
                if (line[0] == '[' && line [$-1] == ']')
                {
                    string chr;
                    bool backslash;
                    int state = 0;
                    line = line[1..$-1];
                    foreach (c; line)
                    {
                        if (state == 0)
                        {
                            if (c == '\"')
                            {
                                state = 1;
                                chr = "";
                            }
                        }
                        else if (state == 1)
                        {
                            if (c == '\\' && !backslash)
                            {
                                backslash = true;
                            }
                            else if (c == '\"' && !backslash)
                            {
                                (*letters)[i] ~= chr;
                                state = 0;
                            }
                            else
                            {
                                chr ~= c;
                                backslash = false;
                            }
                        }
                    }
                    i++;
                }
            }

            layout_names ~= layout.name ~ " - " ~ layout.short_name;
            layouts[layout.short_name] = layout;
        }

        sort!("a < b")(layout_names);
        load_keybar_settings(gs, this);
    }
}

void update_letters(GlobalState gs)
{
    if (gs.keybar.input_mode)
    {
        if (gs.alt_gr && gs.shift)
            gs.keybar.letters = &gs.keybar.layout_modes[gs.keybar.mode].letters_shift_altgr;
        else if (gs.alt_gr)
            gs.keybar.letters = &gs.keybar.layout_modes[gs.keybar.mode].letters_altgr;
        else if (gs.shift)
            gs.keybar.letters = &gs.keybar.layout_modes[gs.keybar.mode].letters_shift;
        else
            gs.keybar.letters = &gs.keybar.layout_modes[gs.keybar.mode].letters;
    }
    else
    {
        if (gs.alt_gr && gs.shift)
            gs.keybar.letters = &gs.keybar.layouts["us(basic)"].letters_shift_altgr;
        else if (gs.alt_gr)
            gs.keybar.letters = &gs.keybar.layouts["us(basic)"].letters_altgr;
        else if (gs.shift)
            gs.keybar.letters = &gs.keybar.layouts["us(basic)"].letters_shift;
        else
            gs.keybar.letters = &gs.keybar.layouts["us(basic)"].letters;
    }
}

void
draw_keybar(GlobalState gs)
{
    ushort[] attrs;
    for (ssize_t z=0; z<16; z++)
        attrs ~= Attr.Bold | Attr.Color;

    SDL_Rect full_rect;
    full_rect.x = gs.screen.w;
    full_rect.y = gs.screen.h - 32*4-16;
    full_rect.w = 32*6;
    full_rect.h = 32*4+16;

    if (gs.mouse_screen_x > full_rect.x &&
            gs.mouse_screen_x < full_rect.x + full_rect.w &&
            gs.mouse_screen_y > full_rect.y &&
            gs.mouse_screen_y < full_rect.y + full_rect.h)
    {
        gs.keybar.pos = get_position_by_chars(
                gs.mouse_screen_x - full_rect.x,
                gs.mouse_screen_y - full_rect.y, gs.keybar.buttons);
    }
    else gs.keybar.pos = -1;

    foreach(i, but; gs.keybar.buttons)
    {
        SDL_Color color = SDL_Color(0xFF, 0xFF, 0xFF, 0xFF);
        if (gs.keybar.pos == i)
        {
            color = SDL_Color(0x80, 0xFF, 0xFF, 0xFF);
        }
        auto tt = gs.keybar.get_button_from_cache(but, color);
        if (!tt && !tt.texture)
        {
            throw new Exception("can't create text_surface: "~
                    SDL_GetError().fromStringz().idup());
        }

        SDL_Rect rect;
        rect.x = but.x + gs.screen.w;
        rect.y = but.y + gs.screen.h - 32*4-16;
        rect.w = but.w;
        rect.h = but.h;

        int r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
        if (r < 0)
        {
            writefln(
                    "draw_keybar(): error while render copy: %s", 
                    SDL_GetError().fromStringz() );
        }

        int[3] x = [2, 18, 2];
        int[3] y = [0, 7, 22];
        int[3] xp = [0, 16, 0];
        int[3] yp = [0, 8, 16];
        SDL_Color[3] bright = [SDL_Color(0x00, 0x00, 0x00, 0xFF),
            SDL_Color(0xFF, 0x00, 0x00, 0xFF),
            SDL_Color(0x80, 0x80, 0x80, 0xFF)
        ];
        SDL_Color[3] unbright = [SDL_Color(0xC0, 0xC0, 0xC0, 0xFF),
            SDL_Color(0xFF, 0xC0, 0xC0, 0xFF),
            SDL_Color(0xE0, 0xE0, 0xE0, 0xFF)
        ];

        string description = "";

        update_letters(gs);

        if (gs.alt_gr)
            gs.keybar.scans_cur = &gs.keybar.scans_altgr;
        else
            gs.keybar.scans_cur = &gs.keybar.scans;

        for (ssize_t j=0; j < 3; j++)
        {
            bool sameleft = false;
            if (j==1 && (*gs.keybar.letters)[j][i] == (*gs.keybar.letters)[0][i])
                sameleft = true;
            KeyHandler* key_handler = (*gs.keybar.scans_cur)[j][i] in gs.keybar.handlers;
            KeyHandler* key_handler_down = (*gs.keybar.scans_cur)[j][i] in gs.keybar.handlers_down;
            KeyHandler* key_handler_double = (*gs.keybar.scans_cur)[j][i] in gs.keybar.handlers_double;
            if (key_handler || key_handler_down || key_handler_double)
            {
                if (gs.keybar.pos == i && (*gs.keybar.letters)[j][i] > "")
                {
                    if (key_handler && key_handler.description > "")
                        description ~= (*gs.keybar.letters)[j][i]~" - "~key_handler.description ~ "\n";
                    if (key_handler_down && key_handler_down.description > "")
                        description ~= "Hold " ~ (*gs.keybar.letters)[j][i]~" - "~key_handler_down.description ~ "\n";
                    if (key_handler_double && key_handler_double.description > "")
                        description ~= "Double " ~ (*gs.keybar.letters)[j][i]~" - "~key_handler_double.description ~ "\n";
                }

                if (!key_handler && key_handler_down)
                    key_handler = key_handler_down;

                if (!key_handler && key_handler_double)
                    key_handler = key_handler_double;

                if ( key_handler.icon.endsWith(".png") )
                {
                    string image_file = gs.start_cwd~SL~"images"~SL~key_handler.icon;
                    if (!exists(image_file))
                    {
                        image_file = "/usr/share/unde/images/"~key_handler.icon;
                        if (!exists(image_file))
                        {
                            new Exception("Not found .images or /usr/share/unde/images/");
                        }
                    }

                    auto st = get_image_from_cache(gs, image_file);

                    if (st)
                    {
                        SDL_Rect dst;
                        dst.x = rect.x + xp[j];
                        dst.y = rect.y + yp[j];
                        if (j == 2 && i >= 6*4) 
                        {
                            dst.x+=24;
                            dst.y-=16;
                        }
                        dst.w = st.w;
                        dst.h = st.h;

                        r = SDL_RenderCopy(gs.renderer, st.texture, null, &dst);
                        if (r < 0)
                        {
                            writefln( "draw_keybar() 2: Error while render copy: %s",
                                    SDL_GetError().fromStringz() );
                        }
                    }
                    else
                    {
                        writefln("Can't load %s: %s",
                                image_file,
                                IMG_GetError().fromStringz());
                    }
                }
                else
                {
                    int fontsize = 8;
                    if (key_handler.icon.walkLength() > 1 && i < 24 ||
                            j==2 && i == 28)
                        fontsize = 6;
                    if (key_handler.icon == "Menu" ||
                                key_handler.icon == "Spc")
                            fontsize = 7;
                    tt = gs.text_viewer.font.get_line_from_cache(key_handler.icon, 
                            fontsize, 48, 20, bright[j], attrs);
                    if (!tt && !tt.texture)
                    {
                        throw new Exception("Can't create text_surface: "~
                                TTF_GetError().fromStringz().idup());
                    }

                    SDL_Rect dst;
                    dst.x = rect.x + x[j];
                    if ( j == 1 && i == 11 )
                        dst.x -= 8;
                    dst.y = rect.y + y[j];
                    if ( key_handler.icon.walkLength == 1 && j == 2 )
                        dst.y -= 7;
                    if ( (*gs.keybar.letters)[j][i] == "Enter" && i >= 24 )
                    {
                        dst.x = rect.x+24;
                        dst.y = rect.y+3;
                    }
                    dst.w = tt.w;
                    dst.h = tt.h;

                    r = SDL_RenderCopy(gs.renderer, tt.texture, null, &dst);
                    if (r < 0)
                    {
                        writefln( "draw_keybar() 3: Error while render copy: %s",
                                SDL_GetError().fromStringz() );
                    }

                }
            }
            else
            {
                if (sameleft) continue;
                int fontsize = 8;
                if ((*gs.keybar.letters)[j][i].walkLength() > 1 && i < 24 ||
                        j==2 && i == 28)
                    fontsize = 6;
                if ((*gs.keybar.letters)[j][i] == "Menu" ||
                        (*gs.keybar.letters)[j][i] == "Spc")
                    fontsize = 7;
                tt = gs.text_viewer.font.get_line_from_cache((*gs.keybar.letters)[j][i], 
                        fontsize, 48, 20, (gs.keybar.input_mode?bright[j]:unbright[j]), attrs);
                if (!tt && !tt.texture)
                {
                    throw new Exception("Can't create text_surface: "~
                            TTF_GetError().fromStringz().idup());
                }

                SDL_Rect dst;
                dst.x = rect.x + x[j];
                if ( j == 1 && i == 11 )
                    dst.x -= 8;
                dst.y = rect.y + y[j];
                if ( (*gs.keybar.letters)[j][i].walkLength == 1 && j == 2 )
                    dst.y -= 7;
                if ( (*gs.keybar.letters)[j][i] == "Enter" && i >= 24 )
                {
                    dst.x = rect.x+24;
                    dst.y = rect.y+3;
                }
                dst.w = tt.w;
                dst.h = tt.h;

                r = SDL_RenderCopy(gs.renderer, tt.texture, null, &dst);
                if (r < 0)
                {
                    writefln( "draw_keybar() 4: Error while render copy: %s",
                            SDL_GetError().fromStringz() );
                }
            }
        }

        if (description != "")
        {
            description = description[0..$-1];

            int fontsize = 8;
            int line_height = cast(int)(round(SQRT2^^fontsize)*1.2);
            tt = gs.text_viewer.font.get_line_from_cache(description, 
                    fontsize, 32*6, line_height, SDL_Color(0xFF, 0xFF, 0xFF, 0xFF));
            if (!tt && !tt.texture)
            {
                throw new Exception("Can't create text_surface: "~
                        TTF_GetError().fromStringz().idup());
            }

            /* Render black background */
            SDL_Rect dst;
            dst.x = gs.screen.w;
            dst.y = gs.screen.h - 32*4-16 - tt.h;
            dst.w = tt.w;
            dst.h = tt.h;

            r = SDL_RenderCopy(gs.renderer, gs.texture_black, null, &dst);
            if (r < 0)
            {
                writefln( "draw_keybar(), 5: Error while render copy: %s",
                        SDL_GetError().fromStringz() );
            }

            /* Render description of buttons */
            r = SDL_RenderCopy(gs.renderer, tt.texture, null, &dst);
            if (r < 0)
            {
                writefln( "draw_keybar() 6: Error while render copy: %s",
                        SDL_GetError().fromStringz() );
            }
        }
    }
}

void
save_keybar_settings(GlobalState gs)
{
    with(gs.keybar)
    {
        Dbt key, data;
        string keybar_settings_str = "keybar_settings";
        key = keybar_settings_str;
        string data_str = "";

        data_str ~= (cast(char*)&changer)[0..changer.sizeof];
        foreach(layout_mode; layout_modes)
        {
            data_str ~= layout_mode.short_name ~ "\0";
        }

        data = data_str;

        auto res = gs.db_marks.put(null, &key, &data);
        if (res != 0)
        {
            throw new Exception("Oh, no, can't to write keybar settings");
        }
    }
}

void
load_keybar_settings(GlobalState gs, KeyBar_Buttons keybar)
{
    with(keybar)
    {
        Dbt key, data;
        string keybar_settings_str = "keybar_settings";
        key = keybar_settings_str;

        auto res = gs.db_marks.get(null, &key, &data);
        if (res == 0)
        {
            string data_str = data.to!(string);
            changer = *cast(LayoutChanger*)(data_str[0..changer.sizeof].ptr);
            data_str = data_str[changer.sizeof..$];
            ssize_t pos;
            while ( (pos = data_str.indexOf("\0")) >= 0 )
            {
                layout_modes ~= &layouts[data_str[0..pos]];
                data_str = data_str[pos+1..$];
            }
        }
        else
        {
            layout_modes ~= &layouts["us(basic)"];
            version (Posix)
            {
                string lc_messages = setlocale(LC_MESSAGES, null).fromStringz().idup();
                writefln("lc_messages=%s", lc_messages);
                if (lc_messages == "" || lc_messages == "C")
                    lc_messages = environment["LANG"];
                writefln("lc_messages=%s", lc_messages);
                if (lc_messages.length > 3 && lc_messages[0..3] == "ru_")
                {
                    layout_modes ~= &layouts["ru(winkeys)"];
                }
            }
	    else
	    version (Windows)
	    {
		auto lang = 0xFF & GetUserDefaultUILanguage();
		if (lang == LANG_RUSSIAN)
		{
		    layout_modes ~= &layouts["ru(winkeys)"];
		}
	    }
            changer = LayoutChanger.LeftWin;
            keybar_settings_needed = true;
        }
    }
}
