#!/bin/sh

# Canonical release targets shared by packaging and CI documentation.
case "${1:-list}" in
list)
	cat <<'EOF'
linux amd64
linux arm64
linux riscv64
freebsd amd64
freebsd aarch64
freebsd riscv64
openbsd amd64
openbsd aarch64
netbsd amd64
dragonfly amd64
EOF
	;;
valid)
	case "${2:-}/${3:-}" in
		linux/amd64|linux/arm64|linux/riscv64|freebsd/amd64|freebsd/aarch64|freebsd/riscv64|openbsd/amd64|openbsd/aarch64|netbsd/amd64|dragonfly/amd64) exit 0 ;;
		*) exit 1 ;;
	esac
	;;
*)
	echo "usage: $0 [list|valid PLATFORM ARCH]" >&2
	exit 2
	;;
esac
