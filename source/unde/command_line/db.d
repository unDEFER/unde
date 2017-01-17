module unde.command_line.db;

import berkeleydb.all;
import std.bitmanip;
import std.string;
import std.stdio;

import unde.global_state;

struct command_key
{
    string cwd;
    ulong id;
}

struct command_data
{
    string command;
    ulong start;
    ulong end;
    int status;
}

string
get_key_for_command(command_key k)
{
    string key_string;
    key_string ~= nativeToBigEndian(cast(ushort)k.cwd.length);
    key_string ~= k.cwd;
    key_string ~= nativeToBigEndian(k.id);
    return key_string;
}

void
parse_key_for_command(in string key_string, out command_key k)
{
    ubyte[k.id.sizeof] id = (cast(ubyte[])key_string)[$-k.id.sizeof..$]; 
    k.id = bigEndianToNative!ulong(id);
    k.cwd = key_string[ushort.sizeof..$-k.id.sizeof];
    ubyte[ushort.sizeof] cwd_len_bytes = (cast(ubyte[])key_string)[0..ushort.sizeof]; 
    ushort cwd_len = bigEndianToNative!ushort(cwd_len_bytes);
    assert(k.cwd.length == cwd_len);
}

unittest
{
    command_key cmd_key = command_key("Some Text", 0xABCDEF0123456789);
    string key_string = get_key_for_command(cmd_key);
    command_key cmd_key2;
    parse_key_for_command(key_string, cmd_key2);
    assert(cmd_key == cmd_key2, format("%s=%s, %X=%X", 
                cmd_key.cwd, cmd_key2.cwd, cmd_key.id, cmd_key2.id));
}

string
get_data_for_command(command_data d)
{
    string data_string;
    data_string = d.command;
    data_string ~= (cast(char*)&d.start)[0..d.start.sizeof];
    data_string ~= (cast(char*)&d.end)[0..d.end.sizeof];
    data_string ~= (cast(char*)&d.status)[0..d.status.sizeof];
    return data_string;
}

void
parse_data_for_command(string data_string, out command_data d)
{
    d.status = *cast(int*)data_string[$-d.status.sizeof..$];
    data_string = data_string[0..$-d.status.sizeof];
    d.end = *cast(ulong*)data_string[$-d.end.sizeof..$];
    data_string = data_string[0..$-d.end.sizeof];
    d.start = *cast(ulong*)data_string[$-d.start.sizeof..$];
    d.command = data_string[0..$-d.start.sizeof];
}

unittest
{
    command_data cmd_data = command_data("Some Command", 0xABCDEF0123456789,
            0xFED347891ABCF356, 0xAF102545);
    string data_string = get_data_for_command(cmd_data);
    command_data cmd_data2;
    parse_data_for_command(data_string, cmd_data2);
    assert(cmd_data == cmd_data2);
}

struct command_out_key
{
    string cwd;
    ulong cmd_id;
    ulong out_id;
}

enum OutPipe
{
    STDOUT,
    STDERR
}

enum CommandsOutVersion
{
    Simple,
    Screen
}

struct command_out_data
{
    CommandsOutVersion vers;
    ulong time;
    OutPipe pipe;
    size_t pos;
    union
    {
        struct
        {
            int len;
            ushort[] attrs;
            string output;
        };
        struct
        {
            int cols;
            int rows;
            dchar[] screen;
            ushort[] scr_attrs;
        }
    }

    this(ulong time, OutPipe pipe, size_t pos, string output)
    {
        this.time = time;
        this.pipe = pipe;
        this.pos = pos;
        this.output = output;
    }
    this(ulong time, OutPipe pipe, size_t pos, string output, ushort[] attrs)
    {
        this.time = time;
        this.pipe = pipe;
        this.pos = pos;
        this.output = output;
        this.len = cast(int)attrs.length;
        this.attrs = attrs;
    }
    this(ulong time, OutPipe pipe, size_t pos, int cols, int rows, dchar[] screen, ushort[] scr_attrs)
    {
        this.vers = CommandsOutVersion.Screen;
        this.time = time;
        this.pipe = pipe;
        this.pos = pos;
        this.cols = cols;
        this.rows = rows;
        this.screen = screen;
        this.scr_attrs = scr_attrs;
    }
}

