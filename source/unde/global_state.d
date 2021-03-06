module unde.global_state;

import unde.lib;
import unde.lsblk;
import unde.clickable;
import unde.path_mnt;
import unde.font;
import unde.marks;
import unde.slash;
import unde.command_line.lib;
import unde.file_manager.events;
import unde.keybar.lib;
import unde.keybar.settings;
import unde.guitk.lib;

import std.format;
import std.conv;
import std.stdio;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.errno;
import core.thread;
version (Posix)
{
	import core.sys.posix.unistd: fork;
}
import core.sys.posix.sys.ioctl;
import std.string;
import std.concurrency;
import std.datetime;
import std.math;
import std.container.slist;
import std.regex;
import std.exception;
import std.process;

import berkeleydb.all;
import derelict.sdl2.sdl;
import derelict.sdl2.ttf;
import derelict.sdl2.image;

version (Windows)
{
	struct winsize
	{
	    int ws_col;
	    int ws_row;
	    int ws_xpixel;
	    int ws_ypixel;
	}
}

public import core.sys.posix.sys.types;

import std.file;

struct Texture_Tick
{
    int w, h;
    SDL_Rect[] chars;
    SDL_Texture* texture;
    long tick;
}

mixin template init_deinitBDB(bool main_thread = false)
{
    DbEnv dbenv;
    Db db_map;
    Db db_marks;
    Db db_commands;
    Db db_command_output;

    void initBDB(bool force_recover = false)
    {
        string home = environment["HOME"];
        version(Windows)
        {
	    if (!home.startsWith("C:\\cygwin\\home") &&
			!home.startsWith("D:\\cygwin\\home") &&
            !home.startsWith("C:\\cygwin64\\home") &&
			!home.startsWith("D:\\cygwin64\\home"))
            {
                throw new Exception("Please run under Cygwin environment. Read README.");
            }
        }

        try{
            mkdir(home ~ "/.unde");
        } catch (Exception file)
        {
        }

        try{
            mkdir(home ~ "/.unde/bdb/");
        } catch (Exception file)
        {
        }

        bool recover = force_recover;
        bool goto_recover = false;
recover:
        if (main_thread)
        {
            if (recover)
            {
                writefln("Open Database. Recover mode enabled. Please wait...");
            }
            else
            {
                writefln("Open Database. If it takes long, try `./unde --force_recover`");
            }
        }

        dbenv = new DbEnv(0);

        dbenv.log_set_config(DB_LOG_AUTO_REMOVE, 1);
        dbenv.set_memory_max(16*1024*1024);
        dbenv.set_lk_detect(DB_LOCK_MAXLOCKS);

        uint env_flags = DB_CREATE |    /* Create the environment if it does 
                                    * not already exist. */
                    DB_INIT_TXN  | /* Initialize transactions */
                    DB_INIT_LOCK | /* Initialize locking. */
                    DB_INIT_LOG  | /* Initialize logging */
                    DB_INIT_MPOOL| /* Initialize the in-memory cache. */
                    (recover?DB_RECOVER:0);

        dbenv.open(home ~ "/.unde/bdb/", env_flags, octal!666);

        db_map = new Db(dbenv, 0);
        db_map.open(null, "map.db", null, DB_BTREE, DB_CREATE | 
                        DB_AUTO_COMMIT /*| DB_MULTIVERSION*/, octal!600);

        db_marks = new Db(dbenv, 0);
        db_marks.open(null, "marks.db", null, DB_BTREE, DB_CREATE | 
                        DB_AUTO_COMMIT /*| DB_MULTIVERSION*/, octal!600);

        db_commands = new Db(dbenv, 0);
        db_commands.open(null, "commands.db", null, DB_BTREE, DB_CREATE | 
                        DB_AUTO_COMMIT /*| DB_MULTIVERSION*/, octal!600);

        db_command_output = new Db(dbenv, 0);
        db_command_output.open(null, "command_output.db", null, DB_BTREE, DB_CREATE | 
                        DB_AUTO_COMMIT /*| DB_MULTIVERSION*/, octal!600);

        txn = dbenv.txn_begin(null);

        try
        {
            Dbt key, data;
            string opened_str = "opened";
            key = opened_str;

            int opened = 0;

            if (!main_thread || !recover)
            {
                auto res = db_marks.get(txn, &key, &data);
                if (res == 0)
                {
                    opened = data.to!int;
                }
            }

            if (main_thread && opened != 0 && !recover)
            {
                recover = true;
                txn.abort();
                txn = null;
                db_command_output.close();
                db_commands.close();
                db_marks.close();
                db_map.close();
                dbenv.close();
                goto recover;
            }

            opened++;
            data = opened;
            auto res = db_marks.put(txn, &key, &data);
            if (res != 0)
            {
                throw new Exception("Oh, no, can't to write new value of opened");
            }
        }
        catch (Exception exp)
        {
            goto_recover = true;
        }

        if (main_thread && !recover && goto_recover)
        {
            recover = true;
            txn.abort();
            txn = null;
            db_command_output.close();
            db_commands.close();
            db_marks.close();
            db_map.close();
            dbenv.close();
            goto recover;
        }

        txn.commit();
        txn = null;

        if (main_thread)
        {
            writefln("Clean logs.");
            dbenv.log_archive(DB_ARCH_REMOVE);
            writefln("Database opened.");
        }
    }

    void deInitBDB()
    {
        if (txn)
        {
            txn.abort();
            txn = null;
        }
        txn = dbenv.txn_begin(null);
        try
        {
            Dbt key, data;
            string opened_str = "opened";
            key = opened_str;

            int opened = 0;

            auto res = db_marks.get(txn, &key, &data);
            if (res == 0)
            {
                opened = data.to!int;
            }

            opened--;

            data = opened;
            res = db_marks.put(txn, &key, &data);
            if (res != 0)
            {
                throw new Exception("Oh, no, can't to write new value of opened");
            }
        }
        catch (Exception exp)
        {
        }

        txn.commit();
        txn = null;

        db_command_output.close();
        db_commands.close();
        db_marks.close();
        db_map.close();
        dbenv.close();
        dbenv = null;
        db_command_output = null;
        db_commands = null;
        db_marks = null;
        db_map = null;
    }
}

