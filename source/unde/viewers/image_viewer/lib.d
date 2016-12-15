module unde.viewers.image_viewer.lib;

import unde.global_state;
import unde.path_mnt;
import unde.lib;
import unde.slash;

import berkeleydb.all;

import derelict.sdl2.sdl;
import derelict.sdl2.image;

import std.string;
import std.stdio;
import std.algorithm.sorting;
import std.math;

import std.file;

void
image_viewer(GlobalState gs, PathMnt p)
{
    with (gs.image_viewer)
    {
        auto old_state = gs.state;
        gs.state = State.ImageViewer;
        path = p;

        rect = SDL_Rect(0, 0, gs.screen.w, gs.screen.h);

        auto st = get_image_from_cache(gs, path);
        texture_tick = st;
        get_rectsize(gs);
        if (st != null)
        {
            if (st.w > gs.screen.w || st.h > gs.screen.h)
            {
                setup_0_scale(gs);
            }
            else
            {
                setup_1_scale(gs);
            }
        }

        if (old_state != State.ImageViewer)
        {
            calculate_positions_in_directories(gs);
        }

        gs.dirty = true;
    }
}

package void
setup_0_scale(GlobalState gs)
{
    with (gs.image_viewer)
    {
        with (gs.image_viewer.texture_tick)
        {
            if (texture)
            {
                int w = w;
                int h = h;

                if (rectsize.angle == 90 || rectsize.angle == 270)
                {
                    if (w/h > gs.screen.w/gs.screen.h)
                    {
                        /* EN: Center and scale down picture to take all width
                            of screen
                           RU: Отцентрировать и уменьшить картинку так, чтобы
                            она заняла всю ширину экрана */
                        rect.x = (gs.screen.w - gs.screen.h)/2;
                        rect.y = (gs.screen.w*h/w - gs.screen.h*h/w)/2 + (gs.screen.h-gs.screen.w*h/w)/2;
                        rect.w = gs.screen.h;
                        rect.h = gs.screen.h*h/w;
                    }
                    else
                    {
                        /* EN: Center and scale down picture to take all height
                            of screen
                           RU: Отцентрировать и уменьшить картинку так, чтобы
                            она заняла всю высоту экрана */
                        rect.x = (gs.screen.h*w/h - gs.screen.h)/2 + (gs.screen.w-gs.screen.h*w/h)/2;
                        rect.y = (gs.screen.h - gs.screen.h*h/w)/2;
                        rect.w = gs.screen.h;
                        rect.h = gs.screen.h*h/w;
                    }
                }
                else
                {
                    if (w/h > gs.screen.w/gs.screen.h)
                    {
                        /* EN: Center and scale down picture to take all width
                            of screen
                           RU: Отцентрировать и уменьшить картинку так, чтобы
                            она заняла всю ширину экрана */
                        rect.x = 0;
                        rect.y = (gs.screen.h-gs.screen.w*h/w)/2;
                        rect.w = gs.screen.w;
                        rect.h = gs.screen.w*h/w;
                    }
                    else
                    {
                        /* EN: Center and scale down picture to take all height
                            of screen
                           RU: Отцентрировать и уменьшить картинку так, чтобы
                            она заняла всю высоту экрана */
                        rect.x = (gs.screen.w-gs.screen.h*w/h)/2;
                        rect.y = 0;
                        rect.w = gs.screen.h*w/h;
                        rect.h = gs.screen.h;
                    }
                }
            }
        }
    }
}

package void
setup_1_scale(GlobalState gs)
{
    with (gs.image_viewer)
    {
        with (gs.image_viewer.texture_tick)
        {
            if (texture)
            {
                rect = SDL_Rect(0, 0, w, h);
                if (rectsize.angle == 90 || rectsize.angle == 270)
                {
                    rect.x = -(w-h)/2;
                    rect.y = (w-h)/2;
                }
            }
        }
    }
}

private void
get_rectsize(GlobalState gs)
{
    with (gs.image_viewer)
    {
        Dbt key, data;
        string path0 = path.get_key(gs.lsblk);
        key = path0;
        //writefln("GET %s", path0.replace("\0", SL));
        auto res = gs.db_map.get(null, &key, &data);

        if (res == 0)
        {
            rectsize = data.to!(RectSize);
        }
    }
}

package void
put_rectsize(GlobalState gs)
{
    with (gs.image_viewer)
    {
        Dbt key, data;
        string path0 = path.get_key(gs.lsblk);
        key = path0;
        data = rectsize;
        auto res = gs.db_map.put(null, &key, &data);
        if (res != 0)
            throw new Exception("Path info to map-db not written");
    }
}

