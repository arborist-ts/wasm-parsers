#!/usr/bin/env bash
# Build every parser listed in parsers.txt as WASM, into ./out/<lang>.wasm.
#
# Args:
#   $1  path to arborist.nvim/registry/pins.toml (revision pins per parser)
#   $2  path to parsers.txt (one lang per line)
#   $3  output directory (created if missing)
#
# Reads each parser's git URL and `location` (mono-repo subdir) from the
# bundled arborist.nvim registry/parsers.toml, the revision SHA from
# pins.toml, then clones, checks out the pin, and runs
# `tree-sitter build --wasm`. Hard-fails the script on any single
# parser's build failure — ship-or-don't, no partial releases.

set -euo pipefail

PINS=${1:?pins.toml path required}
LIST=${2:?parsers.txt path required}
OUT=${3:?output dir required}

# Locate parsers.toml relative to pins.toml (same directory).
PARSERS_TOML="$(dirname "$PINS")/parsers.toml"
[[ -f "$PARSERS_TOML" ]] || { echo "missing $PARSERS_TOML" >&2; exit 1; }

mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Minimal TOML field extractor — same shape arborist.nvim's registry.lua expects.
toml_field() {
  local file=$1 section=$2 key=$3
  awk -v sec="[$section]" -v key="$key" '
    $0==sec { inside=1; next }
    inside && /^\[/ { inside=0 }
    inside {
      n = split($0, p, "=")
      if (n >= 2) {
        gsub(/^[ \t]+|[ \t]+$/, "", p[1])
        if (p[1] == key) {
          val = p[2]
          sub(/^[ \t]+/, "", val)
          # strip surrounding quotes
          gsub(/^"|"$/, "", val)
          print val
          exit
        }
      }
    }
  ' "$file"
}

fail=0
while IFS= read -r lang; do
  [[ -z "$lang" || "$lang" == \#* ]] && continue
  url=$(toml_field "$PARSERS_TOML" "$lang" url)
  location=$(toml_field "$PARSERS_TOML" "$lang" location)
  generate=$(toml_field "$PARSERS_TOML" "$lang" generate)
  revision=$(toml_field "$PINS" "$lang" revision)

  [[ -z "$url" ]]      && { echo "[$lang] missing url in parsers.toml"  >&2; fail=1; continue; }
  [[ -z "$revision" ]] && { echo "[$lang] missing revision in pins.toml" >&2; fail=1; continue; }

  clone=$WORK/$lang
  echo "[$lang] cloning $url @ $revision"
  git clone --quiet "$url" "$clone"
  git -C "$clone" checkout --quiet --detach "$revision"

  build_dir=$clone
  [[ -n "$location" ]] && build_dir=$clone/$location

  if [[ "$generate" == "true" ]]; then
    echo "[$lang] tree-sitter generate"
    (cd "$build_dir" && tree-sitter generate)
  fi

  echo "[$lang] tree-sitter build --wasm"
  if ! (cd "$build_dir" && tree-sitter build --wasm -o "$OUT/$lang.wasm"); then
    echo "[$lang] BUILD FAILED" >&2
    fail=1
    continue
  fi
  if [[ ! -s "$OUT/$lang.wasm" ]]; then
    echo "[$lang] EMPTY OUTPUT" >&2
    fail=1
    continue
  fi
  echo "[$lang] ok ($(stat -c%s "$OUT/$lang.wasm") bytes)"
done < "$LIST"

[[ "$fail" == "0" ]] || { echo "one or more parsers failed to build" >&2; exit 1; }
echo "built $(ls "$OUT"/*.wasm | wc -l) parsers"
