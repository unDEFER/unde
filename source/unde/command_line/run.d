module unde.command_line.run;

import unde.global_state;
import unde.lsblk;
import unde.path_mnt;
import unde.slash;
import unde.command_line.db;

import std.stdio;
import std.conv;
import core.stdc.stdlib;
import std.math;
import berkeleydb.all;
import std.stdint;
import core.stdc.stdlib;
import std.string;
import std.algorithm.sorting;
import std.algorithm.searching;
import std.algorithm.comparison;
import std.utf;
import std.concurrency;
import core.time;
import core.exception;
import core.sys.posix.sys.select;
import core.sys.posix.fcntl;
import core.sys.posix.unistd;
import core.stdc.string;
import core.stdc.errno;
import core.thread;
import std.process;
import std.regex;
import std.datetime;
import std.algorithm.mutation;
import core.sys.posix.pty; //Hand-made module
import core.sys.posix.sys.ioctl;
import core.sys.posix.termios;
import core.sys.posix.sys.wait;

import unde.lib;

import std.file;

version(Windows)
{
import core.sys.windows.windows;
import core.stdc.time;
alias ulong ulong_t;
}

private void
set_non_block_mode(int fd)
{
    int flags;
    if (-1 == (flags = fcntl(fd, F_GETFL, 0)))
        flags = 0;
    int res = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    if (res < 0)
    {
        throw new Exception("fcntl() error: " ~ fromStringz(strerror(errno)).idup());
    }
}


private ulong
get_max_id_of_cwd(CMDGlobalState cgs, string cwd)
{
    Dbc cursor = cgs.db_commands.cursor(cgs.txn, 0);
    scope(exit) cursor.close();

    Dbt key, data;
    ulong id = find_prev_command(cursor, cwd, 0, key, data);

    if (id != 0)
    {
        string key_string = key.to!(string);
        command_key cmd_key;
        parse_key_for_command(key_string, cmd_key);
        if (cwd != cmd_key.cwd)
        {
            id = 0;
        }
        else
        {
            id = cmd_key.id;
        }
    }

    return id;
}

private ulong
find_command_in_cwd(CMDGlobalState cgs, string cwd, string command)
{
    Dbc cursor = cgs.db_commands.cursor(cgs.txn, 0);
    scope(exit) cursor.close();

    Dbt key, data;
    ulong id = 0;
    string ks = get_key_for_command(command_key(cwd, 0));
    key = ks;
    auto res = cursor.get(&key, &data, DB_SET_RANGE);
    if (res == DB_NOTFOUND)
    {
        return 0;
    }

    do
    {
        string key_string = key.to!(string);
        command_key cmd_key;
        parse_key_for_command(key_string, cmd_key);

        string data_string = data.to!(string);
        command_data cmd_data;
        parse_data_for_command(data_string, cmd_data);

        if (cmd_key.cwd != cwd) break;
        if (cmd_data.command == command)
        {
            id = cmd_key.id;
            break;
        }

    } while (cursor.get(&key, &data, DB_NEXT) == 0);

    return id;
}

private void
delete_command_out(CMDGlobalState cgs, string cwd, ulong cmd_id)
{
    Dbc cursor = cgs.db_command_output.cursor(cgs.txn, 0);
    scope(exit) cursor.close();

    Dbt key, data;
    ulong id = 0;
    string ks = get_key_for_command_out(command_out_key(cwd, cmd_id, 0));
    key = ks;
    auto res = cursor.get(&key, &data, DB_SET_RANGE);
    if (res == DB_NOTFOUND)
    {
        return;
    }

    do
    {
        string key_string = key.to!(string);
        command_out_key cmd_out_key;
        parse_key_for_command_out(key_string, cmd_out_key);

        if (cmd_out_key.cwd == cwd && cmd_out_key.cmd_id == cmd_id)
        {
            cursor.del();
            cgs.OIT++;
        }
        else
        {
            break;
        }

    } while (cursor.get(&key, &data, DB_NEXT) == 0);

}

enum StateEscape
{
    WaitEscape,
    WaitBracket,
    WaitNumberR,
    WaitText,
    WaitCSI
}

