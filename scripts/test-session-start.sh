#!/usr/bin/env bash
# Fixture-driven tests for skills/jarvis-reload/scripts/jarvis-session-start.sh.
#
# Each fixture builds a minimal JARVIS_DIR with a memories/decisions.md and runs
# the hook. Asserts: exit 0, valid JSON on stdout, additionalContext contains
# the expected memories section.
#
# fx1 is the SIGPIPE regression: a Consolidated section longer than the
# `head -50` window. Under set -euo pipefail, the awk | head pipeline used
# to crash with exit 141 (SIGPIPE) and emit no JSON.

set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOK="$REPO/skills/jarvis-reload/scripts/jarvis-session-start.sh"
[[ -f "$HOOK" ]] || { echo "FATAL: hook not found at $HOOK" >&2; exit 2; }
command -v jq >/dev/null || { echo "FATAL: jq required" >&2; exit 2; }

WORK=$(mktemp -d -t jarvis-sstart-test.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
FAIL=0
TOTAL=0

# mk_jdir <n> <consolidated_lines> [line_padding_bytes]
# Builds $WORK/jdir-<n>/memories/decisions.md with a Consolidated section
# containing <consolidated_lines> bulleted entries. Optional <line_padding_bytes>
# pads each bullet so total output crosses the OS pipe buffer (~64KB on Linux)
# — required to actually trigger the awk-SIGPIPE-on-head-close behavior in
# real-world data where Consolidated sections contain multi-line bullets.
mk_jdir() {
  local n=$1 lines=$2 pad=${3:-0}
  local dir="$WORK/jdir-$n"
  mkdir -p "$dir/memories"
  local padstr=""
  if (( pad > 0 )); then
    padstr=$(head -c "$pad" /dev/zero | tr '\0' 'x')
  fi
  {
    echo "## Consolidated"
    echo
    local i
    for ((i=1; i<=lines; i++)); do
      echo "- bullet $i $padstr"
    done
    echo
    echo "## Recent"
    echo
    echo "- placeholder recent entry"
  } > "$dir/memories/decisions.md"
  echo "$dir"
}

# run_hook <jdir>
# Runs the hook with JARVIS_DIR=<jdir> and empty JSON stdin.
# Captures stdout to $WORK/last.out, stderr to $WORK/last.err, exit to $WORK/last.rc.
run_hook() {
  local jdir=$1
  set +e
  JARVIS_DIR="$jdir" bash "$HOOK" >"$WORK/last.out" 2>"$WORK/last.err" <<<'{}'
  echo $? > "$WORK/last.rc"
  set -e
}

# expect_ok <label> <substring_in_additionalContext>
expect_ok() {
  local label=$1 want_sub=$2
  TOTAL=$((TOTAL+1))
  local rc; rc=$(cat "$WORK/last.rc")
  if [[ "$rc" != "0" ]]; then
    printf 'FAIL  %s  exit=%s (want 0)\n  stderr: %s\n' \
      "$label" "$rc" "$(head -c 400 "$WORK/last.err")" >&2
    FAIL=$((FAIL+1)); return
  fi
  local ctx
  ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' < "$WORK/last.out" 2>/dev/null)
  if [[ -z "$ctx" ]]; then
    printf 'FAIL  %s  empty/invalid JSON on stdout\n  stdout: %s\n' \
      "$label" "$(head -c 400 "$WORK/last.out")" >&2
    FAIL=$((FAIL+1)); return
  fi
  if [[ "$ctx" != *"$want_sub"* ]]; then
    printf 'FAIL  %s  additionalContext missing %q\n' "$label" "$want_sub" >&2
    FAIL=$((FAIL+1)); return
  fi
  printf 'PASS  %s\n' "$label"
}

# ────────────────────────── fixtures ──────────────────────────

# fx1 (regression): Consolidated section with 200 lines × ~700-byte padding
# = ~140KB of awk output, well above the ~64KB pipe buffer. awk is mid-write
# when `head -50` closes the pipe → SIGPIPE (141). Pre-patch: script aborts
# under `set -euo pipefail`, no JSON on stdout. Post-patch: exit 0, JSON with
# memories section.
J=$(mk_jdir 1 200 700)
run_hook "$J"
expect_ok "fx1 Consolidated >>50 lines + large bytes (SIGPIPE regression)" "## Memories: decisions"

# fx2 (baseline): Consolidated section with 20 short lines — happy path.
# Confirms the patch didn't break the under-50 case.
J=$(mk_jdir 2 20)
run_hook "$J"
expect_ok "fx2 Consolidated <50 lines (baseline)" "## Memories: decisions"

echo
echo "──── $((TOTAL-FAIL))/$TOTAL passed ────"
exit "$FAIL"