auto
get_image_from_cache(GlobalState gs,
        in string p)
{
    /* EN: Get picture from cache or load it from file
       RU: Получить картинку из кеша или загрузить из файла */
    with(gs.image_viewer)
    {
        auto st = p in image_cache;
        if (st)
        {
            st.tick = SDL_GetTicks();
            last_image_cache_use = SDL_GetTicks();
        }
        else
        {
            auto image = IMG_Load(path.toStringz());

            if (image)
            {
                auto image_texture =
                    SDL_CreateTextureFromSurface(gs.renderer, image);
                image_cache[p] = Texture_Tick(image.w, image.h, image_texture, SDL_GetTicks());
                SDL_FreeSurface(image);
                last_image_cache_use = SDL_GetTicks();
                st = path in image_cache;
            }
        }

        return st;
    }
}

/* EN: clear cache from old entries
   RU: очистить кеш от старых элементов */
void
clear_image_cache(GlobalState gs)
{
    with(gs.image_viewer)
    {
        foreach(k, v; image_cache)
        {
            if (v.tick < last_image_cache_use - 30_000)
            {
                if (v.texture) SDL_DestroyTexture(v.texture);
                image_cache.remove(k);
                //writefln("v.tick = %s < %s. Remove key %s",
                //        v.tick, last_image_cache_use - 300_000, k);
            }
        }
    }
}

void
draw_image(GlobalState gs)
{
    with(gs.image_viewer)
    {
        clear_image_cache(gs);
        if (texture_tick && texture_tick.texture)
        {
            if (path in gs.selection_hash)
            {
                int r = SDL_RenderCopy(gs.renderer, gs.texture_blue, null, null);
                if (r < 0)
                {
                    writefln( "draw_image(): Error while render copy: %s", fromStringz(SDL_GetError()) );
                }
            }

            int r = SDL_RenderCopyEx(gs.renderer, texture_tick.texture, null, &gs.image_viewer.rect, rectsize.angle,
                        null, SDL_FLIP_NONE);
            if (r < 0)
            {
                writefln( "draw_image(): Error while render copy: %s", fromStringz(SDL_GetError()) );
            }

            if (path in gs.selection_hash &&
                    abs(gs.image_viewer.rect.w - gs.screen.w) < 20 && (gs.image_viewer.rect.h - gs.screen.h) < 20)
            {
                auto rect = SDL_Rect(0, 0, gs.screen.w, 32);
                r = SDL_RenderCopy(gs.renderer, gs.texture_blue, null, &rect);
                if (r < 0)
                {
                    writefln( "draw_image(): Error while render copy: %s", fromStringz(SDL_GetError()) );
                }
            }
        }
    }
}

private void
positions_in_directories_recursive(GlobalState gs, string p, ssize_t lev = 0)
{
    with (gs.image_viewer)
    {
        if (lev == 0)
        {
            files = [];
            positions = [];
        }

        string[] paths;

        try
        {
            foreach (string name; dirEntries(p, SpanMode.shallow))
            {
                paths ~= name;
            }
        }
        catch (FileException e)
        {
            return;
        }

        sort!("a < b")(paths);

        bool found = false;
        foreach (i, name; paths)
        {
            if (path.startsWith(name) && (name.length+1 > path.length || path[name.length] == SL[0]))
            {
                found = true;
                positions ~= i;
                files ~= paths;

                if (name == path)
                {
                    level = lev;
                }
                else
                {
                    positions_in_directories_recursive(gs, name, level+1);
                }
                break;
            }
        }
        assert(found);
    }
}

private void
calculate_positions_in_directories(GlobalState gs)
{
    with (gs.image_viewer)
    {
        selections = [];

        foreach (selection; gs.selection_hash.byKey())
        {
            if ( mime(selection) != "inode/directory" ) continue;

            bool found_subdirs = false;
            //writefln("%s", selection);
            rescan_selections:
            foreach (i, ref s; selections)
            {
                if ( selection.startsWith(s) )
                {
                    //writefln("1. %s starts with %s", selection, s);
                    // Do nothing, the super-directory in the selections
                    found_subdirs = true;
                }
                else if ( s.startsWith(selection) )
                {
                    //writefln("2. %s starts with %s", s, selection);
                    // selections consists subdirectory
                    if (found_subdirs)
                    {
                        //writefln("before selections=%s", selections);
                        if (i < selection.length-1)
                            selections = selections[0..i] ~ selections[i+1..$];
                        else
                            selections = selections[0..i];
                        //writefln("after selections=%s", selections);
                        goto rescan_selections;
                    }
                    else
                    {
                        s = selection;
                        found_subdirs = true;
                    }
                }
            }

            if (!found_subdirs)
            {
                selections ~= selection;
            }
        }

        if (selections.length == 0)
        {
            string dir = getParent(path);
            selections ~= dir;
        }

        /*writefln("selections = %s", selections);*/

        sel = -1;
        foreach (i, s; selections)
        {
            if (path.startsWith(s))
            {
                sel = i;
            }
        }

        if (sel >= 0)
        {
            positions_in_directories_recursive(gs, selections[sel]);
        }

        /*writefln("positions = %s", positions);
        writefln("files = %s", files);
        writefln("level = %s", level);*/
    }
}