private size_t
process_escape_sequences(CMDGlobalState cgs, ushort cur_attr, 
        ref ushort[] attrs, ref size_t attrs_r, 
        ref char[4096] buf, ref size_t buf_r, ref size_t max_r, 
        ref char[4096] prebuf, ref ssize_t r)
{
    StateEscape state;
    ssize_t start_i;
    int substate;
    string text;
    int[] numbers;
    for (ssize_t i = 0; i < r; i += prebuf.mystride(i))
    {
        char[] chr;
        if (i+prebuf.mystride(i) > r)
            chr = prebuf[i..i+1];
        else
            chr = prebuf[i..i+prebuf.mystride(i)];

        //writefln("Process '%c' - %X (%d)", prebuf[i], prebuf[i], prebuf[i]);
        final switch (state)
        {
            case StateEscape.WaitEscape:
                if (chr.length > 1)
                {
                    writef("%s", chr);
                    /*writefln("%s", chr);
                    if (buf_r > 4)
                        writefln("buf=%s", buf[buf_r-4..buf_r+4]);*/
                    auto chrlen = buf.mystride(buf_r);
                    if (chrlen != chr.length)
                    {
                        //if (max_r + chr.length-chrlen > buf.length) max_r = buf.length - (chr.length-chrlen);
                        if (max_r <= buf_r+chrlen) 
                        {
                            buf[max_r..buf_r+chrlen] = ' ';
                            max_r = buf_r+chrlen;
                        }
                        std.algorithm.mutation.copy(buf[buf_r+chrlen..max_r] , buf[buf_r+chr.length..max_r+chr.length-chrlen]);
                        max_r += chr.length-chrlen;
                    }

                    buf[buf_r..buf_r+chr.length] = chr;
                    /*if (buf_r > 4)
                        writefln("After buf=%s", buf[buf_r-4..buf_r+4]);*/
                    buf_r+=chr.length;
                    if (buf_r > max_r) max_r = buf_r;
                    if (attrs_r >= attrs.length) attrs.length = attrs_r+1;
                    attrs[attrs_r] = cur_attr;
                    attrs_r++;
                    continue;
                }

                if (prebuf[i] == '\x07') //Bell
                {
                    continue;
                }
                if (prebuf[i] == '\x08') //BackSpace
                {
                    start_i = i;
                    if (buf_r >= buf.strideBack(buf_r))
                        buf_r -= buf.strideBack(buf_r);
                    attrs_r--;
                    writefln("BackSpace");
                    //writefln("buf_r2=%s", buf[buf_r..max_r]);
                    state = StateEscape.WaitEscape;
                }
                if (prebuf[i] == '\x09') //Tab
                {
                    ssize_t n = buf[0..buf_r].lastIndexOf("\n");
                    if (n < 0) n = 0;
                    else n++;

                    ssize_t spaces = 8-(buf_r - n)%8;

                    for (ssize_t j=0; j < spaces; j++)
                    {
                        auto chrlen = buf.mystride(buf_r);
                        if (chrlen != 1)
                        {
                            if (max_r <= buf_r+chrlen) 
                            {
                                buf[max_r..buf_r+chrlen] = ' ';
                                max_r = buf_r+chrlen;
                            }
                            std.algorithm.mutation.copy(buf[buf_r+chrlen..max_r], buf[buf_r+1..max_r+1-chrlen]);
                            max_r += 1-chrlen;
                        }
                        buf[buf_r] = ' ';
                        /*if (buf_r > 4)
                            writefln("After buf=%s", buf[buf_r-4..buf_r+4]);*/
                        buf_r++;
                        if (buf_r > max_r) max_r = buf_r;
                        if (attrs_r >= attrs.length) attrs.length = attrs_r+1;
                        attrs[attrs_r] = cur_attr;
                        attrs_r++;
                    }

                    state = StateEscape.WaitEscape;
                }
                else if (prebuf[i] == '\x1B')
                {
                    start_i = i;
                    state = StateEscape.WaitBracket;
                    auto till = prebuf[i+1..r].indexOf("\x1B");
                    if (till < 0) till = r;
                    else till += i+1;
                    writefln("ESC %s", prebuf[i+1..till]);
                }
                else if (prebuf[i] == '\x9B')
                {
                    start_i = i;
                    state = StateEscape.WaitCSI;
                    text = "";
                    numbers = [];
                }
                else
                {
                    if ( (prebuf[i] < 0x20 || prebuf[i] == 0x7F) && prebuf[i] != '\n')
                    {
                        writef("%X(%d)", prebuf[i], prebuf[i]);
                    }
                    else
                    {
                        writef("%c", prebuf[i]);
                    }
                    /*writefln("%c", prebuf[i]);
                    if (buf_r > 4)
                        writefln("buf=%s", buf[buf_r-4..buf_r+4]);*/
                    auto chrlen = buf.mystride(buf_r);
                    if (chrlen != 1)
                    {
                        if (max_r <= buf_r+chrlen) 
                        {
                            buf[max_r..buf_r+chrlen] = ' ';
                            max_r = buf_r+chrlen;
                        }
                        std.algorithm.mutation.copy(buf[buf_r+chrlen..max_r], buf[buf_r+1..max_r+1-chrlen]);
                        max_r += 1-chrlen;
                    }
                    buf[buf_r] = prebuf[i];
                    /*if (buf_r > 4)
                        writefln("After buf=%s", buf[buf_r-4..buf_r+4]);*/
                    buf_r++;
                    if (buf_r > max_r) max_r = buf_r;
                    //writefln("ADD '%c': buf=%s", prebuf[i], buf[0..max_r]);
                    if (attrs_r >= attrs.length) attrs.length = attrs_r+1;
                    attrs[attrs_r] = cur_attr;
                    attrs_r++;
                }
                break;
            case StateEscape.WaitBracket:
                if (prebuf[i] == ']')
                    state = StateEscape.WaitNumberR;
                else if (prebuf[i] == '[')
                {
                    state = StateEscape.WaitCSI;
                    text = "";
                    numbers = [];
                }
                else
                {
                    writefln("UNKNOWN Escape Sequence \"ESC %c\"", prebuf[i]);
                    state = StateEscape.WaitEscape;
                }
                break;
            case StateEscape.WaitNumberR:
                if (r - i < 3) break;
                if (prebuf[i..i+2] == "0;")
                {
                    substate = 0;
                    state = StateEscape.WaitText;
                    text = "";
                    i++;
                }
                else if (prebuf[i..i+2] == "2;")
                {
                    substate = 2;
                    state = StateEscape.WaitText;
                    text = "";
                    i++;
                }
                else if (prebuf[i..i+2] == "4;")
                {
                    substate = 4;
                    state = StateEscape.WaitText;
                    text = "";
                    i++;
                }
                else if (prebuf[i..i+3] == "10;")
                {
                    substate = 10;
                    state = StateEscape.WaitText;
                    text = "";
                    i+=2;
                }
                else if (prebuf[i..i+3] == "46;")
                {
                    substate = 46;
                    state = StateEscape.WaitText;
                    text = "";
                    i+=2;
                }
                else if (prebuf[i..i+3] == "50;")
                {
                    substate = 50;
                    state = StateEscape.WaitText;
                    text = "";
                    i+=2;
                }
                else
                {
                    writefln("UNKNOWN Escape Sequence \"ESC ] %c%c\"", prebuf[i], prebuf[i+1]);
                    state = StateEscape.WaitEscape;
                }
                break;
            case StateEscape.WaitText:
                if (prebuf[i] == '\x07')
                {
                    switch(substate)
                    {
                        case 0:
                            /* Set icon name and window title to txt. */
                            break;
                        case 1:
                            /* Set icon name to txt. */
                            break;
                        case 2:
                            /* Set window title to txt. */
                            break;
                        case 4:
                            /* Set ANSI color num to txt. */
                            break;
                        case 10:
                            /* Set dynamic text color to txt.. */
                        case 46:
                            /* Change log file to name */
                        case 50:
                            /* Set font to fn. */
                        default:
                            assert(0);
                    }
                    state = StateEscape.WaitEscape;
                }
                else
                    text ~= prebuf[i];
                break;
            case StateEscape.WaitCSI:
                switch (prebuf[i])
                {
                    case '@':
                        /*Insert the indicated # of blank characters.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'A':
                        /*Move cursor up the indicated # of rows.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'B':
                        /*Move cursor down the indicated # of rows.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'C':
                        /*Move cursor right the indicated # of columns.*/
                        writefln("buf before Right: %s", buf[buf_r..max_r]);
                        buf_r += buf.mystride(buf_r);
                        if (buf_r > max_r)
                        {
                            buf[max_r..buf_r] = ' ';
                            max_r = buf_r;
                        }
                        attrs_r++;
                        state = StateEscape.WaitEscape;
                        writefln("buf after Right: %s", buf[buf_r..max_r]);
                        break;
                    case 'D':
                        /*Move cursor left the indicated # of columns.*/
                        if (buf_r > 0)
                            buf_r -= buf.strideBack(buf_r);
                        state = StateEscape.WaitEscape;
                        break;
                    case 'E':
                        /*Move cursor down the indicated # of rows, to column 1.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'F':
                        /*Move cursor up the indicated # of rows, to column 1.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'G':
                        /*Move cursor to indicated column in current row.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'H':
                        /*Move cursor to the indicated row, column (origin at 1,1).*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'J':
                        /*Erase display (default: from cursor to end of display).*/
                        /*
                           ESC [ 1 J: erase from start to cursor.
                           ESC [ 2 J: erase whole display.
                           ESC [ 3 J: erase whole display including scroll-back
                           prebuffer (since Linux 3.0).
                         */
                        state = StateEscape.WaitEscape;
                        break;
                    case 'K':
                        /*Erase line (default: from cursor to end of line).*/
                        /*
                           ESC [ 1 K: erase from start of line to cursor.
                           ESC [ 2 K: erase whole line.
                         */
                        if (max_r > buf.length) max_r = buf.length;
                        buf[buf_r..max_r] = ' ';
                        state = StateEscape.WaitEscape;
                        break;
                    case 'L':
                        /*Insert the indicated # of blank lines.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'M':
                        /*Delete the indicated # of lines.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'P':
                        /*Delete the indicated # of characters on current line.*/
                        int num = 1;
                        if (text != "") num = to!int(text);
                        //writefln("before buf='%s'", buf[buf_r..max_r]);
                        int bytes = 0;
                        for (auto j=0; j < num; j++)
                        {
                            bytes += buf.stride(buf_r+bytes);
                        }
                        std.algorithm.mutation.copy(buf[buf_r+bytes..max_r], buf[buf_r..max_r-bytes]);
                        std.algorithm.mutation.copy(attrs[attrs_r+num..$], attrs[attrs_r..$-num]);
                        max_r -= bytes;
                        attrs_r -= bytes;
                        //writefln("buf='%s'", buf[buf_r..max_r]);
                        state = StateEscape.WaitEscape;
                        break;
                    case 'X':
                        /*Erase the indicated # of characters on current line.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'a':
                        /*Move cursor right the indicated # of columns.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'c':
                        /*Answer ESC [ ? 6 c: "I am a VT102".*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'd':
                        /*Move cursor to the indicated row, current column.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'e':
                        /*Move cursor down the indicated # of rows.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'f':
                        /*Move cursor to the indicated row, column.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'g':
                        /*Without parameter: clear tab stop at current position.*/
                        /* ESC [ 3 g: delete all tab stops. */
                        state = StateEscape.WaitEscape;
                        break;
                    case 'h':
                        /*Set Mode (see below).*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'l':
                        /*Reset Mode (see below).*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'm':
                        /*Set attributes (see below).*/
                        if (text > "")
                            numbers ~= to!int(text);

                        if (numbers.length == 0) numbers ~= 0;
                        foreach(n; numbers)
                        {
                            switch (n)
                            {
                                case 0:
                                    cur_attr = Attr.Black<<4 | Attr.White;
                                    break;
                                case 1:
                                    cur_attr |= Attr.Bold;
                                    break;
                                case 2:
                                    cur_attr |= Attr.HalfBright;
                                    break;
                                case 4:
                                    cur_attr |= Attr.Underscore;
                                    break;
                                case 5:
                                    cur_attr |= Attr.Blink;
                                    break;
                                case 7:
                                    cur_attr = cur_attr & 0xFF00 | ((cur_attr & 0xF0) >> 4) | ((cur_attr & 0x0F) << 4);
                                    break;
                                case 10:
                                    break;
                                case 11:
                                    break;
                                case 12:
                                    break;
                                case 21:
                                    cur_attr &= ~Attr.HalfBright;
                                    break;
                                case 22:
                                    cur_attr &= ~Attr.HalfBright;
                                    break;
                                case 24:
                                    cur_attr &= ~Attr.Underscore;
                                    break;
                                case 25:
                                    cur_attr &= ~Attr.Blink;
                                    break;
                                case 27:
                                    cur_attr = cur_attr & 0xFF00 | ((cur_attr & 0xF0) >> 4) | ((cur_attr & 0x0F) << 4);
                                    break;
                                case 30:
                                    cur_attr = cur_attr & 0xFFF0 | Attr.Black;
                                    break;
                                case 31:
                                    cur_attr = cur_attr & 0xFFF0 | Attr.Red;
                                    break;
                                case 32:
                                    cur_attr = cur_attr & 0xFFF0 | Attr.Green;
                                    break;
                                case 33:
                                    cur_attr = cur_attr & 0xFFF0 | Attr.Brown;
                                    break;
                                case 34:
                                    cur_attr = cur_attr & 0xFFF0 | Attr.Blue;
                                    break;
                                case 35:
                                    cur_attr = cur_attr & 0xFFF0 | Attr.Magenta;
                                    break;
                                case 36:
                                    cur_attr = cur_attr & 0xFFF0 | Attr.Cyan;
                                    break;
                                case 37:
                                    cur_attr = cur_attr & 0xFFF0 | Attr.White;
                                    break;
                                case 38:
                                    cur_attr = cur_attr & 0xFFF0 | Attr.White | Attr.Underscore;
                                    break;
                                case 39:
                                    cur_attr = (cur_attr & 0xFFF0 | Attr.White) & ~Attr.Underscore;
                                    break;
                                case 40:
                                    cur_attr = cur_attr & 0xFF0F | (Attr.Black << 4);
                                    break;
                                case 41:
                                    cur_attr = cur_attr & 0xFF0F | (Attr.Red << 4);
                                    break;
                                case 42:
                                    cur_attr = cur_attr & 0xFF0F | (Attr.Green << 4);
                                    break;
                                case 43:
                                    cur_attr = cur_attr & 0xFF0F | (Attr.Brown << 4);
                                    break;
                                case 44:
                                    cur_attr = cur_attr & 0xFF0F | (Attr.Blue << 4);
                                    break;
                                case 45:
                                    cur_attr = cur_attr & 0xFF0F | (Attr.Magenta << 4);
                                    break;
                                case 46:
                                    cur_attr = cur_attr & 0xFF0F | (Attr.Cyan << 4);
                                    break;
                                case 47:
                                    cur_attr = cur_attr & 0xFF0F | (Attr.White << 4);
                                    break;
                                case 48:
                                    cur_attr = cur_attr & 0xFF0F | (Attr.Black << 4);
                                    break;
                                default:
                                    writefln("Unknown ECMA-48 SGR sequence %d", n);
                                    break;
                            }
                        }

                        state = StateEscape.WaitEscape;
                        break;
                    case 'n':
                        /*Status report (see below).*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'q':
                        /*Set keyboard LEDs.*/
                        /*ESC [ 0 q: clear all LEDs
                          ESC [ 1 q: set Scroll Lock LED
                          ESC [ 2 q: set Num Lock LED
                          ESC [ 3 q: set Caps Lock LED*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'r':
                        /*Set scrolling region; parameters are top and bottom row.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 's':
                        /*Save cursor location.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case 'u':
                        /*Restore cursor location.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case '`':
                        /*Move cursor to indicated column in current row.*/
                        state = StateEscape.WaitEscape;
                        break;
                    case '?':
                        break;
                    case '0':.. case '9':
                        text ~= prebuf[i];
                        break;
                    case ';':
                        numbers ~= to!int(text);
                        text = "";
                        break;
                    default:
                        writefln("UNKNOWN Escape Sequence \"ESC [ %c\"", prebuf[i]);
                        state = StateEscape.WaitEscape;
                        break;
                }
        }
    }

    return max_r;
}

