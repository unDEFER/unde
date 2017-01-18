module unde.command_line.lib;

import unde.global_state;
import unde.path_mnt;
import unde.lib;
import unde.slash;
import unde.font;
import unde.keybar.lib;
import unde.command_line.db;
import unde.command_line.run;
import unde.command_line.delete_command;

import berkeleydb.all;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;

import core.exception;

import std.string;
import std.stdio;
import std.math;
import std.conv;
import std.utf;
import std.file;
import std.path;
import std.process;
import std.concurrency;
import std.algorithm.iteration;
import std.algorithm.sorting;
import core.sys.posix.signal;
import core.sys.posix.stdlib;

public ssize_t
get_position_by_chars(
        int x, int y, SDL_Rect[] chars, ssize_t p=0)
{
    if (chars.length == 0) return -1;
    ssize_t pos = chars.length/2;
    while (pos >= 0 && chars[pos].w == 0 && chars[pos].h == 0)
        pos--;
    if (pos < 0) return -1;

    if (y < chars[pos].y)
    {
        return get_position_by_chars(x, y, chars[0..pos], p);
    }
    else if (y > chars[pos].y + chars[pos].h)
    {
        return get_position_by_chars(x, y, chars[pos+1..$], p+pos+1);
    }
    else if (x < chars[pos].x)
    {
        return get_position_by_chars(x, y, chars[0..pos], p);
    }
    else if (x > chars[pos].x + chars[pos].w)
    {
        return get_position_by_chars(x, y, chars[pos+1..$], p+pos+1);
    }
    else
    {
        return p+pos;
    }
}

private void
fix_bottom_line(GlobalState gs)
{
    //writefln("Fix Bottom Line");
    with (gs.command_line)
    {
        nav_cmd_id = 0;
        nav_out_id = 0;
        nav_skip_cmd_id = 0;

        cwd = gs.current_path;

        Dbc cursor = gs.db_commands.cursor(null, 0);
        scope(exit) cursor.close();

        Dbt key, data;

        ulong id = mouse.cmd_id > 0 ? mouse.cmd_id : 1;
        string ks = get_key_for_command(command_key(cwd, id));
        //writefln("SET RANGE: %s (cwd=%s, id=%X)", ks, cwd, id);
        key = ks;
        id = find_next_by_key(cursor, 0, id, key, data);

        //writefln("mouse.cmd_id=%s", mouse.cmd_id);
        if (id != 0)
        {
            bool cmd_next_stop;
            /* The bottom command found */
            long y_off = neg_y;
            //writefln("y=%s, y_off=%s", y, y_off);
            do
            {
                string key_string = key.to!(string);
                command_key cmd_key;
                parse_key_for_command(key_string, cmd_key);
                if (cwd != cmd_key.cwd)
                {
                    id = 0;
                    break;
                }
                else
                {
                    //writefln("cmd_id=%s", id);
                    id = cmd_key.id;
                    string data_string = data.to!(string);
                    command_data cmd_data;
                    parse_data_for_command(data_string, cmd_data);

                    if (search_mode && cmd_data.command.indexOf(search) < 0)
                        continue;

                    if (cmd_next_stop)
                    {
                        cmd_next_stop = false;
                        nav_skip_cmd_id = cmd_key.id;
                        //writefln("nav_skip_cmd_id=%d", nav_skip_cmd_id);
                        if (fontsize < 5)
                        {
                            int line_height9 = cast(int)(round(SQRT2^^fontsize)*1.2);
                            y = y_off - gs.screen.h + line_height9*3 + 8;
                            //writefln("CMD y = %d", y);
                        }
                        break;
                    }

                    int line_height = cast(int)(round(SQRT2^^9)*1.2);
                    auto rt = gs.text_viewer.font.get_size_of_line(cmd_data.command, 
                            9, gs.screen.w-80, line_height, SDL_Color(0xFF,0x00,0xFF,0xFF));

                    int lines = rt.h / line_height;

                    auto rect = SDL_Rect();
                    rect.x = 40;
                    rect.y = cast(int)(y_off + 4);
                    rect.w = rt.w;
                    rect.h = rt.h;

                    if (cmd_key.id == mouse.cmd_id &&
                            (0 == mouse.out_id || fontsize < 5))
                    {
                        int ry = cast(int)(gs.mouse_screen_y - mouse_rel_y*rect.h);
                        y_off = ry - 4 + neg_y;
                        //writefln("on mouse cmd_id=%d ry-4=%d y_off=%s", mouse.cmd_id, ry-4, y_off);
                    }

                    //writefln("CMD id=%s %s, rect.y = %s > %s", cmd_key.id, cmd_data.command, rect.y, gs.screen.h + line_height);
                    if (rect.y >= gs.screen.h + line_height && nav_skip_cmd_id == 0)
                    {
                        cmd_next_stop = true;
                    }
                    if (nav_skip_cmd_id > 0 && (nav_cmd_id > 0 || fontsize < 5) )
                        break;

                    y_off += line_height*lines;

                    /* Loop through all commands */
                    if (fontsize >= 5 && !search_mode)
                    {
                        /* Try to find last output for command */
                        Dbc cursor2 = gs.db_command_output.cursor(null, 0);
                        scope(exit) cursor2.close();

                        Dbt key2, data2;
                        ulong out_id = cmd_key.id == mouse.cmd_id && mouse.out_id > 0 ? mouse.out_id : 1;
                        ks = get_key_for_command_out(command_out_key(cwd, cmd_key.id, out_id));
                        //writefln("SET RANGE: %s (cwd=%s, id=%X)", ks, cwd, id);
                        key2 = ks;
                        out_id = find_next_by_key(cursor2, 0, out_id, key2, data2);

                        //writefln("mouse.out_id=%s", mouse.out_id);
                        if (out_id > 0)
                        {
                            bool next_stop = false;
                            /* The last output found */
                            do
                            {
                                /* Loop through all outputs */
                                string key_string2 = key2.to!(string);
                                command_out_key cmd_key2;
                                parse_key_for_command_out(key_string2, cmd_key2);
                                //writefln("cmd_id=%s, out_id=%s", cmd_key2.cmd_id, cmd_key2.out_id);
                                if (cmd_key.id != cmd_key2.cmd_id || cwd != cmd_key2.cwd)
                                {
                                    out_id = 0;
                                    break;
                                }
                                else
                                {
                                    if (next_stop)
                                    {
                                        nav_cmd_id = cmd_key2.cmd_id;
                                        nav_out_id = cmd_key2.out_id;
                                        //writefln("nav_cmd_id=%s, nav_out_id=%s", nav_cmd_id, nav_out_id);
                                        next_stop=false;

                                        int line_height9 = cast(int)(round(SQRT2^^fontsize)*1.2);
                                        y = y_off - gs.screen.h + line_height9*3 + 8;
                                        //writefln("OUT y = %d", y);
                                        break;
                                    }

                                    //writefln("out_id=%s", cmd_key2.out_id);
                                    string data_string2 = data2.to!(string);
                                    command_out_data cmd_data2;
                                    parse_data_for_command_out(data_string2, cmd_data2);

                                    auto color = SDL_Color(0xFF,0xFF,0xFF,0xFF);
                                    if (cmd_data2.pipe == OutPipe.STDERR)
                                    {
                                        color = SDL_Color(0xFF,0x80,0x80,0xFF);
                                    }

                                    line_height = cast(int)(round(SQRT2^^fontsize)*1.2);

                                    final switch(cmd_data2.vers)
                                    {
                                        case CommandsOutVersion.Simple:
                                            rt = gs.text_viewer.font.get_size_of_line(cmd_data2.output, 
                                                    fontsize, gs.screen.w-80, line_height, color);

                                            lines = rt.h / line_height - 1;
                                            if (cmd_data2.output.length > 0 && cmd_data2.output[$-1] != '\n') lines++;
                                            break;

                                        case CommandsOutVersion.Screen:
                                            rt = gs.text_viewer.font.get_size_of_line(cmd_data2.cols,
                                                    cmd_data2.rows, fontsize, color);
                                            lines = cmd_data2.rows;
                                            break;
                                    }


                                    rect = SDL_Rect();
                                    rect.x = 40;
                                    rect.y = cast(int)(y_off + 4);
                                    rect.w = rt.w;
                                    rect.h = rt.h;

                                    if (cmd_key2.cmd_id == mouse.cmd_id &&
                                            cmd_key2.out_id == mouse.out_id)
                                    {
                                        int ry = cast(int)(gs.mouse_screen_y - mouse_rel_y*rect.h);
                                        y_off = ry - 4 + neg_y;
                                        //writefln("on mouse out mouse.cmd_id=%s, mouse.out_id=%d", mouse.cmd_id, mouse.out_id);
                                        //writefln("on mouse out ry-4=%d y_off=%s", ry-4, y_off);
                                    }

                                    //writefln("OUT cmd_key2.cmd_id=%s, out_id=%s %s, rect.y = %s > %s", cmd_key2.cmd_id, cmd_key2.out_id, cmd_data2.output, rect.y, gs.screen.h + line_height);
                                    if (rect.y > gs.screen.h + line_height)
                                    {
                                        next_stop = true;
                                        cmd_next_stop = true;
                                    }

                                    y_off += line_height*lines;
                                }
                            }
                            while (cursor2.get(&key2, &data2, DB_NEXT) == 0);

                            if (next_stop)
                            {
                                nav_cmd_id = cmd_key.id;
                                nav_out_id = 0;

                                int line_height9 = cast(int)(round(SQRT2^^fontsize)*1.2);
                                y = y_off - gs.screen.h + line_height9*3 + 8;
                                //writefln("OUT y = %d", y);
                            }
                        }
                    }
                }
            }
            while (cursor.get(&key, &data, DB_NEXT) == 0);

            if (cmd_next_stop)
            {
                nav_skip_cmd_id = 0;
                if (fontsize < 5)
                {
                    int line_height9 = cast(int)(round(SQRT2^^fontsize)*1.2);
                    y = y_off - gs.screen.h + line_height9*3 + 8;
                    //writefln("CMD y = %d", y);
                }
            }
        }
        neg_y = 0;
    }
}

