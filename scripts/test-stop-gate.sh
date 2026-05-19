#!/usr/bin/env bash
# Fixture-driven tests for skills/jarvis-reflect/scripts/stop-gate.sh.
# Each fixture builds a minimal transcript JSONL + scratch project dir + marker
# at a controlled age, then runs gate_verdict and asserts (verdict, rule).

set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GATE="$REPO/skills/jarvis-reflect/scripts/stop-gate.sh"
[[ -f "$GATE" ]] || { echo "FATAL: gate not found at $GATE" >&2; exit 2; }

WORK=$(mktemp -d -t jarvis-gate-test.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
FAIL=0
TOTAL=0

# touch_age <file> <seconds-ago>   GNU and BSD touch syntax.
touch_age() {
  local f=$1 age=$2
  if date -d "@0" >/dev/null 2>&1; then
    touch -d "@$(($(date +%s) - age))" "$f"
  else
    touch -t "$(date -v"-${age}S" +"%Y%m%d%H%M.%S")" "$f"
  fi
}

# run_gate <transcript> <marker> <project> [last_assistant_message]
# Echoes verdict to stdout; debug to $WORK/last.err.
run_gate() {
  local transcript=$1 marker=$2 project=$3 last_msg=${4:-}
  TRANSCRIPT_PATH="$transcript" MARKER="$marker" PROJECT_DIR="$project" \
    JARVIS_LAST_ASSISTANT_MESSAGE="$last_msg" \
    JARVIS_GATE_DEBUG=1 \
    bash -c "source '$GATE'; gate_verdict" 2>"$WORK/last.err"
}

# expect <label> <want_verdict> <want_rule> <got_verdict>
expect() {
  local label=$1 want_v=$2 want_r=$3 got_v=$4
  TOTAL=$((TOTAL+1))
  local got_r
  got_r=$(grep -oE 'rule=[0-9]+' "$WORK/last.err" | head -1 | cut -d= -f2)
  if [[ "$got_v" == "$want_v" && "$got_r" == "$want_r" ]]; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s  want=(%s rule=%s) got=(%s rule=%s)\n' \
      "$label" "$want_v" "$want_r" "$got_v" "$got_r" >&2
    FAIL=$((FAIL+1))
  fi
}

# JSONL fixture helpers — each emits one assistant entry line on stdout.
asst_text() { jq -nc --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
asst_tool() { jq -nc --arg n "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:$n,input:{}}]}}'; }

mk_proj()   { local p="$WORK/proj-$1";   mkdir -p "$p"; echo "$p"; }
mk_marker() { local m="$WORK/marker-$1"; touch "$m"; touch_age "$m" "$2"; echo "$m"; }

# ────────────────────────── fixtures ──────────────────────────

# fx1: text ending in '?' → SKIP rule 1
F=$WORK/fx1.jsonl
asst_text "Does this look right?" > "$F"
v=$(run_gate "$F" "$(mk_marker 1 60)" "$(mk_proj 1)")
expect "fx1 text ends with ? → SKIP r1" SKIP 1 "$v"

# fx2: text with deferring phrase → SKIP rule 1
F=$WORK/fx2.jsonl
asst_text "All wired up. Let me know if you want changes." > "$F"
v=$(run_gate "$F" "$(mk_marker 2 60)" "$(mk_proj 2)")
expect "fx2 deferring phrase → SKIP r1" SKIP 1 "$v"

# fx3: text + no signal, FS mutation (Edit) in same transcript → BLOCK rule 2
F=$WORK/fx3.jsonl
{ asst_tool "Edit"; asst_text "Done."; } > "$F"
v=$(run_gate "$F" "$(mk_marker 3 60)" "$(mk_proj 3)")
expect "fx3 mutation + no signal → BLOCK r2" BLOCK 2 "$v"

# fx4: tool_use last, earlier text ends with '?', no mutation → SKIP rule 1
# Pure walk-back test — fails under the unmodified gate (picks tool_use entry).
F=$WORK/fx4.jsonl
{ asst_text "Continue?"; asst_tool "Read"; } > "$F"
v=$(run_gate "$F" "$(mk_marker 4 60)" "$(mk_proj 4)")
expect "fx4 walk-back finds earlier ? (no mut) → SKIP r1" SKIP 1 "$v"

# fx5: tool_use last, earlier text ends with '?', mutation present → SKIP rule 1
# Walk-back must win over rule 2. This is the load-bearing case.
F=$WORK/fx5.jsonl
{ asst_text "Here's the design. Anything you want changed?"; asst_tool "Edit"; } > "$F"
v=$(run_gate "$F" "$(mk_marker 5 60)" "$(mk_proj 5)")
expect "fx5 walk-back finds ? with mutation → SKIP r1" SKIP 1 "$v"

# fx6: tool_use last, no '?' anywhere, mutation → BLOCK rule 2
F=$WORK/fx6.jsonl
{ asst_text "Working on it."; asst_tool "Edit"; asst_tool "Write"; } > "$F"
v=$(run_gate "$F" "$(mk_marker 6 60)" "$(mk_proj 6)")
expect "fx6 mutation, no signal, tool_use last → BLOCK r2" BLOCK 2 "$v"

# fx7: no transcript, age ≥ 300s → BLOCK rule 4
v=$(run_gate "$WORK/missing.jsonl" "$(mk_marker 7 400)" "$(mk_proj 7)")
expect "fx7 no transcript + old session → BLOCK r4" BLOCK 4 "$v"

# fx8: no transcript, age < 30s → SKIP rule 5
v=$(run_gate "$WORK/missing.jsonl" "$(mk_marker 8 0)" "$(mk_proj 8)")
expect "fx8 no transcript + young session → SKIP r5" SKIP 5 "$v"

# fx9: stdin last_assistant_message overrides transcript (Claude Code path).
# Transcript ends with tool_use + earlier text has no signal — would BLOCK
# without stdin. With stdin text containing '?', SKIP wins via rule 1.
F=$WORK/fx9.jsonl
{ asst_text "Working on it."; asst_tool "Bash"; } > "$F"
v=$(run_gate "$F" "$(mk_marker 9 60)" "$(mk_proj 9)" "Done. Anything else you want adjusted?")
expect "fx9 stdin last_assistant_message wins → SKIP r1" SKIP 1 "$v"

# fx10: stdin without pause signal does NOT spuriously override a BLOCK
# from rule 2 (mutation present, no signal).
F=$WORK/fx10.jsonl
{ asst_text "Working on it."; asst_tool "Edit"; } > "$F"
v=$(run_gate "$F" "$(mk_marker 10 60)" "$(mk_proj 10)" "Done.")
expect "fx10 stdin without ? + mutation → BLOCK r2" BLOCK 2 "$v"

# fx11: stdin present + ends in '?' + no transcript at all → SKIP r1
# (proves Rule 1 works purely from stdin, no transcript needed).
v=$(run_gate "$WORK/missing.jsonl" "$(mk_marker 11 60)" "$(mk_proj 11)" "Ready?")
expect "fx11 stdin-only path, no transcript → SKIP r1" SKIP 1 "$v"

# fx12: Bash-only (no FS mutation), no pause signal, working tree clean → SKIP r6.
# Read-only Bash (ls/grep/git status/etc.) should not BLOCK. Working-tree check
# is the ground truth for "did Bash actually mutate anything."
F=$WORK/fx12.jsonl
{ asst_tool "Bash"; asst_tool "Bash"; asst_text "Here's what I found."; } > "$F"
v=$(run_gate "$F" "$(mk_marker 12 60)" "$(mk_proj 12)")
expect "fx12 read-only Bash + clean tree → SKIP r6" SKIP 6 "$v"

# fx13: Bash + working tree modified since marker → BLOCK r3.
# The safety net: if Bash actually changed something on disk, rule 3 catches it.
F=$WORK/fx13.jsonl
{ asst_tool "Bash"; asst_text "Done."; } > "$F"
P13=$(mk_proj 13)
M13=$(mk_marker 13 120)
# Create a file newer than the marker (the "tree modified" signal).
touch "$P13/changed.txt"
v=$(run_gate "$F" "$M13" "$P13")
expect "fx13 Bash + tree modified → BLOCK r3" BLOCK 3 "$v"

echo
echo "──── $((TOTAL-FAIL))/$TOTAL passed ────"
exit "$FAIL"