private int
process_input(CMDGlobalState cgs, string cwd, ulong new_id, 
        ref ushort cur_attr,
        ref ushort[] attrs, ref size_t attrs_r,
        ref char[4096] buf, ref size_t buf_r, ref size_t max_r,
        ref ulong out_id, ref ulong out_id1, int fd, OutPipe pipe)
{
    //writefln("max_r=%d", max_r);
    ssize_t r;
    char[4096] prebuf;
    //writefln("buf.length-buf_r = %d", buf.length-buf_r);
    auto r1 = read(fd, prebuf.ptr, buf.length-buf_r-16);
    //writefln("READED: %s", prebuf[0..r1]);
    auto buf_length_was = buf.length-buf_r;

    assert(buf.length > buf_r);

    if (r1 > 0)
    {
        //writefln("r1=%d, buf.length-buf_r=%d", r1, buf.length-buf_r);

        //writefln("read r=%d", r);
        r = process_escape_sequences(cgs, cur_attr, attrs, attrs_r, buf, buf_r, max_r, prebuf, r1);

        //writefln("PROCESSED: %s", buf[0..r]);

        //writefln("r=%d buf=%s", r, buf[0..r]);
        //r = read(fd, buf[buf_r..$].ptr, buf[buf_r..$].length);
        Dbt key, data;
        if (out_id1 == 0)
        {
            out_id++;
            out_id1 = out_id;
        }
        //writefln("WRITED: out_id1 = %s", out_id1);
        //writefln("OUT: new_id=%s out_id=%s", new_id, out_id1);
        string ks = get_key_for_command_out(command_out_key(cwd, new_id, out_id1));
        key = ks;

        ssize_t split_r;
        if (r1 < buf_length_was) split_r = r;
        else
        {
            ssize_t sym = buf[r/2..$].lastIndexOf("\n");
            if (sym >= 0) split_r = r/2+sym+1;
            else
            {
                sym = buf[r/2..$].lastIndexOf(".");
                if (sym >= 0) split_r = r/2+sym+1;
                else
                {
                    sym = buf[r/2..$].lastIndexOf(" ");
                    if (sym >= 0) split_r = r/2+sym+1;
                    else
                    {
                        for (auto i = r-1; i >= 0; i--)
                        {
                            if ((buf[i] & 0b1000_0000) == 0 ||
                                    (buf[i] & 0b1100_0000) == 0b1100_0000)
                            {
                                split_r = i;
                                break;
                            }
                        }
                    }
                }
            }
        }

        ssize_t attrs_split_r = 0;
        for (auto i = 0; i < split_r; i+=buf.mystride(i))
        {
            attrs_split_r++;
        }
        if (attrs_split_r > attrs.length) attrs.length = attrs_split_r+1;

        //writefln("Write to DB buf=%s, pos = %s",buf[0..split_r], split_r > buf_r ? buf_r : split_r);
        //writefln("attrs=%s", attrs[0..attrs_split_r]);
        string ds = get_data_for_command_out(
                command_out_data(Clock.currTime().stdTime(), pipe, 
                    split_r > buf_r ? buf_r : split_r,
                    buf[0..split_r].idup(),
                    attrs[0..attrs_split_r]));
        data = ds;
        auto res = cgs.db_command_output.put(cgs.txn, &key, &data);
        if (res != 0)
        {
            throw new Exception("DB command out not written");
        }
        cgs.OIT++;

        //writefln("r=%d, split_r=%d, buf_r=%d", r, split_r, buf_r);
        /*writefln("%s: buf=%s r=%s", pipe, buf[0..split_r], split_r);
        if (pipe == OutPipe.STDERR)
        {
            for (auto i=0; i < split_r; i++)
            {
                writefln("char=%c code=%X (%d)", buf[i], buf[i], buf[i]);
            }
        }*/
        /*ssize_t a = ((split_r-50 >= 0) ? split_r-50 : 0);
        ssize_t b = ((split_r+50 <= r) ? split_r+50 : r);
        writefln("OUT: split \"%s\"~\"%s\" r=%s", 
                buf[a..split_r], 
                buf[split_r..b], 
                split_r);*/
        bool no_n = false;
        if (split_r < r)
        {
            buf[0..r - split_r] = buf[split_r..r];
            max_r = r - split_r;

            attrs[0..$ - attrs_split_r] = attrs[attrs_split_r..$];
            attrs.length -= attrs_split_r;

            if (split_r > buf_r)
            {
                buf_r = 0;
                attrs_r = 0;
            }
            else
            {
                buf_r -= split_r;
                attrs_r -= attrs_split_r;
            }
            /*ssize_t c = ((50 < r - split_r) ? 50 : r - split_r);
            writefln("buf: \"%s\"", buf[0..c]);*/
        }
        else
        {
            if (r < buf.length/2)
            {
                if (r > 0 && buf[r-1] != '\n')
                {
                    no_n = true;

                    //writefln("%s: Not ended with \\n line found: %s", pipe, buf[0..split_r]);
                }
            }

            if (!no_n)
            {
                buf_r = 0;
                max_r = 0;
                attrs_r = 0;
                attrs.length = 0;
            }
        }
        if (!no_n)
        {
                //writefln("%s: Ended with \\n line found: %s", pipe, buf[0..split_r]);
            out_id1 = 0;
        }

    }
    if (r1 < 0 && errno != EWOULDBLOCK)
    {
        //throw new Exception("read() error: " ~ fromStringz(strerror(errno)).idup());
        return 1;
    }
    if (r1 == 0) return 1;
    return 0;
}