mixin template recommit()
{
    bool txn_on = true;
    DbTxn txn;
    int OIT; // operations in transaction
    long beginned;
    SysTime txn_started;

    bool is_time_to_recommit()
    {
        if (!txn_on) return false;
        return OIT > 100 || OIT > 0 && (Clock.currTime() - txn_started) > 200.msecs;
    }

    void recommit()
    {
        if (!txn_on) return;
        if (OIT > 100 || OIT > 0 && (Clock.currTime() - txn_started) > 200.msecs)
        {
            commit();
        }
        if (txn is null)
        {
            txn = dbenv.txn_begin(null);
            txn_started = Clock.currTime();
        }
    }

    void commit()
    {
        if (!txn_on) return;
        //writefln("Tid=%s, OIT=%d, time=%s", thisTid, OIT, Clock.currTime() - txn_started);
        if (txn !is null)
        {
            txn.commit();
            txn = null;
            OIT = 0;
        }
    }

    void abort()
    {
        //writefln("Tid=%s, OIT=%d, time=%s", thisTid, OIT, Clock.currTime() - txn_started);
        if (txn !is null)
        {
            txn.abort();
            txn = null;
            OIT = 0;
        }
    }
}

struct CopyMapInfo
{
    string path;
    bool[Tid] sent;
    bool move;
    Tid from;
}

class ScannerGlobalState
{
    LsblkInfo[string] lsblk;
    CopyMapInfo[string] copy_map;
    Tid parent_tid;
    bool finish;
    bool one_level;

    mixin init_deinitBDB;
    mixin recommit;

    this()
    {
        initBDB();
    }

    ~this()
    {
        deInitBDB();
    }
}

class FMGlobalState
{
    LsblkInfo[string] lsblk;
    bool finish;

    mixin init_deinitBDB;
    mixin recommit;

    this()
    {
        initBDB();
    }

    ~this()
    {
        deInitBDB();
    }
}

class CMDGlobalState
{
    bool finish;

