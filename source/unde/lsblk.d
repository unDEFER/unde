module unde.lsblk;

import unde.lib;
import unde.slash;

import std.conv;
import std.string;
import std.process;
import std.array;
import std.regex;

version (Windows)
{
import core.sys.windows.winbase;
import core.sys.windows.winnt;
import core.stdc.stdarg;
import std.utf;
import std.stdio;
import std.format;
}

struct LsblkInfo{
    string name;
    string mountpoint;
    string fstype;
    string label;
    string uuid;
    ulong  size;
    ulong  used;
    ulong  avail;
}

version (Posix)
{
private string slashXToString(string str)
{
    string res = "";
    for (int i=0; i < str.length; i++)
    {
        if (str.length - i >= 4)
        {
            if (str[i] == '\\' && str[i+1] == 'x')
            {
                string s;
                res ~= parse!ubyte(s=str[i+2..i+4], 16);
                i+=3;
                continue;
            }
        }
        res ~= str[i];
    }
    return res;
}

unittest
{
    assert(slashXToString("a\\x20b") == "a b");
    assert(slashXToString("ab\\x20") == "ab ");
    assert(slashXToString("ab\\x2") == "ab\\x2");
}

void df(ref LsblkInfo lsblk_info)
{
    auto df_pipes = pipeProcess(["df", "--output=size,used,avail", lsblk_info.mountpoint], Redirect.stdout);
    scope(exit) wait(df_pipes.pid);

    int l=0;
    foreach (df_line; df_pipes.stdout.byLine)
    {
        if (l == 1)
        {
            auto match = matchFirst(df_line, regex(`(\d+) +(\d+) +(\d+)`));
            if (match)
            {
                lsblk_info.size = to!ulong(match[1])*1024;
                lsblk_info.used = to!ulong(match[2])*1024;
                lsblk_info.avail = to!ulong(match[3])*1024;
            }
        }
        l++;
    }
}
}

version(Windows)
{
void df(ref LsblkInfo lsblk_info)
{
	uint sectors_per_cluster;
	uint bytes_per_sector;
	uint number_of_free_clusters;
	uint total_number_of_clusters;

	auto res = GetDiskFreeSpace(
			toUTF16z(lsblk_info.name~"\\"),
			&sectors_per_cluster,
			&bytes_per_sector,
			&number_of_free_clusters,
			&total_number_of_clusters);
	if (!res)
	{
		throw new Exception("GetDiskFreeSpace: "~GetErrorMessage());
	}

	lsblk_info.size = cast(ulong)total_number_of_clusters * sectors_per_cluster * bytes_per_sector;
	lsblk_info.avail = cast(ulong)number_of_free_clusters * sectors_per_cluster * bytes_per_sector;
	lsblk_info.used = lsblk_info.size - lsblk_info.avail;
}
}

void lsblk(ref LsblkInfo[string] lsblk)
{
    version(Posix)
    {
    auto pipes = pipeProcess(["lsblk", "-rno", "NAME,MOUNTPOINT,FSTYPE,LABEL,UUID"], Redirect.stdout);
    scope(exit) wait(pipes.pid);

    foreach (line; pipes.stdout.byLine)
    {
        LsblkInfo lsblk_info;

        foreach(i, arg; split(line, " "))
        {
            string im_arg = arg.idup();
            switch (i)
            {
                case 0:
                    lsblk_info.name = slashXToString(im_arg);
                    break;
                case 1:
                    lsblk_info.mountpoint = slashXToString(im_arg);
                    break;
                case 2:
                    lsblk_info.fstype = slashXToString(im_arg);
                    break;
                case 3:
                    lsblk_info.label = slashXToString(im_arg);
                    break;
                case 4:
                    lsblk_info.uuid = slashXToString(im_arg);
                    break;
                default:
                    assert(0, "lsblk returned line with more than 2 spaces");
            }
        }

        if (lsblk_info.mountpoint > "" && lsblk_info.mountpoint != "[SWAP]")
        {
            df(lsblk_info);
            lsblk[lsblk_info.mountpoint] = lsblk_info;
        }
    }
    }
    else version(Windows)
    {
        LsblkInfo lsblk_info;
        lsblk_info.name = "My Computer";
        lsblk_info.mountpoint = SL;
        lsblk_info.uuid = "my_computer";
        lsblk[lsblk_info.mountpoint] = lsblk_info;
        LsblkInfo *mycomp_info = &lsblk[lsblk_info.mountpoint];

	auto drives = GetLogicalDrives();
	if (drives == 0)
	{
		throw new Exception("GetLogicalDrives: "~GetErrorMessage());
	}
	foreach (i; 0..32)
	{
		char letter = cast(char)('A' + i);
		if (drives & (1 << i))
		{
			wchar[1024] volumename;
			uint serialnumber;
			uint maximum_components_length;
			uint file_system_flags;
			wchar[1024] file_system_name;

			auto res = GetVolumeInformation(
					toUTF16z(letter~":\\"),
					volumename.ptr,
					volumename.length,
					&serialnumber,
					&maximum_components_length,
					&file_system_flags,
					file_system_name.ptr,
					file_system_name.length);
			lsblk_info = LsblkInfo();
			lsblk_info.name = letter~":";
			lsblk_info.mountpoint = letter~":";
			if (res)
			{
				lsblk_info.fstype = to!(char[])(from_char_array(file_system_name));
				lsblk_info.uuid = format("%X", serialnumber);
				lsblk_info.label = to!string(from_char_array(volumename));

				df(lsblk_info);

				/*writefln("%s:", letter);
				writefln("\tvolumename=%s", to!string(from_char_array(volumename)));
				writefln("\tserialnumber=%X", serialnumber);
				writefln("\tmaximum_components_length=%d", maximum_components_length);
				writefln("\tfile_system_flags=%X", file_system_flags);
				writefln("\tfile_system_name=%s", to!(char[])(from_char_array(file_system_name)));
				writefln("\tsize=%s", lsblk_info.size);
				writefln("\tused=%s", lsblk_info.used);
				writefln("\tavail=%s", lsblk_info.avail);*/

				mycomp_info.size += lsblk_info.size;
				mycomp_info.used += lsblk_info.used;
				mycomp_info.avail += lsblk_info.avail;
			}
			else
			{
				lsblk_info.label = GetErrorMessage();
				//writefln("%s: %s", letter, lsblk_info.label);
			}
			lsblk[lsblk_info.mountpoint] = lsblk_info;

		}
	}
    }
}
