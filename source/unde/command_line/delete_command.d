module unde.command_line.delete_command;

import unde.global_state;
import unde.command_line.db;

import std.concurrency;
import std.stdio;

import berkeleydb.all;

package void
delete_command_out(CMDGlobalState cgs, string cwd, ulong cmd_id)
{
    cgs.commit();
    cgs.recommit();
begin:
    Dbc cursor;
    try
    {
        cursor = cgs.db_command_output.cursor(cgs.txn, 0);
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
                cgs.OIT++;
                if (cgs.is_time_to_recommit())
                {
                    cursor.close();
                    cgs.recommit();
                    cursor = cgs.db_command_output.cursor(cgs.txn, 0);
                    res = cursor.get(&key, &data, DB_SET_RANGE);
                    if (res == DB_NOTFOUND)
                    {
                        return;
                    }
                }
                cursor.del();
            }
            else
            {
                break;
            }

        } while (cursor.get(&key, &data, DB_NEXT) == 0);
    }
    catch (DbDeadlockException exp)
    {
        writefln("Oops deadlock, retry");
        cgs.abort();
        cgs.recommit();
        goto begin;
    }
}

private int
delete_cmd(CMDGlobalState cgs, string cwd, ulong cmd_id)
{
    cgs.recommit();

    int result;

    delete_command_out(cgs, cwd, cmd_id);

    string ks = get_key_for_command(command_key(cwd, cmd_id));
    Dbt key = ks;
    auto res = cgs.db_commands.del(cgs.txn, &key);

    return result;
}

private void
command(string cwd, ulong cmd_id, Tid tid)
{
    CMDGlobalState cgs = new CMDGlobalState();
    try {
        scope(exit)
        {
            destroy(cgs);
        }
        delete_cmd(cgs, cwd, cmd_id);
        cgs.commit();
    } catch (shared(Throwable) exc) {
        send(tid, exc);
    }

    writefln("Finish delete command %s ID=%d", cwd, cmd_id);
    send(tid, thisTid);
}

public int
delete_command(GlobalState gs, string cwd, ulong cmd_id)
{
    writefln("Start delete command %s ID=%d", cwd, cmd_id);
    auto tid = spawn(&.command, cwd, cmd_id, thisTid);
    gs.delete_commands[tid] = cmd_id;
    return 0;
}

