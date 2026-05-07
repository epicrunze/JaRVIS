#!/usr/bin/env bash
# JaRVIS Migration Runner — applies pending data-dir schema migrations
# Usage: migrate.sh [<jarvis-dir>]
#
# Reads <jarvis-dir>/.jarvis-data-version (default 0 if absent),
# compares to migrations/LATEST, runs pending migrations in order,
# atomically advances the stamp on success.
#
# Exit codes:
#   0 = success (or no-op)
#   2 = data dir not found
#   3 = downgrade refused (stamp > LATEST)
#   4 = migration failed (stamp NOT advanced)
#   5 = packaging bug (LATEST disagrees with migration filenames)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="$SCRIPT_DIR/migrations"

# Override JARVIS_DIR via $1, else use resolve-dir.sh.
if [ -n "${1:-}" ]; then
  JARVIS_DIR="$1"
elif [ -f "$SCRIPT_DIR/resolve-dir.sh" ]; then
  # shellcheck source=resolve-dir.sh
  source "$SCRIPT_DIR/resolve-dir.sh"
fi

# --- Verify data dir exists ---
if [ ! -d "${JARVIS_DIR:-}" ]; then
  printf 'jarvis-migrate: data dir not found: %s\n' "${JARVIS_DIR:-<unset>}" >&2
  printf 'jarvis-migrate: run /jarvis-init first.\n' >&2
  exit 2
fi

STAMP_FILE="$JARVIS_DIR/.jarvis-data-version"
LATEST_FILE="$MIGRATIONS_DIR/LATEST"

# --- Read CURRENT stamp (default 0; non-integer treated as 0) ---
CURRENT=0
if [ -f "$STAMP_FILE" ]; then
  raw=$(head -c 32 "$STAMP_FILE" | tr -d '[:space:]')
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    CURRENT="$raw"
  fi
fi

# --- Read LATEST ---
if [ ! -f "$LATEST_FILE" ]; then
  printf 'jarvis-migrate: missing LATEST file at %s (packaging bug)\n' "$LATEST_FILE" >&2
  exit 5
fi
LATEST=$(head -c 32 "$LATEST_FILE" | tr -d '[:space:]')
if ! [[ "$LATEST" =~ ^[0-9]+$ ]]; then
  printf 'jarvis-migrate: LATEST file has non-integer content (packaging bug)\n' >&2
  exit 5
fi

# --- Short-circuit: nothing to do ---
if [ "$CURRENT" -eq "$LATEST" ]; then
  exit 0
fi

# --- Plugin-downgrade guard ---
if [ "$CURRENT" -gt "$LATEST" ]; then
  printf 'jarvis-migrate: data version %s > plugin LATEST %s — plugin was downgraded?\n' "$CURRENT" "$LATEST" >&2
  printf 'jarvis-migrate: to recover, either upgrade the plugin or hand-edit %s to %s.\n' "$STAMP_FILE" "$LATEST" >&2
  exit 3
fi

# --- Discover migrations and sanity-check against LATEST ---
mapfile -t MIGRATIONS < <(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '[0-9][0-9][0-9]-*.sh' | sort)
HIGHEST=0
if [ "${#MIGRATIONS[@]}" -gt 0 ]; then
  last_file="${MIGRATIONS[-1]}"
  last_base=$(basename "$last_file")
  HIGHEST=$((10#${last_base:0:3}))
fi
if [ "$HIGHEST" -ne "$LATEST" ]; then
  printf 'jarvis-migrate: packaging bug — LATEST=%s but highest migration is %s\n' "$LATEST" "$HIGHEST" >&2
  exit 5
fi

# --- Run pending migrations in order ---
CHANGELOG=()
for migration in "${MIGRATIONS[@]}"; do
  base=$(basename "$migration" .sh)
  nnn=$((10#${base:0:3}))
  if [ "$nnn" -le "$CURRENT" ]; then
    continue
  fi
  if [ "$nnn" -gt "$LATEST" ]; then
    break
  fi

  # Run the migration; capture stdout (changelog line) and stderr separately.
  tmp_stderr=$(mktemp)
  if mig_stdout=$(bash "$migration" "$JARVIS_DIR" 2>"$tmp_stderr"); then
    rm -f "$tmp_stderr"
    CHANGELOG+=("$base: ${mig_stdout%$'\n'}")
  else
    printf 'jarvis-migrate: migration %s failed (data dir still at version %s)\n' "$base" "$CURRENT" >&2
    if [ -s "$tmp_stderr" ]; then
      cat "$tmp_stderr" >&2
    fi
    rm -f "$tmp_stderr"
    exit 4
  fi
done

# --- Atomically advance the stamp ---
echo "$LATEST" > "$STAMP_FILE.tmp"
mv "$STAMP_FILE.tmp" "$STAMP_FILE"

# --- Print aggregated changelog to stdout ---
printf 'JaRVIS data dir migrated v%s → v%s\n' "$CURRENT" "$LATEST"
for line in "${CHANGELOG[@]}"; do
  printf -- '- %s\n' "$line"
done
exit 0
