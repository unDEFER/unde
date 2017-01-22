module unde.keybar.settings;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;
import derelict.sdl2.image;

import unde.global_state;
import unde.font;
import unde.keybar.lib;
import unde.guitk.lib;
import unde.guitk.background;
import unde.guitk.label;
import unde.guitk.list;
import unde.guitk.textarea;
import unde.translations.lib;

import std.stdio;
import std.string;
import std.math;
import std.range.primitives;
import std.file;
import std.algorithm.searching;

version(Windows)
{
import berkeleydb.all: ssize_t;
}

ssize_t
get_pos_of_layout(string[] names, string name, ssize_t p = 0)
{
    if (names.length == 0) return -1;

    if (names[$/2] == name)
    {
        return p + names.length/2;
    }
    if (name < names[$/2])
    {
        return get_pos_of_layout(names[0..$/2], name, p);
    }
    else
        return get_pos_of_layout(names[$/2+1..$], name, p + names.length/2 + 1);
}

UIPage create_keybar_settings_ui(GlobalState gs)
{
    UIPage page = new UIPage();

    page.add_entry(gs, new Background(page, gs));
    page.add_entry(gs, new Label(page, gs, _("Choose one or more keyboard layouts:"),
            15, 15));
    auto filter_label = new Label(page, gs, _("Filter:"), 15, 60);
    page.add_entry(gs, filter_label);
    SDL_Rect filter_rect;
    filter_rect.x = filter_label.rect.x + filter_label.rect.w + 5;
    filter_rect.y = 60;
    filter_rect.w = gs.screen.w/2 - 15 - filter_rect.x;
    filter_rect.h = 30;
    auto filter_textarea = new TextArea(page, filter_rect);

    SDL_Rect layouts_rect;
    layouts_rect.x = 15;
    layouts_rect.y = 105;
    layouts_rect.w = gs.screen.w/2 - 15 - layouts_rect.x;
    layouts_rect.h = cast(int)(gs.screen.h*0.83 - 15 - layouts_rect.y);
    auto layouts_list = new List(page, layouts_rect, gs.keybar.layout_names);

    string[] selected_layouts;
    foreach (layout_mode; gs.keybar.layout_modes)
    {
        string layout_string = layout_mode.name ~ " - " ~ layout_mode.short_name;
        selected_layouts ~= layout_string;
        ssize_t pos = get_pos_of_layout(gs.keybar.layout_names, layout_string);
        layouts_list.selected[pos] = true;
    }
    
    filter_textarea.on_change = (GlobalState gs) {
        layouts_list.filter = filter_textarea.text;
    };

    page.add_entry(gs, filter_textarea);
    page.add_entry(gs, layouts_list);
    
    page.add_entry(gs, new Label(page, gs, _("You have chosen:"),
            gs.screen.w/2 + 15, 15));

    SDL_Rect chosen_rect;
    chosen_rect.x = gs.screen.w/2 + 15;
    chosen_rect.y = 60;
    chosen_rect.w = gs.screen.w/2 - 30;
    chosen_rect.h = cast(int)(gs.screen.h*0.83/2 - 15 - chosen_rect.y);

    auto chosen_list = new List(page, chosen_rect, selected_layouts, 1);

    chosen_list.selected[gs.keybar.mode] = 1;

    layouts_list.on_select = (GlobalState gs, ssize_t pos) {
        chosen_list.list ~= layouts_list.list[pos];
        ssize_t short_pos = layouts_list.list[pos].lastIndexOf(" - ");
        string short_name = layouts_list.list[pos][short_pos+3..$];
        gs.keybar.layout_modes ~= &gs.keybar.layouts[short_name];

        save_keybar_settings(gs);
    };

    layouts_list.on_deselect = (GlobalState gs, ssize_t pos) {
        auto found = chosen_list.list.find(layouts_list.list[pos]);
        if (found.length > 0)
        {
            ssize_t cpos = chosen_list.list.length - found.length;
            chosen_list.list = chosen_list.list[0..cpos] ~ chosen_list.list[cpos+1..$];
            gs.keybar.layout_modes = gs.keybar.layout_modes[0..cpos] ~ gs.keybar.layout_modes[cpos+1..$];
            if (gs.keybar.mode >= cpos)
                gs.keybar.mode--;
            chosen_list.selected.clear();
            chosen_list.selected[gs.keybar.mode] = 1;

            save_keybar_settings(gs);
        }
    };

    chosen_list.pre_draw = (GlobalState gs)
    {
        chosen_list.selected.clear();
        chosen_list.selected[gs.keybar.mode] = 1;
    };

    page.add_entry(gs, chosen_list);

    page.add_entry(gs, new Label(page, gs, _("Choose modifiers to change layouts:"),
            gs.screen.w/2 + 15, cast(int)(gs.screen.h*0.83/2 + 15)));

    SDL_Rect modifiers_rect;
    modifiers_rect.x = gs.screen.w/2 + 15;
    modifiers_rect.y = cast(int)(gs.screen.h*0.83/2 + 60);
    modifiers_rect.w = gs.screen.w/2 - 30;
    modifiers_rect.h = cast(int)(gs.screen.h*0.83 - 15 - modifiers_rect.y);

    auto modifiers_list = new List(page, modifiers_rect, gs.keybar.layout_changer_names, 1);

    auto found = gs.keybar.layout_changer_values.find(gs.keybar.changer);
    if (found.length > 0)
    {
        ssize_t cpos = gs.keybar.layout_changer_values.length - found.length;
        modifiers_list.selected[cpos] = true;
    }

    modifiers_list.on_select = (GlobalState gs, ssize_t pos) {
        gs.keybar.changer = gs.keybar.layout_changer_values[pos];

        save_keybar_settings(gs);
    };

    page.add_entry(gs, modifiers_list);

    page.add_entry(gs, new Label(page, gs, _("Try text input here:"),
            15, cast(int)(gs.screen.h*0.83 + 15)));

    SDL_Rect test_rect;
    test_rect.x = 15;
    test_rect.y = cast(int)(gs.screen.h*0.83 + 60);
    test_rect.w = gs.screen.w - 30;
    test_rect.h = cast(int)(gs.screen.h*0.17 - 75);
    auto test_textarea = new TextArea(page, test_rect);
    page.add_entry(gs, test_textarea);

    if (gs.keybar.keybar_settings_needed)
        page.show = true;

    return page;
}

void
turn_on_keybar_settings(GlobalState gs)
{
    gs.uipages["keybar_settings"].show = true;
}
