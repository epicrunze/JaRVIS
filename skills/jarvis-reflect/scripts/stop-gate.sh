#!/usr/bin/env bash
# JaRVIS Stop-Hook Heuristic Gate
# Sourced by jarvis-stop.sh after the marker check. Decides whether to fire the
# "reminder to reflect" block, based on signals from the conversation transcript
# (when available) and the working tree.
#
# Inputs (read from caller-set env):
#   TRANSCRIPT_PATH               — path to a JSONL transcript file (Claude Code), may be empty/missing
#   MARKER                        — path to the .pending-<session-id> marker file (must exist)
#   PROJECT_DIR                   — working tree to scan for file modifications (CLAUDE_PROJECT_DIR or pwd)
#   JARVIS_LAST_ASSISTANT_MESSAGE — agent's final text verbatim (Claude Code stdin field);
#                                   optional, gate falls back to transcript walk-back when empty
#
# Output:
#   stdout: "BLOCK" or "SKIP"
#
# Decision ladder (first match wins):
#   1. Last paragraph of the agent's final text contains '?' OR a deferring
#      phrase → SKIP. Source: $JARVIS_LAST_ASSISTANT_MESSAGE env var (passed
#      by the Claude Code Stop hook stdin), falling back to walk-back over
#      the transcript file if that env var is empty (other platforms).
#   2. Transcript available, any FS-mutating tool call (Edit/Write/NotebookEdit) → BLOCK
#   3. Working tree modified since marker mtime → BLOCK (also catches Bash that
#      actually changed the tree — see "Why Bash is excluded from rule 2" below)
#   4. Transcript missing/empty AND session age >= 300s → BLOCK (Cursor/other fallback)
#   5. Session age < 30s → SKIP
#   6. Default → SKIP
#
# Why prefer the stdin field over the transcript file: Claude Code can invoke
# the Stop hook before the assistant's final text content is flushed to the
# transcript JSONL. Earlier polling-based mitigations were unreliable because
# flush latency exceeded the polling window. The stdin field is delivered
# verbatim with the hook invocation, sidestepping the race entirely.
#
# Why Bash is excluded from rule 2: many Bash invocations are read-only
# (ls/grep/find/git status/etc.) and shouldn't trip the reminder. Treating any
# Bash as mutating produced a false positive on read-mostly Q&A turns. The
# working-tree check in rule 3 is the ground truth for "did Bash actually
# change anything," so we let it carry that signal. Trade-off: Bash with
# non-FS side effects (curl, git push, slack post) no longer blocks on its
# own; in practice those are rare in read-mostly turns and an extra reminder
# is cheaper than the false positive.
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

