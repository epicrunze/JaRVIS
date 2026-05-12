#!/usr/bin/env bash
# JaRVIS Stop-Hook Heuristic Gate
# Sourced by jarvis-stop.sh after the marker check. Decides whether to fire the
# "reminder to reflect" block, based on signals from the conversation transcript
# (when available) and the working tree.
#
# Inputs (read from caller-set env):
#   TRANSCRIPT_PATH  — path to a JSONL transcript file (Claude Code), may be empty/missing
#   MARKER           — path to the .pending-<session-id> marker file (must exist)
#   PROJECT_DIR      — working tree to scan for file modifications (CLAUDE_PROJECT_DIR or pwd)
#
# Output:
#   stdout: "BLOCK" or "SKIP"
#
# Decision ladder (first match wins):
#   1. Transcript available, last paragraph of last assistant message contains '?'
#      OR matches a deferring phrase ("let me know", "your call", …) → SKIP
#   2. Transcript available, any mutating tool call (Edit/Write/NotebookEdit/Bash) → BLOCK
#   3. Working tree modified since marker mtime → BLOCK
#   4. Transcript missing/empty AND session age >= 300s → BLOCK (Cursor/other fallback)
#   5. Session age < 30s → SKIP
#   6. Default → SKIP
#
# All failure modes default to SKIP (bias toward silence).

