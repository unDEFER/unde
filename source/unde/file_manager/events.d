module unde.file_manager.events;

import unde.global_state;
import unde.clickable;
import unde.lib;
import unde.file_manager.remove_paths;
import unde.file_manager.copy_paths;
import unde.file_manager.move_paths;
import unde.command_line.events;
import unde.viewers.image_viewer.events;
import unde.viewers.text_viewer.events;
import unde.keybar.settings;
import unde.keybar.lib;
import unde.marks;
import unde.tick;
import unde.scan;
import unde.path_mnt;
import unde.slash;
import unde.translations.lib;

import berkeleydb.all;
import derelict.sdl2.sdl;

import std.utf;
import std.stdio;
import std.string;
import std.conv;
import std.format;
import std.datetime;
import std.functional;

import std.file;

void nothing(GlobalState gs)
{
}

void quit(GlobalState gs)
{
    gs.finish=true;
}

void restart(GlobalState gs)
{
    gs.finish=true;
    gs.restart=true;
}

void mark(GlobalState gs)
{
    gs.mark=true;
}

void unmark(GlobalState gs)
{
    gs.unmark=true;
}

void gomark(GlobalState gs)
{
    gs.gomark=true;
}

void cancel_mark(GlobalState gs)
{
    gs.mark=false;
    gs.unmark=false;
    gs.gomark=false;
}

void
rescan(GlobalState gs)
{
    rescan_path(gs, PathMnt(gs.lsblk, gs.full_current_path));
}

void
deselect_all(GlobalState gs)
{
    gs.selection_hash = null;
    calculate_selection_sub(gs);
    gs.dirty = true;
}

void clear_messages(GlobalState gs)
{
    gs.msg_stamp = Clock.currTime().toUnixTime() - 10;
    gs.dirty = true;
}

auto get_copy_or_move(GlobalState gs, string copy_or_move)
{
    return (GlobalState gs)
    {
        int copy_or_move_to_the_same_directory = 0;
        int copy_or_move_to_subdirectory = 0;
        foreach (selection; gs.selection_hash.byKey())
        {
            string parent = 
                getParent(selection);
            if (parent == "") parent = SL;
            if (parent == gs.full_current_path)
                copy_or_move_to_the_same_directory++;

            if ( gs.full_current_path.startsWith(selection) )
                copy_or_move_to_subdirectory++;
        }

        if (copy_or_move_to_the_same_directory &&
                gs.selection_hash.length > 1)
        {
            string msg;
            if (copy_or_move == "copy")
                msg = format(_("Copy to the same directory works only for exactly 1 selection"));
            else
                msg = format(_("Rename (move to the same directory) works only for exactly 1 selection"));
            gs.messages ~= ConsoleMessage(
                    SDL_Color(0xFF, 0xFF, 0xFF, 0xFF),
                    msg,
                    SDL_GetTicks() );
            writeln(msg);
        }
        else if (copy_or_move_to_subdirectory)
        {
            string msg;
            if (copy_or_move == "copy")
                msg = format(_("Can't copy to a subdirectory"));
            else
                msg = format(_("Can't move to a subdirectory"));
            gs.messages ~= ConsoleMessage(
                    SDL_Color(0xFF, 0x00, 0x00, 0xFF),
                    msg,
                    SDL_GetTicks() );
            writeln(msg);
        }
        else
        {
            if (copy_or_move_to_the_same_directory &&
                    gs.selection_hash.length == 1)
            {
                gs.shift_copy_or_move = gs.shift;
                string path = gs.selection_hash.keys[0];
                gs.animation_info[path] =
                    AnimationInfo();
                gs.animation_info[path].parent =
                    gs.full_current_path;
                if (copy_or_move == "copy")
                    gs.animation_info[path].type =
                        NameType.Copy;
                else
                    gs.animation_info[path].type =
                        NameType.Move;

                gs.keybar.input_mode = true;
                setup_keybar(gs);
                gs.redraw_fast = true;
                change_current_dir(gs, 
                        (ref RectSize rectsize)
                        {
                        if (rectsize.show_info != 
                                InfoType.CreateDirectory &&
                                rectsize.show_info != InfoType.Copy &&
                                rectsize.show_info != InfoType.Move)
                        {
                        rectsize.show_info = InfoType.Copy;
                        string name = 
                        path[path.lastIndexOf(SL)+1..$];
                        if (copy_or_move == "copy")
                        gs.enter_names[gs.current_path] =
                        EnterName(NameType.Copy, name, 
                                cast(int)name.length);
                        else
                        gs.enter_names[gs.current_path] =
                        EnterName(NameType.Move, name, 
                                cast(int)name.length);
                        }
                        } );
            }
            else
            {
                // copy_or_move_paths algorithm wants SL at the end
                string path = gs.full_current_path ~ SL;
                if (copy_or_move == "copy")
                    copy_paths(gs, gs.selection_hash.keys, path, gs.shift);
                else
                    move_paths(gs, gs.selection_hash.keys, path, gs.shift);
                gs.dirty = true;
            }
        }
    };
}