# --- Parse transcript: sets _JARVIS_GATE_{TC,MUT,LT,LAST_CT,OK} ---
# OK=1 if the transcript was readable and produced any signal.
# LT is the concatenated text of the *most recent assistant entry that has at
# least one text content block* (walk-back). LAST_CT is a JSON-array string of
# the content-block types of the *very last* assistant entry (used by the
# gate's race-retry heuristic).
_jarvis_parse_transcript() {
  local f="$1"
  _JARVIS_GATE_TC=0
  _JARVIS_GATE_MUT=0
  _JARVIS_GATE_LT=""
  _JARVIS_GATE_LAST_CT=""
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
                       | $n == "Edit" or $n == "Write" or $n == "NotebookEdit"))
          | length > 0) as $mut
      | ([$m[] | select(.type? == "assistant")] | last) as $very_last
      | ([$m[] | select(.type? == "assistant")
               | select(content_of | any(.type? == "text"))] | last) as $la
      | ((($la // {}) | content_of)
          | map(select(.type? == "text") | .text? // "")
          | join("\n")) as $lt
      | (($very_last // {}) | content_of | map(.type? // "") | tostring) as $last_ct
      | "TC=\($tc)\nMUT=\(if $mut then 1 else 0 end)\nLAST_CT=\($last_ct)\nLT_BEGIN\n\($lt)\nLT_END"
    ' 2>/dev/null) || out=""

    if [[ -n "$out" ]]; then
      _JARVIS_GATE_TC=$(printf '%s\n' "$out" | sed -n 's/^TC=//p' | head -1)
      _JARVIS_GATE_MUT=$(printf '%s\n' "$out" | sed -n 's/^MUT=//p' | head -1)
      _JARVIS_GATE_LAST_CT=$(printf '%s\n' "$out" | sed -n 's/^LAST_CT=//p' | head -1)
      _JARVIS_GATE_LT=$(printf '%s\n' "$out" | awk '/^LT_BEGIN$/{f=1;next} /^LT_END$/{f=0} f')
      [[ -z "$_JARVIS_GATE_TC" ]] && _JARVIS_GATE_TC=0
      [[ -z "$_JARVIS_GATE_MUT" ]] && _JARVIS_GATE_MUT=0
      _JARVIS_GATE_OK=1
    fi
    return
  fi

  # --- Fallback: grep/sed (no jq). Best-effort; LAST_CT and walk-back are
  # approximated by inspecting the last assistant line's content-type substrings.
  _JARVIS_GATE_TC=$(printf '%s' "$capped" | grep -o '"type":"tool_use"' 2>/dev/null | wc -l | tr -d ' ')
  [[ -z "$_JARVIS_GATE_TC" ]] && _JARVIS_GATE_TC=0
  if printf '%s' "$capped" | grep -qE '"type":"tool_use","name":"(Edit|Write|NotebookEdit)"' 2>/dev/null; then
    _JARVIS_GATE_MUT=1
  fi
  # Walk-back: pick the last assistant line that has any "type":"text" in it.
  local la_text
  la_text=$(printf '%s' "$capped" | grep '"type":"assistant"' 2>/dev/null \
            | grep '"type":"text"' | tail -1)
  if [[ -n "$la_text" ]]; then
    _JARVIS_GATE_LT=$(printf '%s' "$la_text" \
      | grep -oE '"text":"([^"\\]|\\.)*"' \
      | sed -E 's/^"text":"//; s/"$//' \
      | sed -E 's/\\"/"/g; s/\\n/ /g; s/\\t/ /g')
  fi
  # LAST_CT from the very-last assistant line, regardless of content type.
  local very_last
  very_last=$(printf '%s' "$capped" | grep '"type":"assistant"' 2>/dev/null | tail -1)
  if [[ -n "$very_last" ]]; then
    local parts=()
    printf '%s' "$very_last" | grep -q '"type":"text"'      && parts+=('"text"')
    printf '%s' "$very_last" | grep -q '"type":"tool_use"'  && parts+=('"tool_use"')
    printf '%s' "$very_last" | grep -q '"type":"thinking"'  && parts+=('"thinking"')
    if [[ ${#parts[@]} -gt 0 ]]; then
      _JARVIS_GATE_LAST_CT="[$(IFS=,; echo "${parts[*]}")]"
    else
      _JARVIS_GATE_LAST_CT="[]"
    fi
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
  printf 'jarvis-gate: verdict=%s rule=%s age=%ss ok=%s tc=%s mut=%s last_ct=%s lt_tail=%q\n' \
    "$verdict" "$rule" "$age" "${_JARVIS_GATE_OK:-0}" "${_JARVIS_GATE_TC:-0}" "${_JARVIS_GATE_MUT:-0}" \
    "${_JARVIS_GATE_LAST_CT:-}" "$lt_tail" >&2
}

# --- Main entry: echo BLOCK or SKIP ---
gate_verdict() {
  local transcript="${TRANSCRIPT_PATH:-}"
  local marker="${MARKER:-}"
  local project_dir="${PROJECT_DIR:-}"
  local age

  age=$(_jarvis_session_age "$marker")
  _jarvis_parse_transcript "$transcript"

  # Rule 1: last paragraph of the agent's final text signals a pause for input
  # (contains '?' or a deferring phrase) → SKIP regardless of mutations.
  # Prefer the stdin-provided text (race-free); fall back to transcript walk-back
  # when the env var is empty (non-Claude-Code platforms, or unset for tests).
  local _rule1_src=""
  if [[ -n "${JARVIS_LAST_ASSISTANT_MESSAGE:-}" ]]; then
    _rule1_src="$JARVIS_LAST_ASSISTANT_MESSAGE"
  elif [[ "$_JARVIS_GATE_OK" == "1" ]]; then
    _rule1_src="$_JARVIS_GATE_LT"
  fi
  if _jarvis_last_paragraph_signals_pause "$_rule1_src"; then
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
