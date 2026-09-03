#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

"$root_dir/scripts/build.sh"
version=$($root_dir/build/haregirl --version)
[ "$version" = "HareGirl 0.1.0" ]
"$root_dir/build/haregirl" --help
if "$root_dir/build/haregirl" --unknown >/dev/null 2>&1; then
	echo "unknown option was accepted" >&2
	exit 1
fi