string
get_key_for_command_out(command_out_key k)
{
    string key_string;
    key_string = k.cwd;
    key_string ~= nativeToBigEndian(k.cmd_id);
    key_string ~= nativeToBigEndian(k.out_id);
    return key_string;
}

void
parse_key_for_command_out(string key_string, out command_out_key k)
{
    ubyte[k.out_id.sizeof] out_id = (cast(ubyte[])key_string)[$-k.out_id.sizeof..$]; 
    k.out_id = bigEndianToNative!ulong(out_id);
    key_string = key_string[0..$-k.out_id.sizeof];
    ubyte[k.cmd_id.sizeof] cmd_id = (cast(ubyte[])key_string)[$-k.cmd_id.sizeof..$]; 
    k.cmd_id = bigEndianToNative!ulong(cmd_id);
    k.cwd = key_string[0..$-k.cmd_id.sizeof];
}

unittest
{
    command_out_key cmd_key = command_out_key("Some Text", 0xABCDEF0123456789, 0xFED347891ABCF356);
    string key_string = get_key_for_command_out(cmd_key);
    command_out_key cmd_key2;
    parse_key_for_command_out(key_string, cmd_key2);
    assert(cmd_key == cmd_key2);
}

string
get_data_for_command_out(command_out_data d)
{
    string data_string;
    data_string = "";
    data_string ~= (cast(char*)&d.vers)[0..d.vers.sizeof];
    data_string ~= (cast(char*)&d.time)[0..d.time.sizeof];
    data_string ~= (cast(char*)&d.pipe)[0..d.pipe.sizeof];
    data_string ~= (cast(char*)&d.pos)[0..d.pos.sizeof];
    final switch (d.vers)
    {
        case CommandsOutVersion.Simple:
            data_string ~= (cast(char*)&d.len)[0..d.len.sizeof];
            assert(d.attrs.length == d.len);
            data_string ~= (cast(char*)d.attrs.ptr)[0..ushort.sizeof*d.len];
            data_string ~= d.output;
            break;

        case CommandsOutVersion.Screen:
            data_string ~= (cast(char*)&d.cols)[0..d.cols.sizeof];
            data_string ~= (cast(char*)&d.rows)[0..d.rows.sizeof];
            assert(d.cols*d.rows == d.screen.length);
            assert(d.cols*d.rows == d.scr_attrs.length);
            data_string ~= (cast(char*)d.screen.ptr)[0..dchar.sizeof*d.cols*d.rows];
            data_string ~= (cast(char*)d.scr_attrs.ptr)[0..ushort.sizeof*d.cols*d.rows];
            break;
    }

    return data_string;
}

void
parse_data_for_command_out(string data_string, out command_out_data d)
{
    d.vers = *cast(CommandsOutVersion*)data_string[0..d.vers.sizeof];
    data_string = data_string[d.vers.sizeof..$];
    d.time = *cast(ulong*)data_string[0..d.time.sizeof];
    data_string = data_string[d.time.sizeof..$];
    d.pipe = *cast(OutPipe*)data_string[0..d.pipe.sizeof];
    data_string = data_string[d.pipe.sizeof..$];
    d.pos = *cast(size_t*)data_string[0..d.pos.sizeof];
    data_string = data_string[d.pos.sizeof..$];

    final switch (d.vers)
    {
        case CommandsOutVersion.Simple:
            d.len = *cast(int*)data_string[0..d.len.sizeof];
            data_string = data_string[d.len.sizeof..$];
            d.attrs = (cast(ushort*)data_string.ptr)[0..d.len];
            d.output = data_string[ushort.sizeof*d.len..$];
            break;

        case CommandsOutVersion.Screen:
            d.cols = *cast(int*)data_string[0..d.cols.sizeof];
            data_string = data_string[d.cols.sizeof..$];
            d.rows = *cast(int*)data_string[0..d.rows.sizeof];
            data_string = data_string[d.rows.sizeof..$];
            d.screen = (cast(dchar*)data_string.ptr)[0..d.cols*d.rows];
            data_string = data_string[dchar.sizeof*d.cols*d.rows..$];
            d.scr_attrs = (cast(ushort*)data_string.ptr)[0..d.cols*d.rows];
            assert(data_string.length == ushort.sizeof*d.cols*d.rows);
            break;
    }
}