package void
selection_to_buffer(GlobalState gs)
{
    with (gs.command_line)
    {
        if (start_selection.cmd_id == 0 || end_selection.cmd_id == 0)
            return;

        string selection = "";

        cwd = gs.current_path;

        Dbc cursor = gs.db_commands.cursor(null, 0);
        scope(exit) cursor.close();

        Dbt key, data;

        ulong id = start_selection.cmd_id;
        string ks = get_key_for_command(command_key(cwd, id));
        //writefln("SET RANGE: %s (cwd=%s, id=%d)", ks, cwd, id);
        key = ks;
        id = find_next_by_key(cursor, 0, id, key, data);

        //writefln("mouse.cmd_id=%s", mouse.cmd_id);
        if (id != 0)
        {
            bool cmd_next_stop;
            /* The bottom command found */
            long y_off = neg_y;
            //writefln("y=%s, y_off=%s", y, y_off);
            do
            {
                string key_string = key.to!(string);
                command_key cmd_key;
                parse_key_for_command(key_string, cmd_key);
                if (cwd != cmd_key.cwd)
                {
                    id = 0;
                    break;
                }
                else
                {
                    //writefln("cmd_id=%s", id);
                    id = cmd_key.id;
                    string data_string = data.to!(string);
                    command_data cmd_data;
                    parse_data_for_command(data_string, cmd_data);

                    ssize_t start_pos, end_pos;
                    get_start_end_pos(cmd_key.id,
                            0,
                            start_selection, 
                            end_selection,
                            start_pos, end_pos);
                    if (start_pos >= 0)
                    {
                        //writefln("start_pos=%s end_pos=%s", start_pos, end_pos);
                        if (start_pos == 0)
                            selection ~= "$ ";
                        if (end_pos+1 >= cmd_data.command.length) end_pos = cmd_data.command.length-1;
                        selection ~= cmd_data.command[start_pos..end_pos+1];
                        if (end_pos+1 == cmd_data.command.length)
                            selection ~= "\n";
                    }
                    else if ( !(start_selection.cmd_id == cmd_key.id && start_selection.out_id > 0) )
                    {
                        break;
                    }
                
                    /* Try to find last output for command */
                    Dbc cursor2 = gs.db_command_output.cursor(null, 0);
                    scope(exit) cursor2.close();

                    Dbt key2, data2;
                    ulong out_id = cmd_key.id == start_selection.cmd_id && 
                        start_selection.out_id != 0 ? start_selection.out_id : 1;
                    ks = get_key_for_command_out(command_out_key(cwd, cmd_key.id, out_id));
                    //writefln("SET RANGE: %s (cwd=%s, key_id=%d, out_id=%s)", ks, cwd, cmd_key.id, out_id);
                    key2 = ks;
                    out_id = find_next_by_key(cursor2, 0, out_id, key2, data2);

                    //writefln("mouse.out_id=%s", mouse.out_id);
                    if (out_id > 0)
                    {
                        do
                        {
                            /* Loop through all outputs */
                            string key_string2 = key2.to!(string);
                            command_out_key cmd_key2;
                            parse_key_for_command_out(key_string2, cmd_key2);
                            //writefln("cmd_id=%s, out_id=%s", cmd_key2.cmd_id, cmd_key2.out_id);
                            if (cmd_key.id != cmd_key2.cmd_id || cwd != cmd_key2.cwd)
                            {
                                out_id = 0;
                                break;
                            }
                            else
                            {
                                //writefln("out_id=%s", cmd_key2.out_id);
                                string data_string2 = data2.to!(string);
                                command_out_data cmd_data2;
                                parse_data_for_command_out(data_string2, cmd_data2);

                                get_start_end_pos(cmd_key2.cmd_id,
                                        cmd_key2.out_id,
                                        start_selection, 
                                        end_selection,
                                        start_pos, end_pos);

                                if (start_pos < 0) break;
                                if (end_pos+1 >= cmd_data2.output.length) end_pos = cmd_data2.output.length-1;

                                final switch(cmd_data2.vers)
                                {
                                    case CommandsOutVersion.Simple:
                                        selection ~= cmd_data2.output[start_pos..end_pos+1];
                                        break;
                                    case CommandsOutVersion.Screen:
                                        selection ~= to!string(cmd_data2.screen[start_pos..end_pos+1]);
                                        break;
                                }
                            }
                        }
                        while (cursor2.get(&key2, &data2, DB_NEXT) == 0);
                    }
                }
            }
            while (cursor.get(&key, &data, DB_NEXT) == 0);
        }
        //writefln("SELECTION:\n%s", selection);
        SDL_SetClipboardText(selection.toStringz());
    }
}

void cmd_selection_to_buffer(GlobalState gs)
{
    with (gs.command_line)
    {
        string selection = command[cmd_start_selection..cmd_end_selection + command.mystride(cmd_end_selection)];
        SDL_SetClipboardText(selection.toStringz());
    }
}

void shift_selected(GlobalState gs)
{
    with (gs.command_line)
    {
        if (cmd_start_selection < 0 || cmd_end_selection < 0) return;
        if (cmd_end_selection > command.length)
            cmd_end_selection = command.length - 1 - command.strideBack(command.length - 1);
        string converted;
        for (ssize_t i=cmd_start_selection; i < cmd_end_selection + command.mystride(cmd_end_selection); i+=command.stride(i))
        {
            string chr = command[i..i+command.stride(i)];
            if (chr.toLower() == chr)
            {
                chr = chr.toUpper();
            }
            else
                chr = chr.toLower();

            converted ~= chr;
        }

        command = command[0..cmd_start_selection] ~ converted ~ command[cmd_end_selection + command.mystride(cmd_end_selection)..$];
    }
}

