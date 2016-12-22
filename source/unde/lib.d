module unde.lib;

import derelict.sdl2.sdl;
import std.container.dlist;
import std.stdio;
import std.format;
import std.string;
import std.process;
import std.regex;
import std.conv;
import std.utf;
import core.exception;

import derelict.sdl2.sdl;

import unde.global_state;
import unde.slash;

import core.sys.posix.sys.stat;
import core.sys.posix.pwd;
import core.sys.posix.grp;
version(Windows)
{
import core.stdc.time;
alias ulong ulong_t;
}

enum DOUBLE_DELAY=750;

enum PATH_MAX=4096; //from linux/limits.h
enum UUID_MAX=36;
enum MARKS_PATH_MAX=PATH_MAX+UUID_MAX;

struct Gradient
{
    struct ColorPoint
    {
        SDL_Color color;
        double  point;
    }

    DList!ColorPoint grad;

    void add(SDL_Color color, double point)
    {
        auto range = grad[];

        foreach(a; grad[])
        {
            if (point < a.point)
            {
                grad.insertBefore(range, ColorPoint(color, point));
                return;
            }
            range.popFront();
        }
        grad.insertBack(ColorPoint(color, point));
    }

    SDL_Color getColor(double point)
    {
        auto range = grad[];

        ColorPoint *a;
        ColorPoint *b;

        foreach(g; grad[])
        {
            if (point < g.point)
            {
                b = &g;
                if (!a) return b.color;

                SDL_Color ret;
                double k = (point - a.point) / (b.point - a.point);
                ret.r = cast(ubyte)(a.color.r * (1.0-k) + b.color.r * k);
                ret.g = cast(ubyte)(a.color.g * (1.0-k) + b.color.g * k);
                ret.b = cast(ubyte)(a.color.b * (1.0-k) + b.color.b * k);
                ret.a = cast(ubyte)(a.color.a * (1.0-k) + b.color.a * k);
                return ret;
            }
            a = &range.front();
            range.popFront();
        }

        return grad[].back.color;
    }
}

unittest
{
    import std.algorithm: equal;
    Gradient grad;
    grad.add(SDL_Color(0, 0, 0, 1), 1);
    grad.add(SDL_Color(0, 0, 0, 3), 3);
    grad.add(SDL_Color(0, 0, 0, 2), 2);
    grad.add(SDL_Color(0, 0, 0, 0), 0);

    /*foreach(a; grad.grad[])
    {
        writefln("%d - %.2f", a.color.a, a.point);
    }*/
    assert(equal(grad.grad[], [
                             Gradient.ColorPoint(SDL_Color(0,0,0,0), 0),
                             Gradient.ColorPoint(SDL_Color(0,0,0,1), 1),
                             Gradient.ColorPoint(SDL_Color(0,0,0,2), 2),
                             Gradient.ColorPoint(SDL_Color(0,0,0,3), 3),]));
}

struct DRect
{
    double x,y,w,h;

    bool In(in ref DRect b) const
    {
        return x >= b.x && (x+w) <= (b.x+b.w) &&
               y >= b.y && (y+h) <= (b.y+b.h);
    }
    bool NotIntersect(in ref DRect b) const
    {
        return ((b.x+b.w) < x || b.x > (x+w) ||
                (b.y+b.h) < y || b.y > (y+h));
    }
    DRect apply(in ref DRect b) const
    {
        DRect res;
        res.x = b.x + x*b.w/(1024*1024);
        res.y = b.y + y*b.h/(1024*1024);
        res.w = b.w * w / (1024*1024);
        res.h = b.h * h / (1024*1024);
        //assert(res.In(b), format("apply must make rectangle which lays in b.\nthis=%s, b=%s, res=%s", this, b, res));
        return res;
    }
    SDL_Rect to_screen(in ref CoordinatesPlusScale screen)
    {
        SDL_Rect rect;
        rect.x = cast(int)((x - screen.x)/screen.scale);
        rect.y = cast(int)((y - screen.y)/screen.scale);
        rect.w = cast(int)(w/screen.scale);
        rect.h = cast(int)(h/screen.scale);
        return rect;
    }

    void rescale_screen(ref CoordinatesPlusScale screen, SDL_Rect rect)
    {
        screen.scale = w/rect.w;
        screen.x = x - rect.x*screen.scale;
        screen.y = y - rect.y*screen.scale;
    }
}

struct CoordinatesPlusScale
{
    double x, y;
    int w, h;
    double scale;

    DRect getRect()
    {
        DRect rect;
        rect.x = x;
        rect.y = y;
        rect.w = w*scale;
        rect.h = h*scale;
        return rect;
    }
}

enum SortType
{
    ByName = 0,
    BySize,
    ByTime
}

enum FileType
{
    Directory = 0,
    File,
    Image,
    Text
}

enum InfoType
{
    None = 0,
    CreateDirectory,
    Copy,
    Move,
    FileInfo,
    Progress
}

char[i] to_char_array(int i)(string str)
{
    char[i] ret;
    size_t l = str.length;
    if (l > i) l = i;
    ret[0..l] = str[0..l];
    return ret;
}

string from_char_array(const char[] str)
{
    int i;
    foreach (c; str)
    {
        if (c == char.init) break;
        i++;
    }
    return str[0..i].idup();
}

wstring from_char_array(const wchar[] str)
{
    int i;
    foreach (c; str)
    {
        if (c == wchar.init) break;
        i++;
    }
    return str[0..i].idup();
}

string strip_error(string str)
{
    return str[str.indexOf(":")+2..$];
}

struct RectSize
{
    DRect rect_by_name;
    DRect rect_by_size;
    DRect rect_by_time;

