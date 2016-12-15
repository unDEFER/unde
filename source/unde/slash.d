module unde.slash;

version (Posix)
{
	immutable string SL = "/";
}
else version (Windows)
{
	immutable string SL = "\\";
}