unittest
{
    command_out_data cmd_data;
    cmd_data.vers = CommandsOutVersion.Simple;
    cmd_data.time = 0xABCDEF0123456789;
    cmd_data.pipe = OutPipe.STDERR;
    cmd_data.pos = 3458;
    cmd_data.len = 5;
    cmd_data.attrs = [65535, 23524, 12235, 43567, 34585];
    cmd_data.output = "Кра27";
    string data_string = get_data_for_command_out(cmd_data);
    command_out_data cmd_data2;
    parse_data_for_command_out(data_string, cmd_data2);
    assert(cmd_data.vers == cmd_data2.vers &&
            cmd_data.time == cmd_data2.time &&
            cmd_data.pipe == cmd_data2.pipe &&
            cmd_data.pos == cmd_data2.pos &&
            cmd_data.len == cmd_data2.len &&
            cmd_data.attrs == cmd_data2.attrs &&
            cmd_data.output == cmd_data2.output, 
            format("%s = %s", cmd_data.output, cmd_data2.output));

    cmd_data = command_out_data();
    cmd_data.vers = CommandsOutVersion.Screen;
    cmd_data.time = 0xABCDEF0123456789;
    cmd_data.pipe = OutPipe.STDERR;
    cmd_data.pos = 3458;
    cmd_data.cols = 3;
    cmd_data.rows = 2;
    cmd_data.screen = "Кра276"d.dup();
    cmd_data.scr_attrs = [65535, 23524, 12235, 43567, 34585, 456];
    data_string = get_data_for_command_out(cmd_data);
    cmd_data2 = command_out_data();
    parse_data_for_command_out(data_string, cmd_data2);
    assert(cmd_data.vers == cmd_data2.vers &&
            cmd_data.time == cmd_data2.time &&
            cmd_data.pipe == cmd_data2.pipe &&
            cmd_data.pos == cmd_data2.pos &&
            cmd_data.cols == cmd_data2.cols &&
            cmd_data.rows == cmd_data2.rows &&
            cmd_data.screen == cmd_data2.screen &&
            cmd_data.scr_attrs == cmd_data2.scr_attrs, format("%s = %s", 
                cmd_data.screen, cmd_data2.screen));
}

package ulong
find_next_by_key(Dbc cursor, ulong cmd_id, ulong id, ref Dbt key, ref Dbt data)
{
    auto res = cursor.get(&key, &data, DB_SET_RANGE);
    if (res == DB_NOTFOUND)
    {
        //writefln("NOT FOUND, GET LAST");
        res = cursor.get(&key, &data, DB_FIRST);
        if (res == DB_NOTFOUND)
        {
            //writefln("NOT FOUND");
            id = 0;
        }
    }
    else if (cmd_id > 0)
    {
        //writefln("GOTO PREV");
        res = cursor.get(&key, &data, DB_NEXT);
        if (res == DB_NOTFOUND)
        {
            //writefln("NOT FOUND");
            id = 0;
        }
    }
    return id;
}

