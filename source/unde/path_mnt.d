module unde.path_mnt;

import unde.global_state;
import unde.lib;
import unde.lsblk;
import unde.slash;

import std.stdio;
import std.string;
import std.format;

import std.file;
import core.sys.posix.sys.types;

version (Windows)
{
import berkeleydb.all: ssize_t;
}

struct PathMnt
{
    string path;
    string _next;
    string mnt;
    version (Windows)
    {
	alias char dev_t;
    }
    dev_t dev;
    alias _next this;

    this(string p)
    {
        path = p;
        mnt = p;
        _next = p;

	version(Posix)
	{
        DirEntry de = DirEntry(p);
        dev = de.statBuf.st_dev;
	}
	else version(Windows)
	{
	dev=p[0];
	//assert(p[1] == ':');
	}
    }

    this(ref LsblkInfo[string] lsblk, string path)
    out
    {
        assert(this.path == path, 
                format("this.path=%s, path=%s", this.path, path));
    }
    body
    {
    if (path.length > 1 && path[0] == path[1] && path[0] == SL[0])
        path = path[1..$];
	version(Windows)
	{
	if (path.length > 1 && path[1] == ':')
		this(path[0..2]);
	else
		this(SL);
	}
	else
	{
	this(SL);
	}
        string wrkpath = this.path;
        while (wrkpath < path)
        {
	    bool found = false;
	    version (Windows)
	    {
		    if (wrkpath == SL && path[1] == ':')
		    {
			    wrkpath = path[0..2];
			    found = true;
		    }
	    }
	    if (!found)
	    {
		    string after = path[wrkpath.length+1 .. $];
                    if (wrkpath[$-1] == SL[0]) after = path[wrkpath.length .. $];
		    //writefln("wrkpath=%s, path=%s, after=%s", wrkpath, path, after);
		    ssize_t i = after.indexOf(SL);
		    if (i < 0) i = after.length;
		    ssize_t new_len = wrkpath.length + i + 1;
		    if (wrkpath[$-1] == SL[0]) new_len--;
		    wrkpath = path[0..new_len];
		    //writefln("wrkpath=%s", wrkpath);
	    }

            _next = wrkpath;
            update(lsblk);
        }
    }

    this(string path, string mnt, dev_t dev)
    {
        this.path = path;
        this.mnt = mnt;
        this.next = path;
        this.dev = dev;
    }

    PathMnt next(string next)
    {
        PathMnt new_path = this;
        new_path._next = next;
        return new_path;
    }

    string get_key(in LsblkInfo[string] lsblk)
    {
        string key;

        LsblkInfo info = lsblk[mnt];

        string subpath = subpath(_next, mnt);
        string path0 = info.uuid ~ subpath.replace(SL, "\0");
        return path0;
    }

    void update(ref LsblkInfo[string] lsblkinfo)
    in
    {
        size_t i = path.length;
	version(Windows)
	{
		if (path != "\\")
		{
			assert(_next[0..i] == path, _next[0..i]~" == "~path);
			if (_next != path)
			{
			    assert(_next[i] == SL[0] || path == SL, format("path=%s, _next=%s", path, _next));
			    assert(_next[i+1..$].indexOf(SL) < 0, format("path=%s, _next=%s", path, _next));
			}
		}
	}
	else
	{
		assert(_next[0..i] == path, _next[0..i]~" == "~path);
		if (_next != path)
		{
		    assert(_next[i] == SL[0] || path == SL, format("path=%s, _next=%s", path, _next));
		    assert(_next[i+1..$].indexOf(SL) < 0, format("path=%s, _next=%s", path, _next));
		}
	}
    }
    out
    {
        assert(path == _next);
    }
    body
    {
        if (_next == path) return;

        DirEntry de;
        bool direntry_success = true;
	version(Posix)
	{
        try
        {
            de = DirEntry(_next);
        }
        catch (FileException e)
        {
            direntry_success = false;
        }

	bool not_the_same_filesystem = direntry_success && !de.isSymlink && de.statBuf.st_dev != dev;
	}
	else version(Windows)
	{
	bool not_the_same_filesystem = _next[0] != dev;
	}
        if (not_the_same_filesystem)
        {
	    version(Posix)
	    {
            dev = de.statBuf.st_dev;
	    }
	    else
	    {
	    dev = _next[0];
	    }
            char major = (dev & 0xFF00) >> 8;
            if ( (major == 7 ||  major == 8 || major == 179) && 
                    path !in lsblkinfo )
            {
                lsblk(lsblkinfo);
                assert(_next in lsblkinfo, "Path "~path~" not in lsblk");
            }
        }

        if (_next in lsblkinfo)
        {
            mnt = _next;
        }
        path = _next;
    }
}