bool find_chr(string chr, string[][3] *letters, ref ButtonPos buttonpos)
{
    for (buttonpos.i = 0; buttonpos.i < 3; buttonpos.i++)
    {
        for (buttonpos.pos = 0; buttonpos.pos <
                (*letters)[buttonpos.i].length; buttonpos.pos++)
        {
            if ((*letters)[buttonpos.i][buttonpos.pos] == chr)
                return true;
        }
    }
    return false;
}

void change_layout_selected(GlobalState gs)
{
    with (gs.command_line)
    {
        if (cmd_start_selection < 0 || cmd_end_selection < 0) return;
        if (cmd_end_selection > command.length)
            cmd_end_selection = command.length - 1 - command.strideBack(command.length - 1);
        ssize_t end_selection = cmd_end_selection + command.mystride(cmd_end_selection);
        string converted;
        for (ssize_t i=cmd_start_selection; i < end_selection; i+=command.stride(i))
        {
            string chr = command[i..i+command.stride(i)];

            ssize_t prev_mode = gs.keybar.mode-1;
            if (prev_mode < 0)
                prev_mode = gs.keybar.layout_modes.length - 1;

            ButtonPos buttonpos;
            auto letters = &gs.keybar.layout_modes[prev_mode].letters;
            if (find_chr(chr, letters, buttonpos))
            {
                letters = &gs.keybar.layout_modes[gs.keybar.mode].letters;
                chr = (*letters)[buttonpos.i][buttonpos.pos];
            }
            letters = &gs.keybar.layout_modes[prev_mode].letters_shift;
            if (find_chr(chr, letters, buttonpos))
            {
                letters = &gs.keybar.layout_modes[gs.keybar.mode].letters_shift;
                chr = (*letters)[buttonpos.i][buttonpos.pos];
            }
            letters = &gs.keybar.layout_modes[prev_mode].letters_altgr;
            if (find_chr(chr, letters, buttonpos))
            {
                letters = &gs.keybar.layout_modes[gs.keybar.mode].letters_altgr;
                chr = (*letters)[buttonpos.i][buttonpos.pos];
            }
            letters = &gs.keybar.layout_modes[prev_mode].letters_shift_altgr;
            if (find_chr(chr, letters, buttonpos))
            {
                letters = &gs.keybar.layout_modes[gs.keybar.mode].letters_shift_altgr;
                chr = (*letters)[buttonpos.i][buttonpos.pos];
            }

            converted ~= chr;
        }

        command = command[0..cmd_start_selection] ~ converted ~ command[end_selection..$];
        cmd_end_selection = cmd_start_selection + converted.length;
        cmd_end_selection -= command.strideBack(cmd_end_selection);
        if (pos > cmd_start_selection) pos = command.length;
    }
}


bool is_command_position(GlobalState gs, string command, ssize_t pos)
{
    for (ssize_t i = pos-1; i >= -1; i--)
    {
        if (i == -1 || command[i] == '&' || command[i] == '|')
        {
            return true;
        }
        else if (command[i] != ' ' && command[i] != '\t')
        {
            return false;
        }
    }
    return true;
}

enum StringStatus{
    Normal,
    Quote,
    DblQuote,
    BackApostrophe
}

void uniq(ref string[] strings)
{
    for (ssize_t i = 0; i < strings.length-1; i++)
    {
        if (strings[i] == strings[i+1])
        {
            strings = strings[0..i] ~ strings[i+1..$];
            i--;
        }
    }
}

ssize_t find_in_sorted(string[] hashstock, string needle, ssize_t pos = 0)
{
    if (hashstock.length == 0 )
        return pos;

    if ( needle == hashstock[$/2] )
    {
        return pos+hashstock.length/2;
    }
    else if ( needle < hashstock[$/2] )
    {
        return find_in_sorted(hashstock[0..$/2], needle, pos);
    }
    else
    {
        return find_in_sorted(hashstock[$/2+1..$], needle, pos+hashstock.length/2+1);
    }
}

string remove_backslashes(string str)
{
    bool prevslash;
    for (ssize_t i = 0; i < str.length; i += str.stride(i))
    {
        string chr = str[i..i+str.stride(i)];
        if (chr == "\\" && !prevslash)
        {
            str = str[0..i] ~ str[i+chr.length..$];
            if (i >= str.length) break;
            prevslash = true;
        }
        if (chr != "\\")
            prevslash = false;
    }
    return str;
}

