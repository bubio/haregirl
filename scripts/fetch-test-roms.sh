#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
rom_dir="$root_dir/tests/roms"
archive_name="mts-20221022-1426-a2dac64.zip"
archive_url="https://gekkio.fi/files/mooneye-test-suite/mts-20221022-1426-a2dac64/$archive_name"
archive_path="$rom_dir/$archive_name"
dest_dir="$rom_dir/mooneye-test-suite"

mkdir -p "$rom_dir" "$dest_dir"

if [ ! -f "$archive_path" ]; then
	curl -L --fail --silent --show-error -o "$archive_path" "$archive_url"
fi

python3 - "$archive_path" "$dest_dir" <<'PY'
from pathlib import Path
from zipfile import ZipFile
import sys

archive = Path(sys.argv[1])
dest = Path(sys.argv[2])
prefixes = (
    "acceptance/timer/",
    "acceptance/interrupts/",
    "acceptance/serial/",
)

with ZipFile(archive) as zf:
    for name in zf.namelist():
        parts = name.split("/", 1)
        if len(parts) != 2:
            continue
        rel = parts[1]
        if not rel.endswith((".gb", ".sym")):
            continue
        if not any(rel.startswith(prefix) for prefix in prefixes):
            continue
        target = dest / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with zf.open(name) as src, target.open("wb") as dst:
            dst.write(src.read())
PY

printf 'Fetched Mooneye ROMs into %s\n' "$dest_dir"