    mixin init_deinitBDB;
    mixin recommit;

    this()
    {
        initBDB();
    }

    ~this()
    {
        deInitBDB();
    }
}

enum NameType
{
    CreateDirectory,
    Copy,
    Move
}

struct EnterName
{
    NameType type;
    string name;
    int pos;
}

struct AnimationInfo
{
    NameType type;
    int stage;
    string parent;
    bool from_calculated;
    bool to_calculated;
    SDL_Rect from;
    SDL_Rect to;
    long last_frame_time;
    double frame = 0.0;
}

struct RepeatStuffs
{
    long start_press;
    long last_process;
    SDL_Event event;
}

struct ConsoleMessage
{
    SDL_Color color;
    string message;
    uint from;
    SDL_Texture *texture;
    int w, h;
}

enum State
{
    FileManager,
    ImageViewer,
    TextViewer
}

struct Image_Viewer_State{
    PathMnt path;
    SDL_Rect rect;
    Texture_Tick *texture_tick;
    RectSize rectsize;

    ssize_t level;
    ssize_t[] positions;
    string[][] files;
    ssize_t sel;
    string[] selections;

    long last_image_cache_use;
    Texture_Tick[string] image_cache;
};

struct Text_Viewer_State{
    PathMnt path;
    int fontsize = 9;
    bool wraplines;
    int x, y;
    RectSize rectsize;

    ssize_t level;
    ssize_t[] positions;
    string[][] files;
    ssize_t sel;
    string[] selections;

    long last_redraw;
    SDL_Texture *texture;

    ssize_t mouse_offset;
    ssize_t start_selection;
    ssize_t end_selection;
    ssize_t first_click;

    Font font;
}

struct CmdOutPos
{
    ulong cmd_id;
    ulong out_id;
    ssize_t pos;

    int opCmp(CmdOutPos rhs)
    {
        if (cmd_id > rhs.cmd_id)
            return 1;
        else if (cmd_id < rhs.cmd_id)
            return -1;
        else
        {
            if (out_id > rhs.out_id)
                return 1;
            else if (out_id < rhs.out_id)
                return -1;
            else
            {
                if (pos > rhs.pos)
                    return 1;
                if (pos < rhs.pos)
                    return -1;
                else
                    return 0;
            }
        }
    }

}

struct Command_Line_State{
    int fontsize = 9;
    bool font_changed;

    bool enter;
    string command;
    string complete;
    string edited_command;
    ssize_t pos;

    string cwd;
    ulong hist_cmd_id;
    ssize_t hist_pos;

    ulong nav_skip_cmd_id;
    ulong nav_cmd_id;
    ulong nav_out_id;

    CmdOutPos mouse;
    CmdOutPos first_click;
    CmdOutPos start_selection;
    CmdOutPos end_selection;

    ssize_t cmd_mouse_pos;
    ssize_t cmd_first_click;
    ssize_t cmd_start_selection = -1;
    ssize_t cmd_end_selection = -1;
    SDL_Rect cmd_rect;

    double mouse_rel_y;
    long y;
    long neg_y;

    long last_enter;

    bool terminal;

    bool just_started_input;

    long last_redraw;
    SDL_Texture *texture;

    Tid command_in_focus_tid;
    ulong command_in_focus_id;

    long last_left_click;
    long last_right_click;
    long last_ctrl;
    int moved_while_click;

    void delegate() on_click;

    bool ctrl_mode;
    bool search_mode;
    string search;

    winsize ws;
}

enum Modifiers
{
    Left_Ctrl  = 0x0001,
    Right_Ctrl = 0x0002,
    Left_Shift = 0x0004,
    Right_Shift= 0x0008,
    Left_Alt   = 0x0010,
    Right_Alt  = 0x0020,
    CapsLock   = 0x0040,
    Left_Win   = 0x0080,
    Right_Win  = 0x0100,
    Space      = 0x0200,
    Menu       = 0x0400,
    ScrollLock = 0x0800,
}

class GlobalState
{
	SDL_Window* window;
    SDL_Renderer* renderer;
    SDL_Texture* surf_texture;
    bool finish = false;
    string start_cwd;
    string[] args;
    bool restart;
    uint frame; //Frame which renders
    uint time; //Time from start of program in ms
    immutable msize = 128;