string backslashes(string str, StringStatus status)
{
    string[] chars_needed_backslashes = [];
    final switch (status)
    {
        case StringStatus.Quote:
            break;
        case StringStatus.DblQuote:
            chars_needed_backslashes = [`"`, "`"];
            break;
        case StringStatus.BackApostrophe:
            chars_needed_backslashes = [`"`, "`", "`", "`"];
            break;
        case StringStatus.Normal:
            chars_needed_backslashes = [`"`, "`", "'", " "];
            break;
    }

    for (ssize_t i = 0; i < str.length; i += str.stride(i))
    {
        string chr = str[i..i+str.stride(i)];
        foreach (cnb; chars_needed_backslashes)
        {
            if (chr == cnb)
            {
                str = str[0..i] ~ `\` ~ str[i..$];
                i++;
            }
        }
    }
    return str;
}

string common_part(string a, string b)
{
    string res;
    for (ssize_t i = 0; i < a.length && i < b.length; i+=a.stride(i))
    {
        string chr1 = a[i..i+a.stride(i)];
        string chr2 = b[i..i+b.stride(i)];
        if (chr1 == chr2)
            res ~= chr1;
        else break;
    }
    return res;
}

string autocomplete(GlobalState gs, string command, bool is_command, StringStatus status)
{
    string[] completions;
    if (is_command && command.indexOf("/") < 0)
    {
        string path = environment["PATH"];
        auto paths = splitter(path, pathSeparator);

        string[] binaries = [];
        foreach(p; paths)
        {
            p = p.expandTilde();
            try
            {
                foreach (string name; dirEntries(p, SpanMode.shallow))
                {
                    binaries ~= name[name.lastIndexOf("/")+1..$];
                }
            }
            catch (FileException exp)
            {
            }
        }

        binaries ~= ["cd", "select", "go", "open", "mopen"];
        sort!("a < b")(binaries);
        uniq(binaries);
        completions = binaries;
    }
    else
    {
        string dir;
        dir = buildNormalizedPath(absolutePath(expandTilde(command), gs.full_current_path));
        if (command.length > 0 && command[$-1] == '/') dir ~= "/";
        dir = dir[0..dir.lastIndexOf("/")+1];

        string[] files = [];
        if (gs.selection_hash.length > 0)
            files ~= "${SELECTED[@]}";
        //writefln("dir = %s, is null = %s, %s", dir, dir is null, dir.length);
        if (dir !is null)
        {
            try{
                if (!dir.isDir()) dir = dir[0..dir.lastIndexOf("/")];
                foreach (string name; dirEntries(dir, SpanMode.shallow))
                {
                    files ~= name[name.lastIndexOf("/")+1..$];
                }

                command = command[command.lastIndexOf("/")+1..$];

                sort!("a < b")(files);
                completions = files;
            } catch (FileException exp)
            {
            }
        }
    }

    final switch (status)
    {
        case StringStatus.Quote:
            break;
        case StringStatus.DblQuote:
            command = remove_backslashes(command);
            break;
        case StringStatus.BackApostrophe:
            command = remove_backslashes(command);
            break;
        case StringStatus.Normal:
            command = remove_backslashes(command);
            break;
    }

    string[] next_chars = [];
    ssize_t pos = find_in_sorted(completions, command);
    ssize_t i;
    for (i=pos; i < completions.length; i++)
    {
        if ( completions[i].startsWith(command) )
        {
            if ( completions[i].length <= command.length )
            {
                next_chars ~= "✔";
                continue;
            }
            if (next_chars.length == 0 || next_chars[$-1] != completions[i][command.length..command.length+completions[i].stride(command.length)])
                next_chars ~= completions[i][command.length..command.length+completions[i].stride(command.length)];
        }
        else
            break;
    }

    if (i == pos)
        return "";
    else if (i == pos+1)
        return "1"~completions[pos][command.length..$].backslashes(status);
    else if (next_chars.length == 1)
    {
        string common = completions[pos];
        for (ssize_t j = pos+1; j < i; j++)
            common = common_part(common, completions[j]);
        return "1"~common[command.length..$].backslashes(status);
    }
    else if (i - pos <= 5)
    {
        string result = "";
        for (ssize_t j = pos; j < i; j++)
        {
            result ~= completions[j] ~ " ";
        }
        return "2"~result;
    }
    else
    {
        string result = "";
        foreach (chr; next_chars)
        {
            result ~= chr ~ " ";
        }
        return "2"~result;
    }
}

string autocomplete(GlobalState gs, string command)
{
    static string prev_command;
    static string prev_result;
    if (prev_command == command)
        return prev_result;

    prev_command = command;

    if (command.length > 0 && (command[0] == '+' || command[0] == '*'))
        command = command[1..$];

    ssize_t dbl_quotes = command.count("\"");
    ssize_t esc_dbl_quotes = command.count("\\\"");
    dbl_quotes -= esc_dbl_quotes;

    ssize_t back_apostrophes = command.count("`");
    ssize_t esc_back_apostrophes = command.count("\\`");
    back_apostrophes -= esc_back_apostrophes;

    ssize_t quotes = command.count("'");

    ssize_t quote;
    if (quotes%2 == 1)
    {
        quote = command.lastIndexOf("'");
    }

    ssize_t dbl_quote;
    if (dbl_quotes%2 == 1)
    {
        dbl_quote = command.lastIndexOf("\"");
        while (dbl_quote > 0 && command[dbl_quote-1] == '\\')
        {
            dbl_quote = command[0..dbl_quote].lastIndexOf("`");
        }
    }

    ssize_t back_apostrophe;
    if (back_apostrophes%2 == 1)
    {
        back_apostrophe = command.lastIndexOf("`");
        while (back_apostrophe > 0 && command[back_apostrophe-1] == '\\')
        {
            back_apostrophe = command[0..back_apostrophe].lastIndexOf("`");
        }
    }

    bool is_command;
    StringStatus string_status;
    ssize_t pos;
    if (quote > dbl_quote && quote > back_apostrophe)
    {
        is_command = is_command_position(gs, command, quote);
        pos = quote+1;
        string_status = StringStatus.Quote;
    }
    else if (dbl_quote > quote && dbl_quote > back_apostrophe)
    {
        is_command = is_command_position(gs, command, dbl_quote);
        pos = dbl_quote+1;
        string_status = StringStatus.DblQuote;
    }
    else 
    {
        if (back_apostrophe > quote && back_apostrophe > dbl_quote)
        {
            command = command[dbl_quote+1..$];
        }

        ssize_t space = command.lastIndexOf(" ");
        while ( space > 0 && command[space-1] == '\\')
        {
            space = command[0..space].lastIndexOf(" ");
        }
        is_command = is_command_position(gs, command, space);

        pos = space+1;
        if (back_apostrophe > quote && back_apostrophe > dbl_quote)
        {
            string_status = StringStatus.BackApostrophe;
        }
        else
        {
            string_status = StringStatus.Normal;
        }
    }

    prev_result = autocomplete(gs, command[pos..$], is_command, string_status);
    return prev_result;
}

private void
get_start_end_pos(in ulong cmd_id,
        in ulong out_id,
        in CmdOutPos start_selection, 
        in CmdOutPos end_selection,
        out ssize_t start_pos, out ssize_t end_pos)
{
    if (cmd_id < start_selection.cmd_id ||
            cmd_id == start_selection.cmd_id &&
            out_id < start_selection.out_id ||
            cmd_id > end_selection.cmd_id ||
            cmd_id == end_selection.cmd_id &&
            out_id > end_selection.out_id)
    {
        start_pos = -1;
        end_pos = -1;
        return;
    }

    if (cmd_id > start_selection.cmd_id ||
            cmd_id == start_selection.cmd_id &&
            out_id > start_selection.out_id)
    {
        start_pos = 0;
    }

    if ( cmd_id == start_selection.cmd_id &&
            out_id == start_selection.out_id)
    {
        start_pos = start_selection.pos;
    }

    if (cmd_id < end_selection.cmd_id ||
            cmd_id == end_selection.cmd_id &&
            out_id< end_selection.cmd_id)
    {
        end_pos = ssize_t.max;
    }

    if ( cmd_id == end_selection.cmd_id &&
            out_id == end_selection.out_id)
    {
        end_pos = end_selection.pos;
        if (end_pos == -1)
            end_pos = ssize_t.max;
    }
}

void
draw_command_line(GlobalState gs)
{
    with (gs.command_line)
    {
        if (SDL_GetTicks() - last_redraw > 200)
        {
            on_click = null;

            /* Setup texture render target */
            auto old_texture = SDL_GetRenderTarget(gs.renderer);
            int r = SDL_SetRenderTarget(gs.renderer, texture);
            if (r < 0)
            {
                throw new Exception(format("Error while set render target text_viewer.texture: %s",
                            fromStringz(SDL_GetError()) ));
            }

            SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);
            r = SDL_SetRenderDrawColor(gs.renderer, 0, 0, 0, 0);
            if (r < 0)
            {
                writefln("Can't SDL_SetRenderDrawColor: %s",
                        to!string(SDL_GetError()));
            }
redraw:
            r = SDL_RenderClear(gs.renderer);
            if (r < 0)
            {
                throw new Exception(format("Error while clear renderer: %s",
                            fromStringz(SDL_GetError()) ));
            }

            /* If terminal */
            if (gs.command_line.terminal)
            {
                if (font_changed || neg_y < 0)
                {
                    fix_bottom_line(gs);
                    font_changed = false;
                }

                /* Background */
                r = SDL_RenderCopy(gs.renderer, gs.texture_black, null, null);
                if (r < 0)
                {
                    writefln( "draw_command_line(), 1: Error while render copy: %s",
                            SDL_GetError().to!string() );
                }

                with (gs.command_line)
                {
                    cwd = gs.current_path;
                    Dbc cursor = gs.db_commands.cursor(null, 0);
                    scope(exit) cursor.close();

                    /* Try to find bottom command in commands history */
                    bool first_cmd_or_out = true;

                    //writefln("nav_skip_cmd_id=%s", nav_skip_cmd_id);
                    Dbt key, data;
                    //writefln("Find prev nav_skip_cmd_id=%d", nav_skip_cmd_id);
                    ulong id = find_prev_command(cursor, cwd, nav_skip_cmd_id,
                            key, data);

                    if (id != 0)
                    {
                        /* The bottom command found */
                        int line_height9 = cast(int)(round(SQRT2^^fontsize)*1.2);
                        long y_off = y + gs.screen.h - line_height9*3 - 8;
                        //writefln("y=%s, y_off=%s", y, y_off);
                        do
                        {
                            /* Loop through all commands */
                            string key_string = key.to!(string);
                            command_key cmd_key;
                            parse_key_for_command(key_string, cmd_key);
                            if (cwd != cmd_key.cwd)
                            {
                                id = 0;
                                break;
                            }
                            else
                            {
                    //writefln("cmd_id=%s found", cmd_key.id);
                                if (fontsize >= 5 && !search_mode)
                                {
                                    /* Try to find last output for command */
                                    Dbc cursor2 = gs.db_command_output.cursor(null, 0);
                                    scope(exit) cursor2.close();

                                    Dbt key2, data2;
                                    ulong out_id = cmd_key.id == nav_cmd_id ? nav_out_id : 0;
                                    out_id = find_prev_command_out(cursor2, cwd, cmd_key.id, out_id, key2, data2);
                                    bool first_out = true;

                                    if (out_id > 0)
                                    {
                                        /* The last output found */
                                        do
                                        {
                                            /* Loop through all outputs */
                                            string key_string2 = key2.to!(string);
                                            command_out_key cmd_key2;
                                            parse_key_for_command_out(key_string2, cmd_key2);
                                            //writefln("cmd_id=%s, out_id=%s", cmd_key2.cmd_id, cmd_key2.out_id);
                                            if (cmd_key.id != cmd_key2.cmd_id)
                                            {
                                                out_id = 0;
                                                break;
                                            }
                                            else
                                            {
                                                string data_string2 = data2.to!(string);
                                                command_out_data cmd_data2;
                                                parse_data_for_command_out(data_string2, cmd_data2);

                                                auto color = SDL_Color(0xFF,0xFF,0xFF,0xFF);
                                                if (cmd_data2.pipe == OutPipe.STDERR)
                                                {
                                                    color = SDL_Color(0xFF,0x80,0x80,0xFF);
                                                }
                                                int line_height = cast(int)(round(SQRT2^^fontsize)*1.2);

                                                auto rect = SDL_Rect();
                                                SDL_Rect rt;
                                                Texture_Tick *tt;
                                                final switch(cmd_data2.vers)
                                                {
                                                    case CommandsOutVersion.Simple:
                                                        //writefln("out_id=%s  cmd_data2.output=%s", cmd_key2.out_id, cmd_data2.output);
                                                        rt = gs.text_viewer.font.get_size_of_line(cmd_data2.output, 
                                                                fontsize, gs.screen.w-80, line_height, color);

                                                        int lines = rt.h / line_height - 1;
                                                        if (cmd_data2.output.length > 0 && cmd_data2.output[$-1] != '\n') lines++;
                                                        y_off -= line_height*lines;

                                                        auto i = 0;
                                                        rect.x = 40;
                                                        rect.y = cast(int)(y_off + 4 + line_height*i);
                                                        rect.w = rt.w;
                                                        rect.h = rt.h;

                                                        if (rect.y < gs.screen.h && rect.y+rect.h > 0)
                                                        {
                                                            /* Selection */
                                                            ssize_t start_pos, end_pos;
                                                            get_start_end_pos(cmd_key2.cmd_id,
                                                                    cmd_key2.out_id,
                                                                    start_selection, 
                                                                    end_selection,
                                                                    start_pos, end_pos);

                                                            tt = gs.text_viewer.font.get_line_from_cache(cmd_data2.output, 
                                                                    fontsize, gs.screen.w-80, line_height, color,
                                                                    cmd_data2.attrs, start_pos, end_pos);
                                                            if (!tt && !tt.texture)
                                                            {
                                                                throw new Exception("Can't create text_surface: "~
                                                                        to!string(TTF_GetError()));
                                                            }
                                                            //assert(rt.w == tt.w && rt.h == tt.h, format("rt.w=%d, tt.w=%d, rt.h=%d, tt.h=%d",
                                                            //            rt.w, tt.w, rt.h, tt.h));

                                                            r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
                                                            if (r < 0)
                                                            {
                                                                writefln(
                                                                        "draw_command_line(), 2: Error while render copy: %s", 
                                                                        SDL_GetError().to!string() );
                                                                writefln("text: %s", cmd_data2.output);
                                                            }

                                                            /* Draw cursor */
                                                            if (first_out && cmd_data2.pos < tt.chars.length &&
                                                                    command_in_focus_id == cmd_key2.cmd_id)
                                                            {
                                                                auto rect2= tt.chars[cmd_data2.pos];
                                                                rect2.x += 40;
                                                                rect2.y += cast(int)(y_off + 4 + line_height*i);
                                                                string chr = " ";
                                                                try
                                                                {
                                                                if (cmd_data2.pos >= 0 && cmd_data2.pos < cmd_data2.output.length && cmd_data2.pos + cmd_data2.output.mystride(cmd_data2.pos) < cmd_data2.output.length)
                                                                    chr = cmd_data2.output[cmd_data2.pos..cmd_data2.pos+cmd_data2.output.mystride(cmd_data2.pos)];
                                                                }
                                                                catch (UTFException exp)
                                                                {
                                                                    chr = " ";
                                                                }
                                                                if (chr == "\n") chr = " ";

                                                                r = SDL_RenderCopy(gs.renderer, gs.texture_cursor, null, &rect2);
                                                                if (r < 0)
                                                                {
                                                                    writefln( "draw_command_line(), 3: Error while render copy: %s",
                                                                            SDL_GetError().to!string() );
                                                                }

                                                                auto st = gs.text_viewer.font.get_char_from_cache(chr, fontsize, SDL_Color(0x00, 0x00, 0x20, 0xFF));
                                                                if (!st) return;

                                                                r = SDL_RenderCopy(gs.renderer, st.texture, null, &rect2);
                                                                if (r < 0)
                                                                {
                                                                    writefln(
                                                                            "draw_command_line(), 4: Error while render copy: %s", 
                                                                            SDL_GetError().to!string() );
                                                                    writefln("chr: %s", chr);
                                                                }
                                                            }
                                                        }
                                                        break;
                                                    case CommandsOutVersion.Screen:
                                                        rt = gs.text_viewer.font.get_size_of_line(cmd_data2.cols,
                                                               cmd_data2.rows, fontsize, color);

                                                        int lines = rt.h / line_height - 1;
                                                        if (cmd_data2.output.length > 0 && cmd_data2.output[$-1] != '\n') lines++;
                                                        y_off -= line_height*lines;

                                                        auto i = 0;
                                                        rect.x = 40;
                                                        rect.y = cast(int)(y_off + 4 + line_height*i);
                                                        rect.w = rt.w;
                                                        rect.h = rt.h;

                                                        if (rect.y < gs.screen.h && rect.y+rect.h > 0)
                                                        {
                                                            /* Selection */
                                                            ssize_t start_pos, end_pos;
                                                            get_start_end_pos(cmd_key2.cmd_id,
                                                                    cmd_key2.out_id,
                                                                    start_selection, 
                                                                    end_selection,
                                                                    start_pos, end_pos);

                                                            tt = gs.text_viewer.font.get_line_from_cache(cmd_data2.screen, 
                                                                    cmd_data2.cols, cmd_data2.rows,
                                                                    fontsize, line_height, color,
                                                                    cmd_data2.scr_attrs, start_pos, end_pos);
                                                            if (!tt && !tt.texture)
                                                            {
                                                                throw new Exception("Can't create text_surface: "~
                                                                        to!string(TTF_GetError()));
                                                            }
                                                            //assert(rt.w == tt.w && rt.h == tt.h, format("rt.w=%d, tt.w=%d, rt.h=%d, tt.h=%d",
                                                            //            rt.w, tt.w, rt.h, tt.h));

                                                            r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
                                                            if (r < 0)
                                                            {
                                                                writefln(
                                                                        "draw_command_line(), 2: Error while render copy: %s", 
                                                                        SDL_GetError().to!string() );
                                                                writefln("text: %s", cmd_data2.output);
                                                            }

                                                            /* Draw cursor */
                                                            if (first_out && cmd_data2.pos < tt.chars.length &&
                                                                    command_in_focus_id == cmd_key2.cmd_id)
                                                            {
                                                                auto rect2= tt.chars[cmd_data2.pos];
                                                                rect2.x += 40;
                                                                rect2.y += cast(int)(y_off + 4 + line_height*i);
                                                                string chr = " ";
                                                                try
                                                                {
                                                                    chr = to!string(cmd_data2.screen[cmd_data2.pos]);
                                                                }
                                                                catch (UTFException exp)
                                                                {
                                                                    chr = " ";
                                                                }
                                                                if (chr == "\n") chr = " ";

                                                                r = SDL_RenderCopy(gs.renderer, gs.texture_cursor, null, &rect2);
                                                                if (r < 0)
                                                                {
                                                                    writefln( "draw_command_line(), 3: Error while render copy: %s",
                                                                            SDL_GetError().to!string() );
                                                                }

                                                                auto st = gs.text_viewer.font.get_char_from_cache(chr, fontsize, SDL_Color(0x00, 0x00, 0x20, 0xFF));
                                                                if (!st) return;

                                                                r = SDL_RenderCopy(gs.renderer, st.texture, null, &rect2);
                                                                if (r < 0)
                                                                {
                                                                    writefln(
                                                                            "draw_command_line(), 4: Error while render copy: %s", 
                                                                            SDL_GetError().to!string() );
                                                                    writefln("chr: %s", chr);
                                                                }
                                                            }
                                                        }

                                                        break;
                                                }

                                                first_out = false;

                                                if (rect.y <= gs.mouse_screen_y && 
                                                        rect.y+rect.h-line_height >= gs.mouse_screen_y && neg_y >= 0)
                                                {
                                                    mouse.cmd_id = cmd_key2.cmd_id;
                                                    mouse.out_id = cmd_key2.out_id;
                                                    mouse.pos = get_position_by_chars(
                                                            gs.mouse_screen_x - rect.x,
                                                            gs.mouse_screen_y - rect.y, tt.chars);
                                                    mouse_rel_y = (cast(double)gs.mouse_screen_y-rect.y)/rect.h;
                                                    //writefln("OUT: mouse.cmd_id=%s, mouse.out_id=%s, gs.mouse_screen_y=%s rect.y=%s rect.h=%s, mouse_rel_y=%s",
                                                    //        mouse.cmd_id, mouse.out_id, gs.mouse_screen_y, rect.y, rect.h, mouse_rel_y);
                                                }

                                                if (rect.y > gs.screen.h)
                                                {
                                                    //writefln("tt.h=%s", tt.h);
                                                    //writefln("rect.y-gs.screen.h=%s", rect.y-gs.screen.h);
                                                    y -= rt.h - line_height;
                                                    nav_out_id = cmd_key2.out_id;
                                                    nav_cmd_id = cmd_key.id;
                                                    //writefln("OUT UP");
                                                }

                                                //writefln("OUT: y=%s, first_cmd_or_out=%s, nav_out_id=%s, rect.y + rect.h=%s, gs.screen.h=%s",
                                                //        y, first_cmd_or_out, nav_out_id, rect.y + rect.h, gs.screen.h);
                                                if (y != 0 && first_cmd_or_out && nav_out_id > 0 && (rect.y + rect.h) < gs.screen.h)
                                                {
                                                    fix_bottom_line(gs);
                                                    goto redraw;
                                                }
                                                first_cmd_or_out = false;

                                                if (rect.y + rect.h < 0)
                                                    break;
                                            }
                                        }
                                        while (cursor2.get(&key2, &data2, DB_PREV) == 0);

                                    }
                                }

                                //writefln("Excellent");
                                id = cmd_key.id;
                                string data_string = data.to!(string);
                                command_data cmd_data;
                                parse_data_for_command(data_string, cmd_data);

                                if (search_mode && cmd_data.command.indexOf(search) < 0)
                                    continue;

                                int line_height = cast(int)(round(SQRT2^^9)*1.2);
                                auto rt = gs.text_viewer.font.get_size_of_line(cmd_data.command, 
                                        9, gs.screen.w-120, line_height, SDL_Color(0xFF,0x00,0xFF,0xFF));

                                int lines = rt.h / line_height;
                                y_off -= line_height*lines;

                                /* Draw Status of cmd*/
                                if (cmd_data.end == 0)
                                {
                                    string symbol;
                                    SDL_Color color;
                                    if (cmd_key.id in gs.tid_by_command_id)
                                    {
                                        symbol = "⬤";
                                        color = SDL_Color(0x00, 0xFF, 0x00, 0xFF);
                                    }
                                    else
                                    {
                                        symbol = "◯";
                                        color = SDL_Color(0xFF, 0x00, 0x00, 0xFF);
                                    }
                                    auto tt = gs.text_viewer.font.get_char_from_cache(
                                            symbol, 7, color);

                                    auto rect = SDL_Rect();
                                    rect.x = 30;
                                    rect.y = cast(int)(y_off + 4);
                                    rect.w = tt.w;
                                    rect.h = tt.h;

                                    r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
                                    if (r < 0)
                                    {
                                        writefln(
                                                "draw_command_line(), 5: Error while render copy: %s", 
                                                SDL_GetError().to!string() );
                                    }
                                }
                                else
                                {
                                    auto color = SDL_Color(0x00,0xFF,0x00,0xFF);
                                    if (cmd_data.status != 0) color = SDL_Color(0xFF,0x00,0x00,0xFF);

                                    auto tt = gs.text_viewer.font.get_line_from_cache(format("%d", cmd_data.status), 
                                            8, gs.screen.w-120, line_height, color);
                                    if (!tt && !tt.texture)
                                    {
                                        throw new Exception("Can't create text_surface: "~
                                                to!string(TTF_GetError()));
                                    }

                                    auto rect = SDL_Rect();
                                    rect.x = 30;
                                    rect.y = cast(int)(y_off + 4);
                                    rect.w = tt.w;
                                    rect.h = tt.h;

                                    r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
                                    if (r < 0)
                                    {
                                        writefln(
                                                "draw_command_line(), 6: Error while render copy: %s", 
                                                SDL_GetError().to!string() );
                                    }
                                }

                                auto i = 0;
                                auto rect = SDL_Rect();
                                rect.x = 60;
                                rect.y = cast(int)(y_off + 4 + line_height*i);
                                rect.w = rt.w;
                                rect.h = rt.h;

                                Texture_Tick *tt;
                                if (rect.y < gs.screen.h && rect.y+rect.h > 0)
                                {
                                    /* Draw command */
                                    /* Selection */
                                    ssize_t start_pos, end_pos;
                                    get_start_end_pos(cmd_key.id,
                                            0,
                                            start_selection, 
                                            end_selection,
                                            start_pos, end_pos);
                                    tt = gs.text_viewer.font.get_line_from_cache(cmd_data.command, 
                                            9, gs.screen.w-80, line_height, SDL_Color(0xFF,0x00,0xFF,0xFF),
                                            null, start_pos, end_pos);
                                    if (!tt && !tt.texture)
                                    {
                                        throw new Exception("Can't create text_surface: "~
                                                to!string(TTF_GetError()));
                                    }

                                    r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
                                    if (r < 0)
                                    {
                                        writefln(
                                                "draw_command_line(), 7: Error while render copy: %s", 
                                                SDL_GetError().to!string() );
                                    }

                                    if (cmd_data.end == 0 && cmd_key.id in gs.tid_by_command_id)
                                    {
                                        /* Control elements for running processes */
                                        auto color = SDL_Color(0x80,0x80,0x00,0xFF);

                                        /*SIGTERM*/
                                        auto tt2 = gs.text_viewer.font.get_line_from_cache("TERM", 
                                                8, gs.screen.w-80, line_height, color);
                                        if (!tt2 && !tt2.texture)
                                        {
                                            throw new Exception("Can't create text_surface: "~
                                                    to!string(TTF_GetError()));
                                        }

                                        auto rect2 = SDL_Rect();
                                        rect2.x = rect.x+rect.w + 5;
                                        rect2.y = rect.y+3;
                                        rect2.w = tt2.w;
                                        rect2.h = tt2.h;

                                        if (gs.mouse_screen_x >= rect2.x && gs.mouse_screen_x <= rect2.x+rect2.w &&
                                                gs.mouse_screen_y >= rect2.y && gs.mouse_screen_y <= rect2.y+rect2.h)
                                        {
                                            color = SDL_Color(0xFF,0xFF,0x00,0xFF);
                                            tt2 = gs.text_viewer.font.get_line_from_cache("TERM", 
                                                    8, gs.screen.w-80, line_height, color);
                                            if (!tt2 && !tt2.texture)
                                            {
                                                throw new Exception("Can't create text_surface: "~
                                                        to!string(TTF_GetError()));
                                            }

                                            auto get_handler1(Tid tid)
                                            {
                                                return ()
                                                {
                                                    send(tid, "signal", SIGTERM);
                                                };
                                            }

                                            on_click = get_handler1(gs.tid_by_command_id[cmd_key.id]);
                                        }

                                        r = SDL_RenderCopy(gs.renderer, tt2.texture, null, &rect2);
                                        if (r < 0)
                                        {
                                            writefln(
                                                    "draw_command_line(), 8: Error while render copy: %s", 
                                                    SDL_GetError().to!string() );
                                        }

                                        /*SIGKILL*/
                                        color = SDL_Color(0x80,0x00,0x00,0x80);
                                        auto tt3 = gs.text_viewer.font.get_line_from_cache("KILL", 
                                                8, gs.screen.w-80, line_height, color);
                                        if (!tt3 && !tt3.texture)
                                        {
                                            throw new Exception("Can't create text_surface: "~
                                                    to!string(TTF_GetError()));
                                        }

                                        auto rect3 = SDL_Rect();
                                        rect3.x = rect2.x+rect2.w + 5;
                                        rect3.y = rect2.y;
                                        rect3.w = tt3.w;
                                        rect3.h = tt3.h;

                                        if (gs.mouse_screen_x >= rect3.x && gs.mouse_screen_x <= rect3.x+rect3.w &&
                                                gs.mouse_screen_y >= rect3.y && gs.mouse_screen_y <= rect3.y+rect3.h)
                                        {
                                            color = SDL_Color(0xFF,0x00,0x00,0x80);
                                            tt3 = gs.text_viewer.font.get_line_from_cache("KILL", 
                                                    8, gs.screen.w-80, line_height, color);
                                            if (!tt2 && !tt2.texture)
                                            {
                                                throw new Exception("Can't create text_surface: "~
                                                        to!string(TTF_GetError()));
                                            }

                                            auto get_handler2(Tid tid)
                                            {
                                                return ()
                                                {
                                                    send(tid, "signal", SIGKILL);
                                                };
                                            }

                                            on_click = get_handler2(gs.tid_by_command_id[cmd_key.id]);
                                        }

                                        r = SDL_RenderCopy(gs.renderer, tt3.texture, null, &rect3);
                                        if (r < 0)
                                        {
                                            writefln(
                                                    "draw_command_line(), 9: Error while render copy: %s", 
                                                    SDL_GetError().to!string() );
                                        }
                                    }
                                    else
                                    {
                                        /* Control elements for not running processes */

                                        /*PLAY*/
                                        auto color = SDL_Color(0x00,0x80,0x00,0xFF);
                                        auto tt2 = gs.text_viewer.font.get_char_from_cache(
                                                "⏵", 9, color);

                                        auto rect2 = SDL_Rect();
                                        rect2.x = rect.x+rect.w;
                                        rect2.y = rect.y;
                                        rect2.w = tt2.w;
                                        rect2.h = tt2.h;

                                        if (gs.mouse_screen_x >= rect2.x && gs.mouse_screen_x <= rect2.x+rect2.w &&
                                                gs.mouse_screen_y >= rect2.y && gs.mouse_screen_y <= rect2.y+rect2.h)
                                        {
                                            color = SDL_Color(0x00,0xFF,0x00,0xFF);
                                            tt2 = gs.text_viewer.font.get_char_from_cache(
                                                    "⏵", 9, color);
                                            auto get_handler3(string command)
                                            {
                                                return ()
                                                {
                                                    run_command(gs, command);
                                                };
                                            }
                                            on_click = get_handler3(cmd_data.command.idup());
                                        }

                                        r = SDL_RenderCopy(gs.renderer, tt2.texture, null, &rect2);
                                        if (r < 0)
                                        {
                                            writefln(
                                                    "draw_command_line(), 10: Error while render copy: %s", 
                                                    SDL_GetError().to!string() );
                                        }

                                        /*REMOVE*/
                                        color = SDL_Color(0x80,0x00,0x00,0xFF);
                                        auto tt3 = gs.text_viewer.font.get_char_from_cache(
                                                "❌", 9, color);

                                        auto rect3 = SDL_Rect();
                                        rect3.x = rect2.x+rect2.w + 5;
                                        rect3.y = rect2.y;
                                        rect3.w = tt3.w;
                                        rect3.h = tt3.h;

                                        if (gs.mouse_screen_x >= rect3.x && gs.mouse_screen_x <= rect3.x+rect3.w &&
                                                gs.mouse_screen_y >= rect3.y && gs.mouse_screen_y <= rect3.y+rect3.h)
                                        {
                                            color = SDL_Color(0xFF,0x00,0x00,0x80);
                                            tt3 = gs.text_viewer.font.get_char_from_cache(
                                                    "❌", 9, color);

                                            auto get_handler4(string cwd, ulong cmd_id)
                                            {
                                                return ()
                                                {
                                                    delete_command(gs, cwd, cmd_id);
                                                };
                                            }

                                            on_click = get_handler4(cmd_key.cwd.idup(), cmd_key.id);
                                        }

                                        r = SDL_RenderCopy(gs.renderer, tt3.texture, null, &rect3);
                                        if (r < 0)
                                        {
                                            writefln(
                                                    "draw_command_line(), 11: Error while render copy: %s", 
                                                    SDL_GetError().to!string() );
                                        }
                                    }

                                }

                                if (rect.y <= gs.mouse_screen_y && 
                                        rect.y+rect.h >= gs.mouse_screen_y && neg_y >= 0)
                                {
                                    mouse.cmd_id = cmd_key.id;
                                    mouse.out_id = 0;
                                    mouse.pos = get_position_by_chars(
                                            gs.mouse_screen_x - rect.x,
                                            gs.mouse_screen_y - rect.y, tt.chars);
                                    mouse_rel_y = (cast(double)gs.mouse_screen_y-rect.y)/rect.h;
                                    //writefln("CMD: mouse.cmd_id=%s, mouse.out_id=%s, command=%s",
                                    //        mouse.cmd_id, mouse.out_id, cmd_data.command);
                                }

                                if (rect.y > gs.screen.h)
                                {
                                    y -= rt.h;
                                    nav_skip_cmd_id = cmd_key.id;
                                    //writefln("CMD UP");
                                }

                                //writefln("CMD: y=%s, first_cmd_or_out=%s, nav_skip_cmd_id=%s, rect.y + rect.h=%s, gs.screen.h=%s",
                                //        y, first_cmd_or_out, nav_skip_cmd_id, rect.y + rect.h, gs.screen.h);
                                /*if (y != 0 && first_cmd_or_out && nav_skip_cmd_id > 0 && (rect.y + rect.h) < gs.screen.h)
                                {
                                    //FYI: This loop maybe be infinite
                                    fix_bottom_line(gs);
                                    goto redraw;
                                }*/

                                first_cmd_or_out = false;

                                if (rect.y + rect.h < 0)
                                    break;
                            }
                        }
                        while (cursor.get(&key, &data, DB_PREV) == 0);
                    }

                    if (first_cmd_or_out)
                    {
                        fix_bottom_line(gs);
                        //goto redraw;
                    }
                }
            }

            if (gs.command_line.enter)
            {
                long y_off;

                string prompt = "$ ";
                if (search_mode && hist_pos == 0)
                    prompt ="<search> ";
                int line_height = cast(int)(round(SQRT2^^9)*1.2);
                auto ptt = gs.text_viewer.font.get_line_from_cache(prompt, 
                        9, gs.screen.w-80, line_height, SDL_Color(0x00,0xFF,0x00,0xFF));
                if (!ptt && !ptt.texture)
                {
                    throw new Exception("Can't create text_surface: "~
                            to!string(TTF_GetError()));
                }

                string str = command;
                if (search_mode && hist_pos == 0)
                    str = search;

                auto tt = gs.text_viewer.font.get_line_from_cache(str, 
                        9, gs.screen.w-80-ptt.w, line_height, SDL_Color(0xFF, 0xFF, 0xFF, 0xFF),
                        null, cmd_start_selection, cmd_end_selection);
                if (!tt && !tt.texture)
                {
                    throw new Exception("Can't create text_surface: "~
                            to!string(TTF_GetError()));
                }

                Texture_Tick *ctt;
                if (!search_mode || hist_pos != 0)
                {
                    ssize_t ipos = pos;
                    if (ipos > command.length) ipos = command.length-1;
                    complete = autocomplete(gs, command[0..ipos]);

                    if (complete.length > 1)
                    {
                        int linewidth = gs.screen.w-80-ptt.w-tt.w;
                        if (complete[0] == '2')
                        {
                            linewidth = gs.screen.w-80;
                        }

                        ctt = gs.text_viewer.font.get_line_from_cache(complete[1..$], 
                                9, linewidth, line_height, SDL_Color(0xFF, 0x96, 0x00, 0xFF));
                        if (!ctt && !ctt.texture)
                        {
                            throw new Exception("Can't create text_surface: "~
                                    to!string(TTF_GetError()));
                        }
                    }
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

                cmd_rect = rect;

                if (complete.length > 1 && complete[0] == '2' && ctt !is null)
                {
                    rect.y -= ctt.h;
                    rect.h += ctt.h;
                }

                r = SDL_RenderCopy(gs.renderer, gs.texture_black, null, &rect);
                if (r < 0)
                {
                    writefln( "draw_command_line(), 8: Error while render copy: %s",
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
                        "draw_command_line(), 9: Error while render copy: %s", 
                        SDL_GetError().to!string() );
                }

                /* EN: Render text to screen
                   RU: Рендерим текст на экран */
                rect = SDL_Rect();
                rect.x = 40+ptt.w;
                rect.y = cast(int)(y_off + 4 + line_height*i);
                rect.w = tt.w;
                rect.h = tt.h;

                cmd_mouse_pos = get_position_by_chars(
                        gs.mouse_screen_x - rect.x,
                        gs.mouse_screen_y - rect.y, tt.chars);

                r = SDL_RenderCopy(gs.renderer, tt.texture, null, &rect);
                if (r < 0)
                {
                    writefln(
                        "draw_command_line(), 10: Error while render copy: %s", 
                        SDL_GetError().to!string() );
                }

                /* EN: Render autocomplete to screen
                   RU: Рендерим автодополнение на экран */
                if ((!search_mode || hist_pos != 0) && complete.length > 1)
                {
                    rect = SDL_Rect();
                    if (complete[0] == '1' && pos == command.length)
                    {
                        rect.x = 40+ptt.w+tt.w-tt.chars[$-1].w;
                        rect.y = cast(int)(y_off + 4 + line_height*i);
                        rect.w = ctt.w;
                        rect.h = ctt.h;
                    }
                    else if (complete[0] == '2' || pos < command.length)
                    {
                        rect.x = 40;
                        rect.y = cast(int)(y_off + 4 + line_height*i - ctt.h);
                        rect.w = ctt.w;
                        rect.h = ctt.h;
                    }

                    r = SDL_RenderCopy(gs.renderer, ctt.texture, null, &rect);
                    if (r < 0)
                    {
                        writefln(
                            "draw_command_line(), 10: Error while render copy: %s", 
                            SDL_GetError().to!string() );
                    }
                }

                /* Render cursor */
                if (pos < tt.chars.length)
                {
                    rect = tt.chars[pos];
                    rect.x += 40+ptt.w;
                    rect.y += cast(int)(y_off + 4 + line_height*i);
                    string chr = " ";
                    if (pos < str.length)
                        chr = str[pos..pos+str.stride(pos)];
                    else if (complete.length > 1 && complete[0] == '1')
                        chr = complete[1..1+complete.stride(1)];
                    if (chr == "\n") chr = " ";

                    r = SDL_RenderCopy(gs.renderer, gs.texture_cursor, null, &rect);
                    if (r < 0)
                    {
                        writefln( "draw_command_line(), 11: Error while render copy: %s",
                                SDL_GetError().to!string() );
                    }

                    auto st = gs.text_viewer.font.get_char_from_cache(chr, 9, SDL_Color(0x00, 0x00, 0x20, 0xFF));
                    if (!st) return;

                    r = SDL_RenderCopy(gs.renderer, st.texture, null, &rect);
                    if (r < 0)
                    {
                        writefln(
                            "draw_command_line(), 12: Error while render copy: %s", 
                            SDL_GetError().to!string() );
                    }
                }
            }

            last_redraw = SDL_GetTicks();

            r = SDL_SetRenderTarget(gs.renderer, old_texture);
            if (r < 0)
            {
                throw new Exception(format("Error while restore render target: %s",
                        fromStringz(SDL_GetError()) ));
            }

            gs.text_viewer.font.clear_chars_cache();
            gs.text_viewer.font.clear_lines_cache();
        }

        SDL_Rect dst = SDL_Rect(0, 0, gs.screen.w, gs.screen.h);
        int r = SDL_RenderCopy(gs.renderer, texture, null, &dst);
        if (r < 0)
        {
            writefln( "draw_text(): Error while render copy texture: %s", fromStringz(SDL_GetError()) );
        }
    }

}

void update_winsize(GlobalState gs)
{
    if (gs.command_line.fontsize < 5) return;

    int line_height = cast(int)(round(SQRT2^^9)*1.2);
    auto h = gs.screen.h - line_height*2;
    auto w = gs.screen.w - 80;

    auto st = gs.text_viewer.font.get_char_from_cache(" ", 
            gs.command_line.fontsize, SDL_Color(0xFF, 0xFF, 0xFF, 0xFF));
    if (!st) return;

   with ( gs.command_line.ws)
   {
        ws_xpixel = cast(ushort)w;
        ws_ypixel = cast(ushort)h;
        ws_row = cast(ushort)(h/st.h);
        ws_col = cast(ushort)(w/st.w);
   }

   foreach (tid; gs.tid_by_command_id)
   {
       tid.send(gs.command_line.ws);
   }
}


void
hist_up(GlobalState gs)
{
    with (gs.command_line)
    {
        cmd_start_selection = -1;
        cmd_end_selection = -1;

        cwd = gs.current_path;
        Dbc cursor = gs.db_commands.cursor(null, 0);
        scope(exit) cursor.close();

        Dbt key, data;
        ulong id = find_prev_command(cursor, cwd, hist_cmd_id,
                key, data);

        if (id != 0)
        {
            do
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
                    string data_string = data.to!(string);
                    command_data cmd_data;
                    parse_data_for_command(data_string, cmd_data);

                    if (hist_pos == 0)
                    {
                        edited_command = command;
                    }
                    hist_pos++;

                    if (search_mode && cmd_data.command.indexOf(search) < 0)
                        continue;

                    id = cmd_key.id;
                    command = cmd_data.command.idup();
                    pos = command.length;
                    //writefln("Excellent");
                    //writefln("cmd_data.command=%s", cmd_data.command);
                    //writefln("pos=%s", pos);
                }
                break;
            }
            while (cursor.get(&key, &data, DB_PREV) == 0);
        }

        if (id == 0)
        {
            hist_pos = 0;
            command = edited_command;
            pos = command.length;
        }

        hist_cmd_id = id;
    }
}

void
hist_down(GlobalState gs)
{
    with (gs.command_line)
    {
        cmd_start_selection = -1;
        cmd_end_selection = -1;

        cwd = gs.current_path;
        Dbc cursor = gs.db_commands.cursor(null, 0);
        scope(exit) cursor.close();

        Dbt key, data;
        ulong id = find_next_command(cursor, cwd, hist_cmd_id,
                key, data);

        if (id != 0)
        {
            do
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
                    //writefln("Excellent");
                    string data_string = data.to!(string);
                    command_data cmd_data;
                    parse_data_for_command(data_string, cmd_data);

                    if (hist_pos == 0)
                    {
                        edited_command = command;
                    }
                    hist_pos++;

                    if (search_mode && cmd_data.command.indexOf(search) < 0)
                        continue;

                    id = cmd_key.id;
                    command = cmd_data.command.idup();
                    pos = command.length;
                }
                break;
            }
            while (cursor.get(&key, &data, DB_NEXT) == 0);
        }

        if (id == 0)
        {
            hist_pos = 0;
            command = edited_command;
            pos = command.length;
        }

        gs.command_line.hist_cmd_id = id;
    }
}
