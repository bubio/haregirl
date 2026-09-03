#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir="$root_dir/build"

mkdir -p "$output_dir"
hare build -o "$output_dir/haregirl" "$root_dir/src/app/main.ha"
