module unde.command_line.db;

import berkeleydb.all;
import std.bitmanip;

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

package string
get_key_for_command(command_key k)
{
    string key_string;
    key_string = k.cwd;
    key_string ~= nativeToBigEndian(k.id);
    return key_string;
}

package void
parse_key_for_command(in string key_string, out command_key k)
{
    ubyte[k.id.sizeof] id = (cast(ubyte[])key_string)[$-k.id.sizeof..$]; 
    k.id = bigEndianToNative!ulong(id);
    k.cwd = key_string[0..$-k.id.sizeof];
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

package string
get_data_for_command(command_data d)
{
    string data_string;
    data_string = d.command;
    data_string ~= (cast(char*)&d.start)[0..d.start.sizeof];
    data_string ~= (cast(char*)&d.end)[0..d.end.sizeof];
    data_string ~= (cast(char*)&d.status)[0..d.status.sizeof];
    return data_string;
}

package void
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

struct command_out_data
{
    ulong time;
    OutPipe pipe;
    string output;
}

package string
get_key_for_command_out(command_out_key k)
{
    string key_string;
    key_string = k.cwd;
    key_string ~= nativeToBigEndian(k.cmd_id);
    key_string ~= nativeToBigEndian(k.out_id);
    return key_string;
}

package void
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

package string
get_data_for_command_out(command_out_data d)
{
    string data_string;
    data_string = "";
    data_string ~= (cast(char*)&d.time)[0..d.time.sizeof];
    data_string ~= (cast(char*)&d.pipe)[0..d.pipe.sizeof];
    data_string ~= d.output;
    return data_string;
}

package void
parse_data_for_command_out(string data_string, out command_out_data d)
{
    d.time = *cast(ulong*)data_string[0..d.time.sizeof];
    data_string = data_string[d.time.sizeof..$];
    d.pipe = *cast(OutPipe*)data_string[0..d.pipe.sizeof];
    d.output = data_string[d.pipe.sizeof..$];
}

unittest
{
    command_out_data cmd_data = command_out_data(0xABCDEF0123456789,
            OutPipe.STDERR, "Some output");
    string data_string = get_data_for_command_out(cmd_data);
    command_out_data cmd_data2;
    parse_data_for_command_out(data_string, cmd_data2);
    assert(cmd_data == cmd_data2, format("%s = %s", 
                cmd_data.output, cmd_data2.output));
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