private int
fork_command(CMDGlobalState cgs, string cwd, string command, Tid tid)
{
    cgs.recommit();

/*db_commands
cwd, id
    command, start, end, status*/

    ulong id = get_max_id_of_cwd(cgs, cwd);
    ulong new_id = id+1;
    if (id > 0)
    {
        new_id = id + 1000 - id%1000;
        //writefln("last_id=%s (%%1000=%s), new_id=%s", id, id%1000, new_id);
    }

    if (command[0] != '*' && command[0] != '+')
    {
        ulong replace_id = find_command_in_cwd(cgs, cwd, command);

        string ks = get_key_for_command(command_key(cwd, replace_id));
        Dbt key = ks;
        auto res = cgs.db_commands.del(cgs.txn, &key);

        delete_command_out(cgs, cwd, replace_id);
    }

    tid.send(thisTid, "command_id", new_id);

    Dbt key, data;
    string ks = get_key_for_command(command_key(cwd, new_id));
    key = ks;
    command_data cmd_data = command_data(command, 0, 0, -1);
    string ds = get_data_for_command(cmd_data);
    data = ds;

    auto res = cgs.db_commands.put(cgs.txn, &key, &data);
    if (res != 0)
    {
        throw new Exception("DB command not written");
    }

    Dbt key2, data2;
    string ks2 = get_key_for_command(command_key(cwd, id));
    key2 = ks;

    if (command[0] == '+' && id > 0)
    {
        do
        {
            res = cgs.db_commands.get(cgs.txn, &key2, &data2);
            if (res == 0)
            {
                string data2_string = data.to!(string);
                command_data cmd_data2;
                parse_data_for_command(data2_string, cmd_data2);
                if (cmd_data2.end > 0)
                {
                    if (cmd_data2.status != 0)
                    {
                        cmd_data.end = Clock.currTime().stdTime();
                        ds = get_data_for_command(cmd_data);
                        data = ds;

                        res = cgs.db_commands.put(cgs.txn, &key, &data);
                        if (res != 0)
                        {
                            throw new Exception("DB command not written");
                        }
                        cgs.OIT++;

                        return cmd_data2.status;
                    }
                    else
                    {
                        break;
                    }
                }
            }
            else
            {
                throw new Exception(format("Command with id %d not found", id));
            }

            cgs.commit;
            Thread.sleep( 200.msecs() );
            cgs.recommit;
        }
        while (true);
    }

/*db_command_output
cwd, command_id, out_id,
    time, stderr/stdout, output*/

    chdir(cwd);

    version(WithoutTTY)
    {
        auto cmd_pipes = pipeProcess(["bash", "-c", command], Redirect.stdout | Redirect.stderr | Redirect.stdin);
        auto pid = cmd_pipes.pid;

        auto fdstdout = cmd_pipes.stdout.fileno;
        auto fdstderr = cmd_pipes.stderr.fileno;
        auto fdstdin  = cmd_pipes.stdin.fileno;
        auto fdmax = max(fdstdout, fdstderr, fdstdin);
    }
    else
    {
        winsize ws;
        ws.ws_row = 25;
        ws.ws_col = 80;
        ws.ws_xpixel = 1024;
        ws.ws_ypixel = 768;

        if (!access("/bin/bash".toStringz(), X_OK) == 0)
            throw new Exception(text("Not an executable file: ", "/bin/bash"));

        int master;

        auto stderrPipe = pipe();

        auto pid = forkpty(&master, null, null, &ws);
        if (pid < 0)
        {
            throw new Exception("forkpty() error: " ~ fromStringz(strerror(errno)).idup());
        }
        else if ( pid == 0 ) // Child
        {
            stderrPipe.readEnd.close();
            dup2(stderrPipe.writeEnd.fileno, stderr.fileno);
            stderrPipe.writeEnd.close();
            execl("/bin/bash".toStringz(), "/bin/bash".toStringz(), "-c".toStringz(), command.toStringz(), null);
            writefln("execl() error: " ~ fromStringz(strerror(errno)).idup());
            assert(0);
        }
        //parent
        stderrPipe.writeEnd.close();

        File mfile;
        mfile.fdopen(master, "a+");
        scope(success) {
            mfile.close();
        }

        //auto pid = spawnProcess(["bash", "-c", command], sfile, sfile, stderrPipe.writeEnd); 

        auto fdstdout = master;
        auto fdstderr = stderrPipe.readEnd.fileno;
        auto fdstdin  = master;
        auto fdmax = max(fdstdout, fdstderr, fdstdin);
    }

    scope(success) {
        waitpid(pid, null, 0);
    }
    scope(failure) {
        kill(pid, SIGKILL);
        waitpid(pid, null, 0);
    }

    cmd_data.start = Clock.currTime().stdTime();
    ds = get_data_for_command(cmd_data);
    data = ds;

    res = cgs.db_commands.put(cgs.txn, &key, &data);
    if (res != 0)
    {
        throw new Exception("DB command not written");
    }

    cgs.commit();
    cgs.recommit();

    /*Make file descriptions NON_BLOCKING */
    set_non_block_mode(fdstdout);
    set_non_block_mode(fdstderr);
    set_non_block_mode(fdstdin);

    fd_set rfds;
    fd_set wfds;
    timeval tv;
    int retval;

    /* Wait up to 100ms seconds. */
    tv.tv_sec = 0;
    tv.tv_usec = 100_000;

    bool select_zero;
    bool terminated;
    int result = -1;
    ulong out_id = 0;
    char[4096] buf1;
    char[4096] buf2;
    size_t buf1_r;
    size_t buf2_r;
    size_t max1_r;
    size_t max2_r;
    ushort cur_attr1 = Attr.Black<<4 | Attr.White;
    ushort cur_attr2 = Attr.Black<<4 | Attr.White;
    ushort[] attrs1;
    ushort[] attrs2;
    size_t attrs1_r;
    size_t attrs2_r;
    ulong out_id1 = 0;
    ulong out_id2 = 0;
    bool stdin_closed = false;
    while(!cgs.finish)
    {
        cgs.recommit();
        if (select_zero)
        {
            int status;
            if ( waitpid(pid, &status, WNOHANG) )
            {
                cgs.commit();
                cgs.recommit();
                cmd_data.end = Clock.currTime().stdTime();
                cmd_data.status = status;
                result = status;
                ds = get_data_for_command(cmd_data);
                data = ds;

                res = cgs.db_commands.put(cgs.txn, &key, &data);
                if (res != 0)
                {
                    throw new Exception("DB command not written");
                }
                cgs.OIT++;
                writefln("NORMAL EXIT");
                break;
            }
        }

        select_zero = false;

        FD_ZERO(&rfds);
        FD_SET(fdstdout, &rfds);
        FD_SET(fdstderr, &rfds);

        if (!stdin_closed)
        {
            FD_ZERO(&wfds);
            FD_SET(fdstdin, &wfds);
        }

        int eof = 0;

        retval = select(fdmax+1, &rfds, stdin_closed ? null : &wfds, null, &tv);
        if (retval < 0)
        {
            if (errno != EINTR)
                throw new Exception("select() error: " ~ fromStringz(strerror(errno)).idup());
        }
        else if (retval > 0)
        {
            if (FD_ISSET(fdstdout, &rfds))
            {
                eof += process_input(cgs, cwd, new_id, 
                        cur_attr1,
                        attrs1, attrs1_r,
                        buf1, buf1_r, max1_r,
                        out_id, out_id1,
                        fdstdout, OutPipe.STDOUT);
            }
            if (FD_ISSET(fdstderr, &rfds))
            {
                eof += process_input(cgs, cwd, new_id, 
                        cur_attr2,
                        attrs2, attrs2_r,
                        buf2, buf2_r, max2_r,
                        out_id, out_id2,
                        fdstderr, OutPipe.STDERR);
            }
            if ( !stdin_closed && FD_ISSET(fdstdin, &wfds) )
            {
                receiveTimeout( 0.seconds, 
                        (string input) {
                            /*foreach (i; input)
                            {
                                writefln("INPUT: '%c' - %X (%d)", i, i, i);
                            }*/
                            if (input == "\x04") // Ctrl+D
                            {
                                writefln("Ctrl+D");
                                version(WithoutTTY)
                                {
                                    cmd_pipes.stdin.close();
                                    stdin_closed = true;
                                }
                                else
                                {
                                    core.sys.posix.unistd.write(fdstdin, input.ptr, input.length);
                                }
                            }
                            else
                            {
                                if (input == "\x03") // Ctrl+C
                                {
                                    writefln("Ctrl+C");
                                    kill(pid, SIGINT);
                                }
                                core.sys.posix.unistd.write(fdstdin, input.ptr, input.length);
                            }
                        }
                );
            }
        }
        else
        {
            select_zero = true;
        }

        if (eof >= 2) select_zero = true;

        receiveTimeout( 0.seconds, 
                (OwnerTerminated ot) {
                    writefln("Abort command due stopping parent");
                    kill(pid, SIGKILL);
                    cgs.finish = true;

                    cmd_data.end = Clock.currTime().stdTime();
                    cmd_data.status = -1;
                    string ds = get_data_for_command(cmd_data);
                    data = ds;

                    auto res = cgs.db_commands.put(cgs.txn, &key, &data);
                    if (res != 0)
                    {
                        throw new Exception("DB command not written");
                    }
                } );
    }
    return result;
}

private void
command(string cwd, string command, Tid tid)
{
    CMDGlobalState cgs = new CMDGlobalState();
    try {
        scope(exit)
        {
            destroy(cgs);
        }
        fork_command(cgs, cwd, command, tid);
        cgs.commit();
    } catch (shared(Throwable) exc) {
        send(tid, exc);
    }

    writefln("Finish command %s", command);
    send(tid, thisTid);
}

public int
run_command(GlobalState gs, string command)
{
    if (command == "") return -1;
    shared LsblkInfo[string] lsblk = to!(shared LsblkInfo[string])(gs.lsblk);
    shared CopyMapInfo[string] copy_map = cast(shared CopyMapInfo[string])(gs.copy_map);

    writefln("Start command %s", command);
    auto tid = spawn(&.command, gs.full_current_path, command, thisTid);
    gs.commands[tid] = command;
    return 0;
}

