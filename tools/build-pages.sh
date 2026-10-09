#!/usr/bin/env bash
# Builds the browser version for GitHub Pages into build/pages/ (gitignored):
# Godot's single-threaded web export (no SharedArrayBuffer, so no COOP/COEP
# headers needed), the page shell in tools/web/shell.html, and a .nojekyll.
# Every URL in it is relative, so the folder works from any subpath
# (https://nearbycoder.github.io/Jeste/). Check it with tools/check-pages.mjs.
#
# Needs Godot 4.7.2 (GODOT=/path/to/godot to override) and its official export
# templates in ~/.local/share/godot/export_templates/4.7.2.stable/.
#
# Usage: tools/build-pages.sh [out_dir]   (default build/pages)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/build/pages}"
GODOT="${GODOT:-godot}"
WORK="$ROOT/build/pages-work"
REAL_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

ver="$("$GODOT" --version | cut -d. -f1-3)"            # e.g. 4.7.2
tpl="$REAL_DATA/godot/export_templates/$ver.stable"
if [ ! -f "$tpl/web_nothreads_release.zip" ]; then
	echo "build-pages: no web export template at $tpl/web_nothreads_release.zip" >&2
	echo "Install the official Godot $ver export templates (.tpz) there first." >&2
	exit 1
fi

# The editor runs with throwaway data, config and cache dirs, so an export can
# never touch real editor settings or the game's real save; only the
# templates are shared, through a symlink.
iso="$WORK/xdg"
mkdir -p "$iso/data/godot/export_templates" "$iso/config" "$iso/cache"
ln -sfn "$tpl" "$iso/data/godot/export_templates/$ver.stable"
export XDG_DATA_HOME="$iso/data" XDG_CONFIG_HOME="$iso/config" XDG_CACHE_HOME="$iso/cache"

rm -rf "$OUT"
mkdir -p "$OUT"
log="$WORK/export.log"
echo "build-pages: exporting with Godot $ver -> $OUT (log: $log)"
# --import first so a fresh checkout (no .godot/) has its resources imported
nice -n 10 "$GODOT" --headless --path "$ROOT" --import >"$log" 2>&1 || true
nice -n 10 "$GODOT" --headless --path "$ROOT" --export-release "Web" "$OUT/index.html" >>"$log" 2>&1
if grep -E "^(ERROR|SCRIPT ERROR)" "$log" >/dev/null; then
	grep -E -A2 "^(ERROR|SCRIPT ERROR)" "$log" | head -40 >&2
	echo "build-pages: the export logged errors (see $log)" >&2
	exit 1
fi
[ -f "$OUT/index.html" ] && [ -f "$OUT/index.wasm" ] && [ -f "$OUT/index.pck" ] || { echo "build-pages: export incomplete" >&2; exit 1; }

touch "$OUT/.nojekyll"   # serve files as they are, no Jekyll pass

# GitHub refuses files over 100 MB; keep well under it.
big="$(find "$OUT" -type f -size +50M)"
if [ -n "$big" ]; then
	echo "build-pages: files over 50 MB:" >&2
	echo "$big" >&2
	exit 1
fi
echo "build-pages: done"
( cd "$OUT" && ls -la . | sed 1d && du -sh . )