    string desktop;
    string[string] mime_applications;
    State state;
    Image_Viewer_State image_viewer;
    Text_Viewer_State text_viewer;
    Command_Line_State command_line;
    KeyBar_Buttons keybar;
    UIPage[string] uipages;

    CoordinatesPlusScale screen;
    double mousex, mousey;
    int mouse_screen_x, mouse_screen_y;
    long last_mouse_down;
    long last_left_click;
    long last_right_click;
    long last_middle_click;
    long last_key_press;
    int key_press;
    int moved_while_click;
    uint flags;
    uint mouse_buttons;
    LsblkInfo[string] lsblk;

    SList!Clickable clickable_list;
    SList!Clickable new_clickable_list;

    SList!Clickable double_clickable_list;
    SList!Clickable new_double_clickable_list;

    SList!Clickable right_clickable_list;
    SList!Clickable new_right_clickable_list;

    SList!Clickable double_right_clickable_list;
    SList!Clickable new_double_right_clickable_list;

    SList!Clickable middle_clickable_list;
    SList!Clickable new_middle_clickable_list;

    ulong msg_stamp; // RU: Время ранее которого сообщения считать просмотренными
    ulong last_escape;

    Selection[] selection_list;
    DRect[string] selection_hash;
    bool[string] selection_sub;
    int selection_lsof; //list size on finish
    int selection_finish;
    int selection_stage = 2;

    ConsoleMessage[] messages;

    bool[string] interface_flags;
    bool dirty;
    bool redraw_fast;

    Tid[] scanners;
    Tid[string] rescanners;
    string[][Tid] removers;
    string[][Tid] copiers;
    string[][Tid] movers;
    string[][Tid] changers_rights;
    string[Tid] commands;
    ulong[Tid] delete_commands;
    Tid[ulong] tid_by_command_id;
    Pid[] pids;
    CopyMapInfo[string] copy_map;
    EnterName[string] enter_names;
    AnimationInfo[string] animation_info;
    RepeatStuffs repeat;

    bool mark;
    bool gomark;
    bool unmark;
    ushort modifiers;
    @property bool ctrl() { return (modifiers & (Modifiers.Left_Ctrl | Modifiers.Right_Ctrl)) != 0; }
    @property bool shift() { return (modifiers & (Modifiers.Left_Shift | Modifiers.Right_Shift)) != 0; }
    @property bool alt() { return (modifiers & (Modifiers.Left_Alt)) != 0; }
    @property bool alt_gr() { return (modifiers & (Modifiers.Right_Alt)) != 0; }
    bool shift_copy_or_move;
    DRect  current_path_rect;
    string current_path;
    string full_current_path;
    string main_path = SL;
    PathMnt path;
    DRect apply_rect;
    SortType sort;
    CoordinatesPlusScale surf;
    SDL_Texture* texture;
    SDL_Texture* texture_white;
    SDL_Texture* texture_black;
    SDL_Texture* texture_blue;
    SDL_Texture* texture_cursor;
    SDL_Texture* texture_gray;
    Gradient grad;

    void createWindow()
    {
        //The window we'll be rendering to
        window = SDL_CreateWindow(
            "unDE",                            // window title
            SDL_WINDOWPOS_UNDEFINED,           // initial x position
            SDL_WINDOWPOS_UNDEFINED,           // initial y position
            0,                                 // width, in pixels
            0,                                 // height, in pixels
            SDL_WINDOW_FULLSCREEN_DESKTOP | 
            SDL_WINDOW_RESIZABLE               // flags
        );
        if( window == null )
        {
            throw new Exception(format("Error while create window: %s",
                    SDL_GetError().to!string()));
        }
    }