# --- Marker mtime → session age (seconds) ---
_jarvis_session_age() {
  local marker="$1"
  local now mtime age
  now=$(date +%s 2>/dev/null || echo 0)
  if [[ -f "$marker" ]]; then
    mtime=$(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker" 2>/dev/null || echo "$now")
  else
    mtime="$now"
  fi
  age=$(( now - mtime ))
  [[ "$age" -lt 0 ]] && age=0
  echo "$age"
}

# --- Deferring-phrase regex (Rule 1, case-insensitive) ---
# English phrases that signal "agent is awaiting user input" even without '?'.
# Matched anywhere in the last paragraph. Keep this list short and high-precision —
# false positives lean toward SKIP, which is the file's stated bias.
_JARVIS_DEFER_REGEX="(let me know|your call|up to you|tell me (when|which|how)|pick (one|which)|choose (one|which)|standing by|over to you|ready when you are|when you'?re ready|whenever you'?re ready|approve to proceed|give (me )?the go-ahead|say the word|confirm before)"

# --- Pause-signal check ---
# Returns 0 if the LAST paragraph of $1 (text after the final blank line) contains
# '?' OR matches a deferring phrase. The last-paragraph scope keeps rhetorical
# questions in earlier explanatory paragraphs from triggering false SKIPs.
_jarvis_last_paragraph_signals_pause() {
  local t="$1"
  [[ -z "$t" ]] && return 1
  local last_para
  last_para=$(printf '%s\n' "$t" | awk 'BEGIN{RS=""} {p=$0} END{print p}')
  [[ -z "$last_para" ]] && return 1
  [[ "$last_para" == *\?* ]] && return 0
  printf '%s' "$last_para" | grep -iqE "$_JARVIS_DEFER_REGEX"
}

# --- Parse transcript: sets _JARVIS_GATE_{TC,MUT,LT,OK} ---
# OK=1 if the transcript was readable and produced any signal.
_jarvis_parse_transcript() {
  local f="$1"
  _JARVIS_GATE_TC=0
  _JARVIS_GATE_MUT=0
  _JARVIS_GATE_LT=""
  _JARVIS_GATE_OK=0

  if [[ -z "$f" || ! -f "$f" ]]; then
    return
  fi

  # Cap input at the trailing 2 MB. Truncation only undercounts tools, which
  # biases SKIP — safe. Last assistant message lives at the tail, so the
  # pause-signal check is unaffected.
  local capped
  capped=$(tail -c 2097152 "$f" 2>/dev/null) || return

  if command -v jq &>/dev/null; then
    local out
    out=$(printf '%s' "$capped" | jq -rs '
      def msgs: [.[] | select(type=="object")];
      def content_of: (.message?.content? // .content? // []);
      msgs as $m
      | ($m | map(content_of | .[]? | select(.type? == "tool_use")) | length) as $tc
      | ($m
          | map(content_of | .[]?
              | select(.type? == "tool_use"
                       and (.name? // "") as $n
                       | $n == "Edit" or $n == "Write" or $n == "NotebookEdit" or $n == "Bash"))
          | length > 0) as $mut
      | ([$m[] | select(.type? == "assistant")] | last) as $la
      | ((($la // {}) | content_of)
          | map(select(.type? == "text") | .text? // "")
          | join("\n")) as $lt
      | "TC=\($tc)\nMUT=\(if $mut then 1 else 0 end)\nLT_BEGIN\n\($lt)\nLT_END"
    ' 2>/dev/null) || out=""

    if [[ -n "$out" ]]; then
      _JARVIS_GATE_TC=$(printf '%s\n' "$out" | sed -n 's/^TC=//p' | head -1)
      _JARVIS_GATE_MUT=$(printf '%s\n' "$out" | sed -n 's/^MUT=//p' | head -1)
      _JARVIS_GATE_LT=$(printf '%s\n' "$out" | awk '/^LT_BEGIN$/{f=1;next} /^LT_END$/{f=0} f')
      [[ -z "$_JARVIS_GATE_TC" ]] && _JARVIS_GATE_TC=0
      [[ -z "$_JARVIS_GATE_MUT" ]] && _JARVIS_GATE_MUT=0
      _JARVIS_GATE_OK=1
    fi
    return
  fi

  # --- Fallback: grep/sed (no jq) ---
  _JARVIS_GATE_TC=$(printf '%s' "$capped" | grep -o '"type":"tool_use"' 2>/dev/null | wc -l | tr -d ' ')
  [[ -z "$_JARVIS_GATE_TC" ]] && _JARVIS_GATE_TC=0
  if printf '%s' "$capped" | grep -qE '"type":"tool_use","name":"(Edit|Write|NotebookEdit|Bash)"' 2>/dev/null; then
    _JARVIS_GATE_MUT=1
  fi
  local last_a
  last_a=$(printf '%s' "$capped" | grep '"type":"assistant"' 2>/dev/null | tail -1)
  if [[ -n "$last_a" ]]; then
    # Concatenate all "text":"..." values in the last assistant line.
    _JARVIS_GATE_LT=$(printf '%s' "$last_a" \
      | grep -oE '"text":"([^"\\]|\\.)*"' \
      | sed -E 's/^"text":"//; s/"$//' \
      | sed -E 's/\\"/"/g; s/\\n/ /g; s/\\t/ /g')
  fi
  _JARVIS_GATE_OK=1
}

# --- Working-tree modification check (rule 3) ---
_jarvis_tree_modified_since() {
  local marker="$1"
  local dir="$2"
  [[ -z "$dir" || ! -d "$dir" ]] && return 1
  [[ ! -f "$marker" ]] && return 1
  local canon
  canon=$(cd "$dir" 2>/dev/null && pwd -P) || return 1
  # Short-circuit on first hit; exclude common large/uninteresting trees.
  find "$canon" \
    \( -path '*/.git' -o -path '*/node_modules' -o -path '*/dist' -o -path '*/build' -o -path '*/.next' -o -path '*/.venv' -o -path '*/__pycache__' \) -prune \
    -o -newer "$marker" -type f -print 2>/dev/null \
    | head -1 | grep -q .
}

# --- Debug trace ---
# Set JARVIS_GATE_DEBUG=1 to log verdict + signals to stderr.
_jarvis_gate_debug() {
  [[ "${JARVIS_GATE_DEBUG:-}" != "1" ]] && return
  local verdict="$1" rule="$2" age="$3"
  local lt_tail
  lt_tail=$(printf '%s' "${_JARVIS_GATE_LT:-}" | tail -c 80 | tr '\n' ' ')
  printf 'jarvis-gate: verdict=%s rule=%s age=%ss ok=%s tc=%s mut=%s lt_tail=%q\n' \
    "$verdict" "$rule" "$age" "${_JARVIS_GATE_OK:-0}" "${_JARVIS_GATE_TC:-0}" "${_JARVIS_GATE_MUT:-0}" \
    "$lt_tail" >&2
}

# --- Main entry: echo BLOCK or SKIP ---
gate_verdict() {
  local transcript="${TRANSCRIPT_PATH:-}"
  local marker="${MARKER:-}"
  local project_dir="${PROJECT_DIR:-}"
  local age

  age=$(_jarvis_session_age "$marker")
  _jarvis_parse_transcript "$transcript"

  # Rule 1: last paragraph of last assistant message signals a pause for input
  # (contains '?' or a deferring phrase) → SKIP regardless of mutations.
  if [[ "$_JARVIS_GATE_OK" == "1" ]] && _jarvis_last_paragraph_signals_pause "$_JARVIS_GATE_LT"; then
    _jarvis_gate_debug SKIP 1 "$age"
    echo SKIP
    return
  fi

  # Rule 2: any mutating tool call (transcript-only)
  if [[ "$_JARVIS_GATE_OK" == "1" && "$_JARVIS_GATE_MUT" == "1" ]]; then
    _jarvis_gate_debug BLOCK 2 "$age"
    echo BLOCK
    return
  fi

  # Rule 3: working tree modified since marker mtime
  if _jarvis_tree_modified_since "$marker" "$project_dir"; then
    _jarvis_gate_debug BLOCK 3 "$age"
    echo BLOCK
    return
  fi

  # Rule 4: no transcript and session is old enough (Cursor/other fallback)
  if [[ "$_JARVIS_GATE_OK" != "1" && "$age" -ge 300 ]]; then
    _jarvis_gate_debug BLOCK 4 "$age"
    echo BLOCK
    return
  fi

  # Rule 5: very young session
  if [[ "$age" -lt 30 ]]; then
    _jarvis_gate_debug SKIP 5 "$age"
    echo SKIP
    return
  fi

  # Rule 6: default
  _jarvis_gate_debug SKIP 6 "$age"
  echo SKIP
}
