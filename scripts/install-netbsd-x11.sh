#!/bin/sh
set -eu

# The small NetBSD VM images intentionally omit xbase.  pkgsrc's SDL2 package
# links to the native X11 libraries, so restore the official xbase set first.
case "$(uname -m)" in
	amd64|x86_64) machine=amd64 ;;
	aarch64|arm64) machine=evbarm-aarch64 ;;
	*) echo "unsupported NetBSD architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [ -f /usr/X11R7/lib/libXau.so.7 ]; then
	exit 0
fi

release=$(uname -r | sed 's/[^0-9.].*$//')
archive=/tmp/netbsd-xbase.tar.xz
ftp -o "$archive" "https://cdn.netbsd.org/pub/NetBSD/NetBSD-$release/$machine/binary/sets/xbase.tar.xz"
tar -C / -xJpf "$archive"