void start_create_directory(GlobalState gs)
{
    gs.keybar.input_mode = true;
    setup_keybar(gs);
    gs.redraw_fast = true;
    change_current_dir(gs, 
            (ref RectSize rectsize)
            {
            if (rectsize.show_info != InfoType.CreateDirectory &&
                    rectsize.show_info != InfoType.Copy &&
                    rectsize.show_info != InfoType.Move)
            {
            rectsize.show_info = InfoType.CreateDirectory;
            gs.enter_names[gs.current_path] = 
            EnterName(NameType.CreateDirectory, "", 0);
            }
            } );
}

void remove_selection(GlobalState gs)
{
    bool not_fit_on_screen = false;
    foreach(path, ref rect; gs.selection_hash)
    {
        SDL_Rect sdl_rect = rect.to_screen(gs.screen);

        if (sdl_rect.x < 0 || sdl_rect.y < 0 ||
                (sdl_rect.x+sdl_rect.w) > gs.screen.w ||
                (sdl_rect.y+sdl_rect.h) > gs.screen.h)
        {
            not_fit_on_screen = true;
            break;
        }
    }

    if (not_fit_on_screen)
    {
        string msg = format(_("Go (up) to directory which fully covers selection to confirm removing %d items"),
                gs.selection_hash.length);
        gs.messages ~= ConsoleMessage(
                SDL_Color(0xFF, 0xFF, 0xFF, 0xFF),
                msg,
                SDL_GetTicks() );
        writeln(msg);
    }
    else
    {
        remove_paths(gs, gs.selection_hash.keys);
    }
}

void change_sorting(GlobalState gs)
{
    change_current_dir(gs, 
            (ref RectSize rectsize)
            {
            rectsize.sort = cast(SortType)( (rectsize.sort+1)%(SortType.max+1) );
            } );
}

void filemanager_left(GlobalState gs)
{
    with(gs.enter_names[gs.current_path])
    {
        if (pos > 0)
            pos -= name.strideBack(pos);
    }
    gs.dirty = true;
}

void filemanager_right(GlobalState gs)
{
    with(gs.enter_names[gs.current_path])
    {
        if (pos < name.length)
            pos += name.stride(pos);
    }
    gs.dirty = true;
}

void filemanager_enter(GlobalState gs)
{
    with(gs.enter_names[gs.current_path])
    {
        if (name != "")
        {
            final switch (type)
            {
                case NameType.CreateDirectory:
                    try{
                        string path = gs.full_current_path ~ SL ~
                            name;
                        mkdir(path);
                        gs.animation_info[path] =
                            AnimationInfo();
                        gs.animation_info[path].parent =
                            gs.full_current_path;
                        gs.animation_info[path].type =
                            NameType.CreateDirectory;
                        gs.dirty = true;
                    }
                    catch (FileException exp)
                    {
                        string msg = format("Failed Create Directory: %s", exp.msg);
                        gs.messages ~= ConsoleMessage(
                                SDL_Color(0xFF, 0x00, 0x00, 0xFF),
                                msg,
                                SDL_GetTicks()
                                );
                        writeln(msg);
                    }
                    break;

                case NameType.Copy:
                    goto case;
                case NameType.Move:
                    string path = gs.full_current_path ~ SL ~
                        name;
                    string[] selection = gs.selection_hash.keys;
                    try
                    {
                        auto de = DirEntry(selection[0]);
                        if (!de.isSymlink() && de.isDir())
                        {
                            selection[0] ~= SL;//It is the single entry
                        }
                    }
                    catch(Exception e)
                    {
                        // Ignore errors
                    }

                    if (type == NameType.Copy)
                    { 
                        copy_paths(gs, selection.idup(), path, gs.shift_copy_or_move);
                    }
                    else
                    {
                        move_paths(gs, selection.idup(), path, gs.shift_copy_or_move);
                    }
                    gs.animation_info[path] =
                        AnimationInfo();
                    gs.animation_info[path].parent =
                        gs.full_current_path;
                    gs.animation_info[path].type =
                        type;
                    gs.animation_info[path].stage =
                        1;
                    gs.dirty = true;
                    break;
            }
        }
        filemanager_escape(gs);
    }
}