    void createRenderer()
    {
        /* To render we need only renderer (which connected to window) and
           surfaces to draw it */
        renderer = SDL_CreateRenderer(
                window, 
                -1, 
                SDL_RENDERER_ACCELERATED | SDL_RENDERER_TARGETTEXTURE
        );
        if (!renderer)
        {
            writefln("Error while create accelerated renderer: %s",
                    SDL_GetError().to!string());
            renderer = SDL_CreateRenderer(
                    window, 
                    -1, 
                    SDL_RENDERER_TARGETTEXTURE
            );
        }
        if (!renderer)
        {
            throw new Exception(format("Error while create renderer: %s",
                    SDL_GetError().to!string()));
        }

        int r = SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);
        if (r < 0)
        {
            throw new Exception(
                    format("Error while set render draw blend mode: %s",
                    SDL_GetError().to!string()));
        }

        SDL_bool res = SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "1");
        if (!res)
        {
            throw new Exception(
                    format("Can't set filter mode"));
        }
    }

    void createTextures()
    {
        SDL_Surface* surface = SDL_CreateRGBSurface(0,
                1,
                1,
                32, 0x00FF0000, 0X0000FF00, 0X000000FF, 0XFF000000);

        (cast(uint*) surface.pixels)[0] = 0x80FFFFFF;

        texture_white =
            SDL_CreateTextureFromSurface(renderer, surface);

        (cast(uint*) surface.pixels)[0] = 0xAA000000;

        texture_black =
            SDL_CreateTextureFromSurface(renderer, surface);

        (cast(uint*) surface.pixels)[0] = 0x800000FF;

        texture_blue =
            SDL_CreateTextureFromSurface(renderer, surface);

        (cast(uint*) surface.pixels)[0] = 0xFFA0A0FF;

        texture_cursor =
            SDL_CreateTextureFromSurface(renderer, surface);

        (cast(uint*) surface.pixels)[0] = 0x80808080;

        texture_gray =
            SDL_CreateTextureFromSurface(renderer, surface);

        text_viewer.texture = SDL_CreateTexture(renderer,
                SDL_PIXELFORMAT_ARGB8888,
                SDL_TEXTUREACCESS_TARGET,
                screen.w,
                screen.h);
        if( !text_viewer.texture )
        {
            throw new Exception(format("Error while creating text_viewer.texture: %s",
                    SDL_GetError().to!string() ));
        }

        command_line.texture = SDL_CreateTexture(renderer,
                SDL_PIXELFORMAT_ARGB8888,
                SDL_TEXTUREACCESS_TARGET,
                screen.w,
                screen.h);
        if( !command_line.texture )
        {
            throw new Exception(format("Error while creating command_line.texture: %s",
                    SDL_GetError().to!string() ));
        }

        SDL_FreeSurface(surface);
    }

    void initSDL()
    {
        DerelictSDL2.load();
        
        if( SDL_Init( SDL_INIT_VIDEO | SDL_INIT_TIMER ) < 0 )
        {
            throw new Exception(format("Error while SDL initializing: %s",
                    SDL_GetError().to!string() ));
        }

        createWindow();
        createRenderer();

        SDL_GetWindowSize(window, &screen.w, &screen.h);
        screen.w -= 192;

        createTextures();

        surf.w = 2*screen.w;
        surf.h = 2*screen.h;
        surf_texture = SDL_CreateTexture(renderer,
                SDL_PIXELFORMAT_ARGB8888,
                SDL_TEXTUREACCESS_TARGET,
                surf.w,
                surf.h);
        if( !surf_texture )
        {
            throw new Exception(format("Error while creating surf_texture: %s",
                    SDL_GetError().to!string() ));
        }

        texture = SDL_CreateTexture(renderer,
                SDL_PIXELFORMAT_ARGB8888,
                SDL_TEXTUREACCESS_TARGET,
                surf.w,
                surf.h);
        if( !texture )
        {
            throw new Exception(format("Error while creating surf_texture: %s",
                    SDL_GetError().to!string() ));
        }
    }

    void deInitSDL()
    {
        SDL_DestroyTexture(text_viewer.texture),
        SDL_DestroyTexture(texture_blue);
        SDL_DestroyTexture(texture_black);
        SDL_DestroyTexture(texture_white);
        SDL_DestroyTexture(texture);
        SDL_DestroyTexture(surf_texture);
        SDL_DestroyRenderer(renderer);
        SDL_DestroyWindow(window);
        SDL_Quit();
    }

    void initSDLImage()
    {
        DerelictSDL2Image.load();

        auto flags = IMG_INIT_JPG | IMG_INIT_PNG | IMG_INIT_TIF;
        int initted = IMG_Init(flags);
        if((initted&flags) != flags) {
            if (!(IMG_INIT_JPG & initted))
                writefln("IMG_Init: Failed to init required jpg support!");
            if (!(IMG_INIT_PNG & initted))
                writefln("IMG_Init: Failed to init required png support!");
            if (!(IMG_INIT_TIF & initted))
                writefln("IMG_Init: Failed to init required tif support!");
            throw new Exception(format("IMG_Init: %s\n",
                        IMG_GetError().to!string()));
        }
    }

    void initSDLTTF()
    {
        text_viewer.font = new Font(renderer);
    }

    void initAllSDLLibs()
    {
        initSDL();
        initSDLImage();
        initSDLTTF();
    }

    void deInitAllSDLLibs()
    {
        IMG_Quit();
        deInitSDL();
    }

    mixin init_deinitBDB!true;
    mixin recommit;

    void initGradient()
    {
        /* Gradient Initialize */
        grad.add(SDL_Color(  0, 255, 255, 255), 0.0);
        grad.add(SDL_Color(  0, 255,   0, 255), 3.0);
        grad.add(SDL_Color(255, 255,   0, 255), 6.0);
        grad.add(SDL_Color(255,   0,   0, 255), 9.0);
        grad.add(SDL_Color(255,   0, 255, 255), 12.0);
    }

    void initScreenAndSurf()
    {
        path = PathMnt(SL);
        apply_rect = DRect(0, 0, 1024*1024, 1024*1024);

        screen.x = 0;
        screen.y = 0;
        screen.scale = 2 * 1024*1024 / screen.w;

        surf.x = 0;
        surf.y = 0;
        surf.scale = 1;
    }

    void loadMimeApplications()
    {
        try
        {
            string home = environment["HOME"];
            auto file = File(home ~ "/.unde/mime");
            foreach (line; file.byLine())
            {
                auto match = matchFirst(line, regex(`([^ ]*) *= *(.*)`));
                if (match)
                {
                    mime_applications[match[1].idup()] = match[2].idup();
                }
            }
        }
        catch(ErrnoException e)
        {
            writefln("~/.unde/mime NOT FOUND");
            writefln(q{Example of line "text/plain = gvim"});
        }
    }

    void getCurrentDesktop()
    {
        string current_desktop = "current_desktop"; 
        Dbt key = current_desktop;
        Dbt data;

        auto res = db_marks.get(null, &key, &data);

        desktop = "1";
        if (res == 0)
        {
            desktop = data.to!(string).idup();
        }

	if (desktop.length != 1 || desktop[0] < '0' || desktop[0] > '9')
        {
	    writefln("WARNING! current_desktop = %s", desktop);
            desktop = "1";
        }

        go_mark(this, desktop);
    }

    this(bool force_recover = false)
    {
        start_cwd = getcwd();
        txn_on = false;
        msg_stamp = Clock.currTime().toUnixTime();
        initBDB(force_recover);
        initAllSDLLibs();
        initGradient();
        initScreenAndSurf();
        loadMimeApplications();
        .lsblk(this.lsblk);
        getCurrentDesktop();
        update_winsize(this);
        keybar = new KeyBar_Buttons(this, renderer, start_cwd);
        setup_keybar_filemanager_default(this);
        uipages["keybar_settings"] = create_keybar_settings_ui(this);
    }

    ~this()
    {
        deInitBDB();
        deInitAllSDLLibs();
        if (restart)
        {
	    version (Posix)
	    {
		    writefln("Restart");
		    int r = fork();
		    if (r < 0)
		    {
			throw new Exception("fork() error: " ~ fromStringz(strerror(errno)).idup());
		    }
		    else if (r == 0)
		    {
			Thread.sleep(2.seconds);
			chdir(start_cwd);
			execv(args[0], args);
			assert(0);
		    }
	    }
	    else version (Windows)
	    {
		    writefln("Restart in windows version not supported. Exit.");
	    }
        }
    }
}

