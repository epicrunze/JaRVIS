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

# ────────────── permission-staleness nudge (plugin installs) ──────────────
# The hook calls jarvis-permissions.sh --check against
# $CLAUDE_PROJECT_DIR/.claude/settings.local.json when CLAUDE_PLUGIN_ROOT is
# set, and prepends a one-line nudge to additionalContext when rules are stale.

PERMS="$REPO/skills/jarvis-init/scripts/jarvis-permissions.sh"
NUDGE="JaRVIS permission rules in .claude/settings.local.json are out of date"
FAKE_PLUGIN_ROOT="$WORK/plugins/cache/jarvis-marketplace/jarvis/9.9.9"
mkdir -p "$FAKE_PLUGIN_ROOT"

# run_hook_proj <jdir> <project-dir>
run_hook_proj() {
  local jdir=$1 proj=$2
  set +e
  JARVIS_DIR="$jdir" CLAUDE_PROJECT_DIR="$proj" CLAUDE_PLUGIN_ROOT="$FAKE_PLUGIN_ROOT" \
    bash "$HOOK" >"$WORK/last.out" 2>"$WORK/last.err" <<<'{}'
  echo $? > "$WORK/last.rc"
  set -e
}

# expect_absent <label> <substring>: exit 0, valid JSON, substring NOT in additionalContext
expect_absent() {
  local label=$1 sub=$2
  TOTAL=$((TOTAL+1))
  local rc; rc=$(cat "$WORK/last.rc")
  local ctx; ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' < "$WORK/last.out" 2>/dev/null)
  if [[ "$rc" != "0" || -z "$ctx" ]]; then
    printf 'FAIL  %s  exit=%s or invalid JSON\n  stderr: %s\n' "$label" "$rc" "$(head -c 400 "$WORK/last.err")" >&2
    FAIL=$((FAIL+1)); return
  fi
  if [[ "$ctx" == *"$sub"* ]]; then
    printf 'FAIL  %s  additionalContext unexpectedly contains %q\n' "$label" "$sub" >&2
    FAIL=$((FAIL+1)); return
  fi
  printf 'PASS  %s\n' "$label"
}

# fx3: stale (old-template) rules → nudge present, memories still loaded.
J=$(mk_jdir 3 5)
PROJ="$WORK/proj-stale"; mkdir -p "$PROJ/.claude"
cat > "$PROJ/.claude/settings.local.json" <<EOF
{ "permissions": { "allow": [
  "Read(~/.jarvis/projects/x/**)", "Edit(~/.jarvis/projects/x/**)", "Write(~/.jarvis/projects/x/**)",
  "Bash(cd ~/.jarvis/projects/x && git *)",
  "Bash(bash $FAKE_PLUGIN_ROOT/skills/jarvis-validate/scripts/validate.sh *)"
] } }
EOF
run_hook_proj "$J" "$PROJ"
expect_ok "fx3 stale rules: nudge present" "$NUDGE"
expect_ok "fx3 stale rules: memories still loaded" "## Memories: decisions"

# fx4: canonical rules (written by jarvis-permissions.sh itself) → no nudge.
J=$(mk_jdir 4 5)
PROJ="$WORK/proj-canon"; mkdir -p "$PROJ"
bash "$PERMS" --project-dir "$PROJ" --jarvis-dir "$J" --plugin-root "$FAKE_PLUGIN_ROOT" >/dev/null
run_hook_proj "$J" "$PROJ"
expect_absent "fx4 canonical rules: no nudge" "$NUDGE"

# fx5: no settings.local.json at all → no nudge (user never opted in).
J=$(mk_jdir 5 5)
PROJ="$WORK/proj-none"; mkdir -p "$PROJ"
run_hook_proj "$J" "$PROJ"
expect_absent "fx5 no settings file: no nudge" "$NUDGE"

echo
echo "──── $((TOTAL-FAIL))/$TOTAL passed ────"
exit "$FAIL"
