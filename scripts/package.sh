#!/bin/sh
set -eu

# Create a portable release archive after a native build. The target label is
# deliberately supplied by CI so cross-builds can never be mislabeled.
if [ "$#" -ne 2 ]; then
	echo "usage: $0 PLATFORM ARCH" >&2
	exit 2
fi

platform=$1
arch=$2
root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dist_dir="$root_dir/dist"
binary="$root_dir/build/HareGirl"

if ! command -v zip >/dev/null 2>&1; then
	echo "zip is required to create a release archive" >&2
	exit 1
fi

"$root_dir/scripts/build.sh"
version=$("$binary" --version | awk '{ print $2 }')
case "$version" in
	''|*[!0-9.]*)
		echo "unable to determine HareGirl version" >&2
		exit 1
		;;
esac

archive_name="HareGirl-$version-$platform-$arch.zip"
stage_dir="$dist_dir/HareGirl-$version-$platform-$arch"
archive="$dist_dir/$archive_name"
rm -rf "$stage_dir"
mkdir -p "$stage_dir"
cp "$binary" "$stage_dir/HareGirl"
cp "$root_dir/LICENSE" "$stage_dir/LICENSE"
rm -f "$archive"
(cd "$stage_dir" && zip -q -r "$archive" HareGirl LICENSE)
rm -rf "$stage_dir"
printf '%s\n' "$archive"
