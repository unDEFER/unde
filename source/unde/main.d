module unde.main;

import unde.draw;
import unde.global_state;
import unde.tick;
import unde.slash;

import derelict.sdl2.sdl;

import std.stdio;
import core.stdc.stdlib;

import core.sys.posix.signal;

extern(C) void mybye(int value){
    exit(1);
}

int main(string[] args)
{
    bool force_recover;
    if (args.length > 1)
       force_recover = (args[1] == "--force_recover");
    GlobalState gs = new GlobalState(force_recover);
    version(Posix)
    {
    sigset(SIGINT, &mybye);
    }
    gs.main_path = gs.path = SL;

    /* How many frames was skipped */
    uint skipframe;
    /* How long rendering was last frame */
    uint last_draw_time;

    /* Sum of time which was taken by rendering */
    uint drawtime;
    /* Minumum time between 2 frames */
    uint min_frame_time = 2;
    /* Maximum skip frames running */
    uint max_skip_frames = 10;

    /* Start time used in below scope(exit) to calculate avarage
       rendering time*/
    uint starttime=SDL_GetTicks();
    scope(exit)
    {
        uint endtime = SDL_GetTicks();
        writefln("FPS= %f, average draw time: %f ms\n",
            (cast(float)gs.frame)*1000/(endtime-starttime), 
            (cast(float)drawtime)/gs.frame);
        /* EN: Necessary because otherwise it will destroy 
           gs.dbenv, gs.db_map before and it lead to Seg.Fault
           RU: Необходим, т.к. иначе до gs будут уничтожены
           gs.dbenv, gs.db_map, что ведёт к ошибке сегментирования */
        destroy(gs);
    }

    /* The main Idea of rendering process:
       Splitting the actions which must be done on frame on 2:
       1. Process events and make tick
       2. Draw Frame
       "Draw frame" maybe skipped to catch up real time,
       But "Make tick" can't be skipped
     */
    while(!gs.finish)
    {
        uint time_before_frame=SDL_GetTicks();

        /* Process incoming events. */

        process_events(gs);

        make_tick(gs);
	stdout.flush();

        uint now=SDL_GetTicks();
        /* Draw the screen. */
        /* Don't skip frame when:
            1. Too much frame skipped
            2. The virtual time (gs.time) too big (more than real time)
            3. Estimation time of the next frame less than minumum frame time  */
        if ( skipframe>=max_skip_frames || (gs.time+250.0)>now ||
                (now+last_draw_time)<(time_before_frame+min_frame_time) )
        {
            gs.txn = null;//dbenv.txn_begin(null, DB_TXN_SNAPSHOT);
            uint time_before_draw=SDL_GetTicks();

	    draw_screen(gs, gs.txn);

            last_draw_time=SDL_GetTicks()-time_before_draw;
            drawtime+=last_draw_time;

            //gs.txn.commit();

            gs.frame++;
            skipframe=0;
        }
        else skipframe++;

        now=SDL_GetTicks();
        /* Virtual time more real time? */
        if (gs.time>now)
            SDL_Delay(gs.time-now);
        else /* If time of frame too small */
            if ( (now - time_before_frame)<min_frame_time )
                SDL_Delay( min_frame_time - (now - time_before_frame) );
        
        /* Add 10 ms to time, because we want render with speed 100 FPS
           1 frame / 100 FPS = 1/100s = 10ms */
        gs.time += 10;

    }
    return 0;
}