void filemanager_escape(GlobalState gs)
{
    gs.keybar.input_mode = false;

    gs.redraw_fast = false;
    change_current_dir(gs, 
            (ref RectSize rectsize)
            {
            rectsize.show_info = InfoType.None;
            gs.enter_names.remove(gs.current_path);
            } );

    gs.last_escape = SDL_GetTicks();
}

void filemanager_backscape(GlobalState gs)
{
    RectSize rectsize = getRectSize(gs);
    with(gs.enter_names[gs.current_path])
    {
        if ( (rectsize.show_info == InfoType.CreateDirectory ||
                    rectsize.show_info == InfoType.Copy ||
                    rectsize.show_info == InfoType.Move) &&
               name > "" && pos > 0 )
        {
            int sb = name.strideBack(pos);
            name = (name[0..pos-sb] ~ name[pos..$]).idup();
            pos -= sb;
            gs.dirty = true;
        }
    }
}

auto get_mark(string mark)
{
    return (GlobalState gs)
    {
        unde.marks.mark(gs, mark);
        gs.mark = false;
    };
}

auto get_unmark(string mark)
{
    return (GlobalState gs)
    {
        unde.marks.unmark(gs, mark);
        gs.unmark = false;
    };
}

auto get_gomark(string mark)
{
    return (GlobalState gs)
    {
        unde.marks.go_mark(gs, mark);
        gs.gomark = false;
    };
}

