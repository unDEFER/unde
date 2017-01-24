Name: unDE	
Version: 0.2.0	
Release: 1%{?dist}
Summary: unDE Is Not Desktop Environment	

License: GPL3+
URL: http://unde.su	
Source0: unde

Requires: dejavu-sans-fonts >= 2.35
Requires: liberation-mono-fonts >= 1.07.4
Requires: SDL2 >= 2.0.4
Requires: SDL2_image >= 2.0.1
Requires: SDL2_ttf >= 2.0.14
Requires: rsync >= 3.1.2
Requires: coreutils >= 8.25
Requires: util-linux >= 2.28

%description
unDE is a recursive acronym for "unDE Is Not Desktop Environment".
unDE 0.1.0 provides original file manager, text viewer and image viewer.
unDE 0.2.0 provides also command line and keybar.

%install
mkdir -p %{buildroot}/%{_bindir}
install -p -m 755 %{SOURCE0} %{buildroot}/%{_bindir}
mkdir -p %{buildroot}/%{_datadir}/unde/layouts
mkdir -p %{buildroot}/%{_datadir}/unde/images
cp -a layouts/* %{buildroot}/%{_datadir}/unde/layouts
cp -a images/* %{buildroot}/%{_datadir}/unde/images

%files
%{_bindir}/unde
%{_datadir}/unde/layouts
%{_datadir}/unde/images

%changelog

