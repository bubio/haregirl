#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
rom_dir="$root_dir/tests/roms"
blargg_dir="$rom_dir/blargg"
archive_name="mts-20221022-1426-a2dac64.zip"
archive_url="https://gekkio.fi/files/mooneye-test-suite/mts-20221022-1426-a2dac64/$archive_name"
archive_path="$rom_dir/$archive_name"
dest_dir="$rom_dir/mooneye-test-suite"
blargg_commit="c240dd7d700e5c0b00a7bbba52b53e4ee67b5f15"
blargg_base_url="https://raw.githubusercontent.com/retrio/gb-test-roms/$blargg_commit"

mkdir -p "$rom_dir" "$dest_dir" "$blargg_dir/cpu_instrs/individual" \
	"$blargg_dir/instr_timing"

fetch_blargg() {
	remote_path=$1
	local_path=$2

	if [ -f "$local_path" ]; then
		return 0
	fi

	tmp_path="$local_path.tmp"
	encoded_path=$(printf '%s' "$remote_path" | sed 's/ /%20/g')
	if ! curl -L --fail --silent --show-error -o "$tmp_path" \
		"$blargg_base_url/$encoded_path"; then
		rm -f "$tmp_path"
		return 1
	fi
	mv "$tmp_path" "$local_path"
}

fetch_blargg "cpu_instrs/individual/01-special.gb" \
	"$blargg_dir/cpu_instrs/individual/01-special.gb"
fetch_blargg "cpu_instrs/individual/02-interrupts.gb" \
	"$blargg_dir/cpu_instrs/individual/02-interrupts.gb"
fetch_blargg "cpu_instrs/individual/03-op sp,hl.gb" \
	"$blargg_dir/cpu_instrs/individual/03-op sp,hl.gb"
fetch_blargg "cpu_instrs/individual/04-op r,imm.gb" \
	"$blargg_dir/cpu_instrs/individual/04-op r,imm.gb"
fetch_blargg "cpu_instrs/individual/05-op rp.gb" \
	"$blargg_dir/cpu_instrs/individual/05-op rp.gb"
fetch_blargg "cpu_instrs/individual/06-ld r,r.gb" \
	"$blargg_dir/cpu_instrs/individual/06-ld r,r.gb"
fetch_blargg "cpu_instrs/individual/07-jr,jp,call,ret,rst.gb" \
	"$blargg_dir/cpu_instrs/individual/07-jr,jp,call,ret,rst.gb"
fetch_blargg "cpu_instrs/individual/08-misc instrs.gb" \
	"$blargg_dir/cpu_instrs/individual/08-misc instrs.gb"
fetch_blargg "cpu_instrs/individual/09-op r,r.gb" \
	"$blargg_dir/cpu_instrs/individual/09-op r,r.gb"
fetch_blargg "cpu_instrs/individual/10-bit ops.gb" \
	"$blargg_dir/cpu_instrs/individual/10-bit ops.gb"
fetch_blargg "cpu_instrs/individual/11-op a,(hl).gb" \
	"$blargg_dir/cpu_instrs/individual/11-op a,(hl).gb"
fetch_blargg "instr_timing/instr_timing.gb" \
	"$blargg_dir/instr_timing/instr_timing.gb"

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

printf 'Fetched Blargg ROMs into %s (commit %s)\n' "$blargg_dir" "$blargg_commit"
printf 'Fetched Mooneye ROMs into %s\n' "$dest_dir"
