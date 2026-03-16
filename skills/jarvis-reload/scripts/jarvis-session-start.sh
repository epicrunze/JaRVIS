#!/usr/bin/env bash
# JaRVIS SessionStart Hook
# Automatically loads agent identity and memories at session start.
# Outputs structured JSON to stdout for Claude Code's hook system:
#   - hookSpecificOutput.additionalContext: model context (identity, memories, journals)
#   - systemMessage: user-visible notification
#
# Installation: Add to your platform's hook configuration (e.g., .claude/settings.local.json for Claude Code)
# See skills/jarvis-init/references/CLAUDE.md.example for configuration details.
# This script lives inside the jarvis-reload skill so the documented
# install paths (.claude/skills/jarvis-reload/hooks/...) work as-is.
#
# When running as a Claude Code plugin hook (via hooks/hooks.json), CLAUDE_PROJECT_DIR
# still points to the user's project (not the plugin root), so path resolution works as-is.
# BASH_SOURCE[0] resolves to the actual script location within the plugin directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/resolve-dir.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/resolve-dir.sh"
elif [ -z "${JARVIS_DIR:-}" ]; then
  _project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  _slug=$(echo "$_project_dir" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
  JARVIS_DIR="$HOME/.jarvis/projects/$_slug"
  unset _project_dir _slug
fi

# --- Helper: output JSON to stdout ---
# Uses jq when available, falls back to manual encoding
_jarvis_output_json() {
  local context="$1"
  local message="$2"
  if command -v jq &>/dev/null; then
    jq -n \
      --arg ctx "$context" \
      --arg msg "$message" \
      '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}, systemMessage: $msg}'
  else
    # Escape backslashes, double quotes, newlines, tabs, and carriage returns for JSON
    local escaped_ctx escaped_msg
    escaped_ctx=$(printf '%s' "$context" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g' -e 's/\r/\\r/g')
    escaped_msg=$(printf '%s' "$message" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g' -e 's/\r/\\r/g')
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"},"systemMessage":"%s"}\n' "$escaped_ctx" "$escaped_msg"
  fi
}

# --- Check for JaRVIS data directory ---
if [[ ! -d "$JARVIS_DIR" ]]; then
  _jarvis_output_json \
    "JaRVIS is not set up for this project. Run /jarvis-init to get started." \
    "⚠️ JaRVIS is not set up for this project. Run /jarvis-init to get started."
  exit 0
fi

# --- Read hook input from stdin ---
_jarvis_hook_input=$(cat 2>/dev/null || true)
if command -v jq &>/dev/null; then
  _jarvis_session_id=$(echo "$_jarvis_hook_input" | jq -r '.session_id // empty' 2>/dev/null)
  _jarvis_source=$(echo "$_jarvis_hook_input" | jq -r '.source // "startup"' 2>/dev/null)
else
  _jarvis_session_id=$(echo "$_jarvis_hook_input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)
  _jarvis_source="startup"
fi

# Create pending-reflection marker (skip for compaction events)
if [[ -n "$_jarvis_session_id" && "$_jarvis_source" != "compact" ]]; then
  touch "$JARVIS_DIR/.pending-$_jarvis_session_id"
fi

# Cleanup stale markers from crashed sessions (older than 24 hours)
find "$JARVIS_DIR" -maxdepth 1 -name '.pending-*' -mmin +1440 -delete 2>/dev/null || true

# Extract project slug from JARVIS_DIR (last path component)
_project_slug=$(basename "$JARVIS_DIR")

# --- Build context into a variable ---
_ctx=""
_ctx+="<jarvis-session-context>"$'\n'

# --- Framing instructions ---
_ctx+=""$'\n'
_ctx+="## How to use this context"$'\n'
_ctx+=""$'\n'
_ctx+="This is your identity and memory context from JaRVIS."$'\n'
_ctx+="- Internalize the identity below — this is who you are, developed through real experiences over time."$'\n'
_ctx+="- Use memories to inform your work. Don't recite them — let them shape how you approach tasks."$'\n'

# --- Load identity ---
if [[ -f "$JARVIS_DIR/IDENTITY.md" ]]; then
  IDENTITY=$(cat "$JARVIS_DIR/IDENTITY.md")
  if [[ -n "$IDENTITY" ]]; then
    # Check for blank/template identity (version 0.0)
    if echo "$IDENTITY" | grep -qi 'Version.*0\.0'; then
      _ctx+=""$'\n'
      _ctx+="## Identity"$'\n'
      _ctx+=""$'\n'
      _ctx+="This is a fresh JaRVIS setup — no identity yet. You'll develop one through work and reflection."$'\n'
    else
      _ctx+=""$'\n'
      _ctx+="## Identity"$'\n'
      _ctx+=""$'\n'
      _ctx+="$IDENTITY"$'\n'
    fi
  fi
fi

# --- Load consolidated memories ---
if [[ -d "$JARVIS_DIR/memories" ]]; then
  for memfile in "$JARVIS_DIR/memories"/*.md; do
    [[ -f "$memfile" ]] || continue
    # Extract the ## Consolidated section
    consolidated=$(awk '/^## Consolidated$/{found=1; next} /^## /{found=0} found' "$memfile" | head -50)
    if [[ -n "$consolidated" ]]; then
      basename_no_ext=$(basename "$memfile" .md)
      _ctx+=""$'\n'
      _ctx+="## Memories: $basename_no_ext"$'\n'
      _ctx+=""$'\n'
      _ctx+="$consolidated"$'\n'
    fi
  done
fi

# --- Load 3 most recent journal entries ---
if [[ -d "$JARVIS_DIR/journal" ]]; then
  journal_files=$(ls -1t "$JARVIS_DIR/journal"/*.md 2>/dev/null | head -3 || true)
  if [[ -n "$journal_files" ]]; then
    _ctx+=""$'\n'
    _ctx+="## Recent Sessions"$'\n'
    while IFS= read -r journal_file; do
      [[ -f "$journal_file" ]] || continue
      # Get the heading (first markdown heading)
      heading=$(grep -m1 '^# ' "$journal_file" 2>/dev/null || true)
      # Extract the Task Summary section
      task_summary=$(awk '/^## Task Summary$/{found=1; next} /^## /{found=0} found' "$journal_file" | head -20)
      # Extract the Key Decisions section
      key_decisions=$(awk '/^## Memory Updates$/{found=1; next} /^## /{found=0} found' "$journal_file" | head -20)
      # Extract the Lessons section
      lessons=$(awk '/^## Lessons Learned$/{found=1; next} /^## /{found=0} found' "$journal_file" | head -20)
      if [[ -n "$heading" || -n "$task_summary" ]]; then
        _ctx+=""$'\n'
        [[ -n "$heading" ]] && _ctx+="$heading"$'\n'
        [[ -n "$task_summary" ]] && _ctx+="$task_summary"$'\n'
        if [[ -n "$key_decisions" ]]; then
          _ctx+=""$'\n'
          _ctx+="### Memory Updates"$'\n'
          _ctx+=""$'\n'
          _ctx+="$key_decisions"$'\n'
        fi
        if [[ -n "$lessons" ]]; then
          _ctx+=""$'\n'
          _ctx+="### Lessons"$'\n'
          _ctx+=""$'\n'
          _ctx+="$lessons"$'\n'
        fi
      fi
    done <<< "$journal_files"
  fi
fi

# --- Auto memory note ---
_ctx+=""$'\n'
_ctx+="---"$'\n'
_ctx+="**Note on platform memory:** Some platforms have their own auto-memory systems that handle incidental observations separately. JaRVIS memories are for deliberate, reflected-on knowledge from the reflection process. Don't duplicate platform memory observations into JaRVIS memories."$'\n'

# --- Closing reminder ---
_ctx+=""$'\n'
_ctx+="Remember: run \`/jarvis-reflect\` after completing meaningful tasks to capture what you learned."$'\n'
_ctx+="</jarvis-session-context>"

# --- Output structured JSON ---
_jarvis_output_json "$_ctx" "🤖 JaRVIS loaded for $_project_slug"

# Cleanup temp vars
unset _jarvis_hook_input _jarvis_session_id _jarvis_source
