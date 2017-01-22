module unde.translations.lib;

import core.stdc.locale;
import std.process;
import std.string;
import std.stdio;
import core.sys.windows.windows;

static string[string][string] tr;
static string locale;

string _(string str)
{
    if (locale in tr && str in tr[locale])
        return tr[locale][str];
    return str;
}

static this()
{
    version (Posix)
    {
        string lc_messages = setlocale(LC_MESSAGES, null).fromStringz().idup();
        if (lc_messages == "" || lc_messages == "C")
            lc_messages = environment["LANG"];
        if (lc_messages.length > 3 && lc_messages[0..3] == "ru_")
        {
            locale = "ru";
        }
    }
    else
    version (Windows)
    {
	auto lang = 0xFF & GetUserDefaultUILanguage();
	if (lang == LANG_RUSSIAN)
	{
		locale = "ru";
	}
    }
}