package void
image_next(GlobalState gs)
{
    with (gs.image_viewer)
    {
        int sel0_count = 0;
        bool found_image = false;
        do
        {
            if (sel >= 0 && level >= 0)
            {
                bool level_dec;
                do
                {
                    level_dec = false;
                    positions[level]++;
                    //writefln("positions[%s] = %s", level, positions[level]);
                    //writefln("files = %s", files);
                    if ( positions[level] >= files[level].length )
                    {
                        //writefln("files[%s] exceeded", level);
                        files = files[0..$-1];
                        positions = positions[0..$-1];
                        level--;
                        level_dec = true;
                        if (level == -1)
                        {
                            //writefln("level == -1");
                            sel++;
                            if (sel >= selections.length)
                            {
                                //writefln("sel = 0");
                                sel = 0;
                                sel0_count++;
                            }
                        }
                    }
                } while (level_dec && level >= 0);
            }
            else if (sel == -1)
            {
                sel = 0;
                sel0_count++;
            }

            //writefln("level = %s", level);
            if (level == -1)
            {
                string[] paths;
                try
                {
                    foreach (string name; dirEntries(selections[sel], SpanMode.shallow))
                    {
                        paths ~= name;
                    }
                }
                catch (FileException e)
                {
                    return;
                }

                sort!("a < b")(paths);

                positions ~= 0;
                files ~= paths;
                level++;
                //writefln("0 paths added");
            }

            do
            {
                if (files[level].length == 0) break;
                string p = files[level][positions[level]]; 
                    //writefln("p=%s", p);
                string mime_type = mime(p);
                if (mime_type == "inode/directory")
                {
                    //writefln("directory");
                    string[] paths;

                    try
                    {
                        foreach (string name; dirEntries(p, SpanMode.shallow))
                        {
                            paths ~= name;
                        }
                    }
                    catch (FileException e)
                    {
                        return;
                    }

                    if (paths.length == 0)
                    {
                        break;
                    }

                    sort!("a < b")(paths);

                    positions ~= 0;
                    files ~= paths;
                    level++;
                }
                else if (mime_type.startsWith("image/"))
                {
                    //writefln("image!");
                    auto pathmnt = PathMnt(gs.lsblk, p);
                    image_viewer(gs, pathmnt);
                    found_image = true;
                    break;
                }
                else
                {
                    break;
                }
            } while (true);
        } while(sel0_count < 2 && !found_image);
    }
}

package void
image_prev(GlobalState gs)
{
    with (gs.image_viewer)
    {
        int seln_count = 0;
        bool found_image = false;
        do
        {
            if (sel >= 0 && level >= 0)
            {
                bool level_dec;
                do
                {
                    level_dec = false;
                    positions[level]--;
                    //writefln("positions[%s] = %s", level, positions[level]);
                    //writefln("files = %s", files);
                    if ( positions[level] < 0 )
                    {
                        //writefln("files[%s] exceeded", level);
                        files = files[0..$-1];
                        positions = positions[0..$-1];
                        level--;
                        level_dec = true;
                        if (level == -1)
                        {
                            //writefln("level == -1");
                            sel--;
                            if (sel < 0)
                            {
                                //writefln("sel = 0");
                                sel = selections.length-1;
                                seln_count++;
                            }
                        }
                    }
                } while (level_dec && level >= 0);
            }
            else if (sel == -1)
            {
                sel = selections.length-1;
                seln_count++;
            }

            //writefln("level = %s", level);
            if (level == -1)
            {
                string[] paths;
                try
                {
                    foreach (string name; dirEntries(selections[sel], SpanMode.shallow))
                    {
                        paths ~= name;
                    }
                }
                catch (FileException e)
                {
                    return;
                }

                sort!("a < b")(paths);

                positions ~= paths.length-1;
                files ~= paths;
                level++;
                //writefln("0 paths added");
            }

            do
            {
                if (files[level].length == 0) break;
                string p = files[level][positions[level]]; 
                    //writefln("p=%s", p);
                string mime_type = mime(p);
                if (mime_type == "inode/directory")
                {
                    //writefln("directory");
                    string[] paths;

                    try
                    {
                        foreach (string name; dirEntries(p, SpanMode.shallow))
                        {
                            paths ~= name;
                        }
                    }
                    catch (FileException e)
                    {
                        return;
                    }

                    if (paths.length == 0)
                    {
                        break;
                    }

                    sort!("a < b")(paths);

                    positions ~= paths.length-1;
                    files ~= paths;
                    level++;
                }
                else if (mime_type.startsWith("image/"))
                {
                    //writefln("image!");
                    auto pathmnt = PathMnt(gs.lsblk, p);
                    image_viewer(gs, pathmnt);
                    found_image = true;
                    break;
                }
                else
                {
                    break;
                }
            } while (true);
        } while(seln_count < 2 && !found_image);
    }
}