void process_event(GlobalState gs, ref SDL_Event event)
{
    switch( event.type )
    {
        case SDL_TEXTINPUT:
            RectSize rectsize = getRectSize(gs);
            if (rectsize.show_info == InfoType.CreateDirectory ||
                    rectsize.show_info == InfoType.Copy ||
                    rectsize.show_info == InfoType.Move)
            {
                with(gs.enter_names[gs.current_path])
                {
                    char[] input = fromStringz(cast(char*)event.text.text);
                    name = 
                        (name[0..pos] ~
                        input ~
                        name[pos..$]).idup();
                    pos += input.length;
                    gs.dirty = true;
                }
            }
            break;

        case SDL_MOUSEMOTION:
            if (gs.mouse_buttons & unDE_MouseButtons.Left &&
                    event.motion.x < gs.screen.w)
            {
                gs.screen.x -= cast(double)(event.motion.xrel)*gs.screen.scale;
                gs.screen.y -= cast(double)(event.motion.yrel)*gs.screen.scale;
            }

            gs.mousex = event.motion.x * gs.screen.scale + gs.screen.x;
            gs.mousey = event.motion.y * gs.screen.scale + gs.screen.y;
            gs.mouse_screen_x = event.motion.x;
            gs.mouse_screen_y = event.motion.y;
            gs.moved_while_click++;

            if (gs.mouse_buttons & unDE_MouseButtons.Right)
            {
                process_click(gs.right_clickable_list, gs.mouse_screen_x, gs.mouse_screen_y, 1);
            }
            break;
            
        case SDL_MOUSEBUTTONDOWN:
            switch (event.button.button)
            {
                case SDL_BUTTON_LEFT:
                    gs.mouse_buttons |= unDE_MouseButtons.Left;
                    gs.moved_while_click = 0;
                    break;
                case SDL_BUTTON_MIDDLE:
                    gs.mouse_buttons |= unDE_MouseButtons.Middle;
                    break;
                case SDL_BUTTON_RIGHT:
                    gs.mouse_buttons |= unDE_MouseButtons.Right;
                    process_click(gs.right_clickable_list, gs.mouse_screen_x, gs.mouse_screen_y, 0);
                    break;
                default:
                    break;
            }
            break;
            
        case SDL_MOUSEBUTTONUP:
            switch (event.button.button)
            {
                case SDL_BUTTON_LEFT:
                    gs.mouse_buttons &= ~unDE_MouseButtons.Left;
                    if (!gs.moved_while_click)
                    {
                        if (SDL_GetTicks() - gs.last_left_click < DOUBLE_DELAY)
                        {
                            process_click(gs.double_clickable_list, gs.mouse_screen_x, gs.mouse_screen_y);
                        }
                        else
                        {
                            process_click(gs.clickable_list, gs.mouse_screen_x, gs.mouse_screen_y);
                        }
                        gs.last_left_click = SDL_GetTicks();
                    }
                    break;
                case SDL_BUTTON_MIDDLE:
                    gs.mouse_buttons &= ~unDE_MouseButtons.Middle;
                    process_click(gs.middle_clickable_list, gs.mouse_screen_x, gs.mouse_screen_y, 2);
                    break;
                case SDL_BUTTON_RIGHT:
                    gs.mouse_buttons &= ~unDE_MouseButtons.Right;
                    if (SDL_GetTicks() - gs.last_right_click < DOUBLE_DELAY)
                    {
                        process_click(gs.double_right_clickable_list, gs.mouse_screen_x, gs.mouse_screen_y);
                    }
                    process_click(gs.right_clickable_list, gs.mouse_screen_x, gs.mouse_screen_y, 2);
                    gs.last_right_click = SDL_GetTicks();
                    break;
                default:
                    break;
            }
            break;

        case SDL_MOUSEWHEEL:
            while (event.wheel.y > 0)
            {
                gs.screen.scale /= 1.0905;
                event.wheel.y--;
            }
            while (event.wheel.y < 0)
            {
                gs.screen.scale *= 1.0905;
                event.wheel.y++;
            }
            gs.screen.x = gs.mousex - gs.mouse_screen_x*gs.screen.scale;
            gs.screen.y = gs.mousey - gs.mouse_screen_y*gs.screen.scale;
            //writeln("scale=", gs.screen.scale);
            break;
            
        case SDL_JOYAXISMOTION:
            /* Do something with event.jaxis */
            break;
            
        case SDL_JOYBALLMOTION:
            /* Do something with event.jball */
            break;
            
        case SDL_JOYHATMOTION:
            /* Do something with event.jhat */
            break;
            
        case SDL_JOYBUTTONDOWN:
            /* Do something with event.jbutton */
            break;
            
        case SDL_JOYBUTTONUP:
            /* Do something event.jbutton */
            break;

        case SDL_QUIT:
            /* Do something event.quit */
            gs.finish=true;
            break;
            
        case SDL_SYSWMEVENT:
            /* Do something with event.syswm */
            break;
            
        case SDL_WINDOWEVENT:
            /*if (event.window.event == SDL_WINDOWEVENT_RESIZED)
                diz_setvideomode(event.window.data1, event.window.data2, 
                  dizvideomode.flags & SDL_WINDOW_FULLSCREEN_DESKTOP);*/
            break;
        default:
            writeln("Ignored event: "~to!string(event.type));
            break;
    }
}

bool setup_keybar_mark(GlobalState gs)
{
    if (gs.mark || gs.unmark || gs.gomark)
    {
        gs.keybar.handlers.clear();
        gs.keybar.handlers_down.clear();
        gs.keybar.handlers_double.clear();

        gs.keybar.handlers[SDL_SCANCODE_ESCAPE] = KeyHandler(toDelegate(&cancel_mark), "Cancel", "Esc");
        for (ssize_t i = 0; i < 3; i++)
        {
            for (ssize_t pos = 0; pos < (*gs.keybar.letters)[i].length; pos++)
            {
                string mark = (*gs.keybar.letters)[i][pos];
                if ( mark.length == 1 &&
                        (mark[0] >= '0' && 
                         mark[0] <= '9' ||
                         mark[0] >= 'A' && 
                         mark[0] <= 'Z') )
                {
                    if (gs.mark)
                    {
                        gs.keybar.handlers[(*gs.keybar.scans_cur)[i][pos]] = 
                            KeyHandler(get_mark(mark), "Mark "~mark, mark);
                    }
                    else if (gs.unmark && check_mark(gs, mark))
                    {
                        gs.keybar.handlers[(*gs.keybar.scans_cur)[i][pos]] = 
                            KeyHandler(get_unmark(mark), "Unmark "~mark, mark);
                    }
                    else if (gs.gomark && 
                            (mark[0] >= '0' && mark[0] <= '9' || 
                             check_mark(gs, mark)))
                    {
                        gs.keybar.handlers[(*gs.keybar.scans_cur)[i][pos]] = 
                            KeyHandler(get_gomark(mark), "Go to Mark "~mark, mark);
                    }
                }
            }
        }

        if (!gs.shift)
        {
            gs.keybar.handlers_down[SDL_SCANCODE_LSHIFT] = KeyHandler(toDelegate(&nothing), "Global Mark", "Shift");
            gs.keybar.handlers_down[SDL_SCANCODE_RSHIFT] = KeyHandler(toDelegate(&nothing), "", "");
        }
        return true;
    }
    else return false;
}