package ulong
find_prev_by_key(Dbc cursor, ulong id, ref Dbt key, ref Dbt data)
{
    auto res = cursor.get(&key, &data, DB_SET_RANGE);
    if (res == DB_NOTFOUND)
    {
        //writefln("NOT FOUND, GET LAST");
        res = cursor.get(&key, &data, DB_LAST);
        if (res == DB_NOTFOUND)
        {
            //writefln("NOT FOUND");
            id = 0;
        }
    }
    else
    {
        //writefln("GOTO PREV");
        res = cursor.get(&key, &data, DB_PREV);
        if (res == DB_NOTFOUND)
        {
            //writefln("NOT FOUND");
            id = 0;
        }
    }
    return id;
}

package ulong
find_prev_command(Dbc cursor, string cwd, ulong cmd_id,
        ref Dbt key, ref Dbt data)
{
    ulong id = cmd_id > 0 ? cmd_id : ulong.max;
    string ks = get_key_for_command(command_key(cwd, id));
    //writefln("SET RANGE: %s (cwd=%s, id=%X)", ks, cwd, id);
    key = ks;
    id = find_prev_by_key(cursor, id, key, data);

    return id;
}

package ulong
find_next_command(Dbc cursor, string cwd, ulong cmd_id,
        ref Dbt key, ref Dbt data)
{
    ulong id = cmd_id > 0 ? cmd_id : 1;
    string ks = get_key_for_command(command_key(cwd, id));
    //writefln("SET RANGE: %s (cwd=%s, id=%X)", ks, cwd, id);
    key = ks;
    id = find_next_by_key(cursor, cmd_id, id, key, data);

    return id;
}

package ulong
find_prev_command_out(Dbc cursor, string cwd, ulong cmd_id, ulong out_id,
        ref Dbt key, ref Dbt data)
{
    ulong id = out_id > 0 ? out_id : ulong.max;
    string ks = get_key_for_command_out(command_out_key(cwd, cmd_id, id));
    //writefln("SET RANGE: %s (cwd=%s, id=%X)", ks, cwd, id);
    key = ks;
    id = find_prev_by_key(cursor, id, key, data);

    return id;
}

package ulong
find_next_command_out(Dbc cursor, string cwd, ulong cmd_id, ulong out_id,
        ref Dbt key, ref Dbt data)
{
    ulong id = out_id > 0 ? out_id : 1;
    string ks = get_key_for_command_out(command_out_key(cwd, cmd_id, id));
    //writefln("SET RANGE: %s (cwd=%s, id=%X)", ks, cwd, id);
    key = ks;
    id = find_next_by_key(cursor, out_id, id, key, data);

    return id;
}

private
struct TxnPuts
{
   uint txn_id;
   string[] keys;
   string[] datas;
}

package int
command_output_put(CMDGlobalState cgs, Dbt *key, Dbt *data)
{
    static TxnPuts txn_puts;
    auto txn_id = cgs.txn.id();
    if (txn_id != txn_puts.txn_id)
    {
        txn_puts.txn_id = txn_id;
        txn_puts.keys = [];
        txn_puts.datas = [];
    }

    bool reput;
    int res;
retry:
    try
    {
        if (reput)
        {
            txn_puts.txn_id = cgs.txn.id();
            for (ssize_t i = 0; i < txn_puts.keys.length; i++)
            {
                Dbt key2, data2;
                key2 = txn_puts.keys[i];
                data2 = txn_puts.datas[i];
                cgs.db_command_output.put(cgs.txn, &key2, &data2);
            }
        }

        res = cgs.db_command_output.put(cgs.txn, key, data);
    }
    catch (DbDeadlockException exp)
    {
        writefln("Oops deadlock, retry");
        cgs.abort();
        cgs.recommit();
        reput = true;
        goto retry;
    }

    string str_key = key.to!(string).idup();
    if (txn_puts.keys.length > 0 && str_key == txn_puts.keys[$-1])
    {
        txn_puts.datas[$-1] ~= data.to!(string).idup();
    }
    else
    {
        txn_puts.keys ~= str_key;
        txn_puts.datas ~= data.to!(string).idup();
    }

    return res;
}