    long size;
    long disk_usage;
    time_t mtime;
    ulong_t mtime_nsec;
    long files;
    InfoType show_info;

    union{
        struct
        {
            // Error Message
            char[80] msg;
            long msg_time;
            uint msg_color;
        };
        struct
        {
            // Progress Info
            char[80] path;
            long estimate_end;
            int progress; // from 0 tlll 10000
        };
    }

    FileType type;

    union
    {
        struct {
        // Directory
            SortType sort;
            long newest_msg_time;
        };
        struct {
        // Image
            double angle;
        };
        struct {
        // Text
            long offset;
            char[32] charset;
        };
    }

    ref inout(DRect) rect(const SortType sort) inout
    {
        final switch(sort)
        {
            case SortType.ByName:
                return rect_by_name;
            case SortType.BySize:
                return rect_by_size;
            case SortType.ByTime:
                return rect_by_time;
        }
    }
}

struct Mark
{
    char[MARKS_PATH_MAX] path;
    SDL_Rect screen_rect;
    State state;
    union{
        struct
        { // Text
            long offset;
        }
    }
}

struct DirEntryRect
{
    string path;
    DRect rect;
    long size;
    alias rect this;

    this (string path, long x, long y, long w, long h, long size)
    {
        this.path = path;
        rect = DRect(x, y, w, h);
        this.size = size;
    }

    this (string path, DRect rect, long size)
    {
        this.path = path;
        this.rect = rect;
        this.size = size;
    }
}

string
subpath(string path, string mnt)
{
    if (mnt == SL) return path;
    if (mnt == path) return SL;
    return path[mnt.length..$];
}

void
calculate_selection_sub(GlobalState gs)
{
    gs.selection_sub = null;
    foreach(path, rectsize; gs.selection_hash)
    {
        path = getParent(path);
        while (path > "")
        {
            gs.selection_sub[path] = true;
            path = getParent(path);
        }
        gs.selection_sub[SL] = true;
    }
}

struct Selection
{
    string from;
    string to;

    long size_from;
    long size_to;

    time_t mtime_from;
    time_t mtime_to;

    SortType sort;
}

version (Posix)
{
import core.sys.posix.sys.types;
import core.sys.posix.sys.stat;
string mode_to_string(mode_t mode)
{
    char[12] res;
    res[ 0] = mode & S_ISUID ? 'U' : '-';
    res[ 1] = mode & S_ISGID ? 'G' : '-';
    res[ 2] = mode & S_ISVTX ? 'S' : '-';
    res[ 3] = mode & S_IRUSR ? 'r' : '-';
    res[ 4] = mode & S_IWUSR ? 'w' : '-';
    res[ 5] = mode & S_IXUSR ? 'x' : '-';
    res[ 6] = mode & S_IRGRP ? 'r' : '-';
    res[ 7] = mode & S_IWGRP ? 'w' : '-';
    res[ 8] = mode & S_IXGRP ? 'x' : '-';
    res[ 9] = mode & S_IROTH ? 'r' : '-';
    res[10] = mode & S_IWOTH ? 'w' : '-';
    res[11] = mode & S_IXOTH ? 'x' : '-';
    return res.idup();
}

string uid_to_name(uid_t uid)
{
    auto pwd = getpwuid(uid);
    return fromStringz(pwd.pw_name).idup();
}

string gid_to_name(gid_t gid)
{
    auto pwd = getgrgid(gid);
    return fromStringz(pwd.gr_name).idup();
}
}

string
mime(string path)
{
    auto df_pipes = pipeProcess(["file", "-bi", path], Redirect.stdout);
    scope(exit) wait(df_pipes.pid);

    int l=0;
    foreach (df_line; df_pipes.stdout.byLine)
    {
        if (l == 0)
        {
            auto match = matchFirst(df_line, regex(`(.*); charset=.*`));
            if (match)
            {
                return match[1].idup();
            }
        }
        l++;
    }
    return "error/none";
}

int
db_recover(string path)
{
    auto df_pipes = pipeProcess(["db_recover", "-h", path], Redirect.stdout | Redirect.stderrToStdout);
    scope(exit) wait(df_pipes.pid);

    foreach (df_line; df_pipes.stdout.byLine)
    {
        writefln(df_line);
    }

    return 0;
}

void
unDE_RenderFillRect(SDL_Renderer *renderer, SDL_Rect *rect, uint color)
{
    int r = SDL_SetRenderDrawColor(renderer, 
            (color&0xFF0000) >> 16,
            (color&0xFF00) >> 8,
            color&0xFF,
            (color&0xFF000000) >> 24);
    if (r < 0)
    {
        writefln("Can't SDL_SetRenderDrawColor: %s",
                fromStringz(SDL_GetError()));
    }

    r = SDL_RenderFillRect(renderer, rect);
    if (r < 0)
    {
        writefln("Can't SDL_RenderFillRect: %s",
                fromStringz(SDL_GetError()));
    }
}

version(Windows)
{
import core.sys.windows.winbase;

string GetErrorMessage()
{
	wchar[1024] pBuffer;

	auto res = FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM,
			null, 
			GetLastError(),
			0,
			pBuffer.ptr, 
			pBuffer.length, 
			null);
	if (!res)
	{
		writefln("FormatMessage error %s", GetLastError());
	}

	return to!string(from_char_array(pBuffer));
}
}

string getParent(string path)
{
	version (Windows)
	{
	if (path.lastIndexOf(SL) < 0)
		return SL;
	}
        return path[0..path.lastIndexOf(SL)];
}

size_t
mystride(T)(T str, size_t pos)
{
    try
    {
        return str.stride(pos);
    }
    catch (UnicodeException e)
    {
    }
    catch (UTFException e)
    {
    }
    return 1;
}