void setup_keybar(GlobalState gs)
{
    foreach (uipage; gs.uipages)
    {
        if (uipage.show)
        {
            uipage.set_keybar(gs);
            return;
        }
    }

    final switch (gs.state)
    {
        case State.FileManager:
            if (setup_keybar_mark(gs))
            {
            }
            else if (gs.command_line.enter)
            {
                if (gs.ctrl)
                {
                    setup_keybar_command_line_ctrl(gs);
                }
                else
                {
                    setup_keybar_command_line_default(gs);
                }
            }
            else if (gs.command_line.terminal)
            {
                if (gs.command_line.command_in_focus_id > 0)
                {
                    setup_keybar_terminal_command_focus_in(gs);
                }
                else
                {
                    if (gs.ctrl)
                    {
                        setup_keybar_terminal_ctrl(gs);
                    }
                    else
                    {
                        setup_keybar_terminal(gs);
                    }
                }
            }
            else if (gs.current_path in gs.enter_names)
            {
                gs.keybar.input_mode = true;
                gs.keybar.handlers.clear();
                gs.keybar.handlers_down.clear();
                gs.keybar.handlers_double.clear();
                gs.keybar.handlers_down[SDL_SCANCODE_LEFT] = KeyHandler(toDelegate(&filemanager_left), "Left", "←");
                gs.keybar.handlers_down[SDL_SCANCODE_RIGHT] = KeyHandler(toDelegate(&filemanager_right), "Right", "→");
                gs.keybar.handlers[SDL_SCANCODE_RETURN] = KeyHandler(toDelegate(&filemanager_enter), "Finish Enter", "Enter");
                gs.keybar.handlers[SDL_SCANCODE_ESCAPE] = KeyHandler(toDelegate(&filemanager_escape), "Cancel", "Esc");
                gs.keybar.handlers_down[SDL_SCANCODE_BACKSPACE] = KeyHandler(toDelegate(&filemanager_backscape), "Backspace", "<--");

            }
            else
            {
                gs.keybar.input_mode = false;
                if (gs.ctrl)
                    setup_keybar_filemanager_ctrl(gs);
                else if (gs.shift)
                    setup_keybar_filemanager_shift(gs);
                else
                    setup_keybar_filemanager_default(gs);
            }
            break;

        case State.ImageViewer:
            if (setup_keybar_mark(gs))
            {
            }
            else if (gs.shift)
                setup_keybar_imageviewer_shift(gs);
            else
                setup_keybar_imageviewer_default(gs);
            break;

        case State.TextViewer:
            if (setup_keybar_mark(gs))
            {
            }
            else if (gs.shift)
                setup_keybar_textviewer_shift(gs);
            else
                setup_keybar_textviewer_default(gs);
            break;
    }
}

