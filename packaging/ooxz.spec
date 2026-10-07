Name:           ooxz
Version:        0.1.0
Release:        1%{?dist}
Summary:        High-ratio LZMA2 compressor utilizing dictionary matching and thread pools.
License:        ASL 2.0
URL:            https://github.com/openOODA-tools/ooxz
Source0:        ooxz-linux-x86_64
Source1:        uninstall.sh
BuildArch:      x86_64
Requires:       glibc

%description
ooxz is a sovereign, capability-bounded LZMA COMPRESS written
in pure openOODA, featuring zero ambient authority, oote color themes,
and an MCP stdio server.

%install
mkdir -p %{buildroot}/usr/bin
install -m 0755 %{SOURCE0} %{buildroot}/usr/bin/ooxz
install -m 0755 %{SOURCE1} %{buildroot}/usr/bin/ooxz-uninstall

%files
/usr/bin/ooxz
/usr/bin/ooxz-uninstall

%changelog
* Wed Oct 07 2026 openOODA-tools <ops@openooda.org> - 0.1.0-1
- Initial sovereign blueprint scaffolding
