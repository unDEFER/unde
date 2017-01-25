Name: unDE	
Version: 0.2.0	
Release: 1%{?dist}
Summary: unDE Is Not Desktop Environment	

License: GPL3+
URL: http://unde.su	
Source0: unde

Requires: gdouros-symbola-fonts >= 7.12
Requires: liberation-fonts >= 1.07.3
Requires: libSDL2-2_0-0 >= 2.0.3
Requires: libSDL2_image-2_0-0 >= 2.0.0
Requires: libSDL2_ttf-2_0-0 >= 2.0.12
Requires: rsync >= 3.1.1
Requires: coreutils >= 8.23
Requires: util-linux >= 2.25

%description
unDE is a recursive acronym for "unDE Is Not Desktop Environment".
unDE 0.1.0 provides original file manager, text viewer and image viewer.
unDE 0.2.0 provides also command line and keybar.

%install
mkdir -p %{buildroot}/%{_bindir}
install -p -m 755 %{SOURCE0}/unde %{buildroot}/%{_bindir}
mkdir -p %{buildroot}/%{_datadir}/unde/layouts
mkdir -p %{buildroot}/%{_datadir}/unde/images
cp -a %{SOURCE0}/layouts/* %{buildroot}/%{_datadir}/unde/layouts
cp -a %{SOURCE0}/images/* %{buildroot}/%{_datadir}/unde/images

%files
%{_bindir}/unde
%{_datadir}/unde/layouts
%{_datadir}/unde/images

%changelog