void
setup_keybar_filemanager_default(GlobalState gs)
{
    gs.keybar.handlers.clear();
    gs.keybar.handlers_down.clear();
    gs.keybar.handlers_double.clear();

    gs.keybar.handlers[SDL_SCANCODE_Q] = KeyHandler(toDelegate(&quit), _("Quit"), "exit.png");
    gs.keybar.handlers[SDL_SCANCODE_PRINTSCREEN] = KeyHandler(toDelegate(&make_screenshot), _("Make screenshot"), "Prt Sc");
    gs.keybar.handlers[SDL_SCANCODE_M] = KeyHandler(toDelegate(&mark), _("Make Mark"), "mark.png");
    gs.keybar.handlers[SDL_SCANCODE_APOSTROPHE] = KeyHandler(toDelegate(&gomark), _("Go To Mark"), "gomark.png");
    gs.keybar.handlers[SDL_SCANCODE_R] = KeyHandler(toDelegate(&rescan), _("Rescan directory"), "rescan.png");
    gs.keybar.handlers[SDL_SCANCODE_A] = KeyHandler(toDelegate(&deselect_all), _("Clear selection"), "deselect.png");
    gs.keybar.handlers_down[SDL_SCANCODE_LSHIFT] = KeyHandler(toDelegate(&setup_keybar_filemanager_shift), "", "Shift");
    gs.keybar.handlers_down[SDL_SCANCODE_RSHIFT] = KeyHandler(toDelegate(&setup_keybar_filemanager_shift), "", "");
    gs.keybar.handlers_down[SDL_SCANCODE_LCTRL] = KeyHandler(toDelegate(&setup_keybar_filemanager_ctrl), "", "Ctrl");
    gs.keybar.handlers_down[SDL_SCANCODE_RCTRL] = KeyHandler(toDelegate(&setup_keybar_filemanager_ctrl), "", "");
    gs.keybar.handlers_double[SDL_SCANCODE_ESCAPE] = KeyHandler(toDelegate(&clear_messages), _("Clear error messages in directories"), "clear_errors.png");
    gs.keybar.handlers[SDL_SCANCODE_C] = KeyHandler(get_copy_or_move(gs, "copy"), _("Copy selection to current directory"), "copy.png");
    gs.keybar.handlers[SDL_SCANCODE_V] = KeyHandler(get_copy_or_move(gs, "move"), _("Move selection to current directory"), "move.png");
    gs.keybar.handlers[SDL_SCANCODE_D] = KeyHandler(toDelegate(&start_create_directory), _("Create Directory"), "create_directory.png");
    gs.keybar.handlers[SDL_SCANCODE_E] = KeyHandler(toDelegate(&remove_selection), _("Remove Selection"), "remove.png");
    gs.keybar.handlers[SDL_SCANCODE_S] = KeyHandler(toDelegate(&change_sorting), _("Change Sort Order"), "sort.png");
    gs.keybar.handlers_double[SDL_SCANCODE_RETURN] = KeyHandler(toDelegate(&turn_on_terminal), _("Open Terminal"), "terminal.png");
}

void
setup_keybar_filemanager_ctrl(GlobalState gs)
{
    gs.keybar.handlers.clear();
    gs.keybar.handlers_down.clear();
    gs.keybar.handlers_double.clear();

    gs.keybar.handlers[SDL_SCANCODE_Q] = KeyHandler(toDelegate(&restart), _("Restart"), "exit.png");
    gs.keybar.handlers[SDL_SCANCODE_SEMICOLON] = KeyHandler(toDelegate(&turn_on_command_line), _("Command line"), "command_line.png");
    gs.keybar.handlers[SDL_SCANCODE_L] = KeyHandler(toDelegate(&turn_on_keybar_settings), _("Keyboard layouts settings"), "keybar");
    gs.keybar.handlers[SDL_SCANCODE_LCTRL] = KeyHandler(toDelegate(&setup_keybar_filemanager_default), "", "Ctrl");
    gs.keybar.handlers[SDL_SCANCODE_RCTRL] = KeyHandler(toDelegate(&setup_keybar_filemanager_default), "", "");
}

void
setup_keybar_filemanager_shift(GlobalState gs)
{
    gs.keybar.handlers.clear();
    gs.keybar.handlers_down.clear();
    gs.keybar.handlers_double.clear();

    gs.keybar.handlers[SDL_SCANCODE_M] = KeyHandler(toDelegate(&unmark), _("Delete Mark"), "unmark.png");
    gs.keybar.handlers[SDL_SCANCODE_C] = KeyHandler(get_copy_or_move(gs, "copy"), _("Copy selection to current directory with deleting not exists files in the source directory"), "copy.png");
    gs.keybar.handlers[SDL_SCANCODE_V] = KeyHandler(get_copy_or_move(gs, "move"), _("Move selection to current directory with deleting not exists files in the source directory"), "move.png");
    gs.keybar.handlers[SDL_SCANCODE_LSHIFT] = KeyHandler(toDelegate(&setup_keybar_filemanager_default), "", "Shift");
    gs.keybar.handlers[SDL_SCANCODE_RSHIFT] = KeyHandler(toDelegate(&setup_keybar_filemanager_default), "", "");
}
