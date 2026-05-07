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
#   1. Transcript available, last assistant message ends with '?' AND no mutating tool calls → SKIP
#   2. Transcript available, any mutating tool call (Edit/Write/NotebookEdit/Bash) → BLOCK
#   3. Working tree modified since marker mtime → BLOCK
#   4. Transcript available, >=5 total tool_use blocks → BLOCK
#   5. Transcript missing/empty AND session age >= 300s → BLOCK (Cursor/other fallback)
#   6. Session age < 30s → SKIP
#   7. Default → SKIP
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

# --- Question-end check ---
# Strips trailing whitespace and markdown wrappers iteratively, then tests for '?'.
_jarvis_ends_with_question() {
  local t="$1"
  [[ -z "$t" ]] && return 1
  local stripped="$t" prev=""
  while [[ "$stripped" != "$prev" ]]; do
    prev="$stripped"
    stripped=$(printf '%s' "$stripped" | sed -E 's/[[:space:]]+$//')
    stripped=$(printf '%s' "$stripped" | sed -E "s/[\`*_\"'>)]+\$//")
  done
  [[ "$stripped" == *\? ]]
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
  # ends-with-? check is unaffected.
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

# --- Main entry: echo BLOCK or SKIP ---
gate_verdict() {
  local transcript="${TRANSCRIPT_PATH:-}"
  local marker="${MARKER:-}"
  local project_dir="${PROJECT_DIR:-}"
  local age

  age=$(_jarvis_session_age "$marker")
  _jarvis_parse_transcript "$transcript"

  # Rule 1: question + no mutations (transcript-only)
  if [[ "$_JARVIS_GATE_OK" == "1" && "$_JARVIS_GATE_MUT" != "1" ]]; then
    if _jarvis_ends_with_question "$_JARVIS_GATE_LT"; then
      echo SKIP
      return
    fi
  fi

  # Rule 2: any mutating tool call (transcript-only)
  if [[ "$_JARVIS_GATE_OK" == "1" && "$_JARVIS_GATE_MUT" == "1" ]]; then
    echo BLOCK
    return
  fi

  # Rule 3: working tree modified since marker mtime
  if _jarvis_tree_modified_since "$marker" "$project_dir"; then
    echo BLOCK
    return
  fi

  # Rule 4: tool-call count threshold (transcript-only)
  if [[ "$_JARVIS_GATE_OK" == "1" && "${_JARVIS_GATE_TC:-0}" -ge 5 ]]; then
    echo BLOCK
    return
  fi

  # Rule 5: no transcript and session is old enough (Cursor/other fallback)
  if [[ "$_JARVIS_GATE_OK" != "1" && "$age" -ge 300 ]]; then
    echo BLOCK
    return
  fi

  # Rule 6: very young session
  if [[ "$age" -lt 30 ]]; then
    echo SKIP
    return
  fi

  # Rule 7: default
  echo SKIP
}
