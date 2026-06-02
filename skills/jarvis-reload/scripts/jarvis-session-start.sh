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

# Check for disable toggle (env var — before resolving JARVIS_DIR)
if [[ "${JARVIS_DISABLE:-false}" == "true" ]]; then
  # Output minimal JSON so the hook system doesn't error
  if command -v jq &>/dev/null; then
    jq -n '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: ""}, systemMessage: ""}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""},"systemMessage":""}\n'
  fi
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/resolve-dir.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/resolve-dir.sh"
elif [ -z "${JARVIS_DIR:-}" ]; then
  # Inline fallback mirrors resolve-dir.sh: git toplevel + canonicalize + legacy fallback.
  _jstart="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  _jtop=$(git -C "$_jstart" rev-parse --show-toplevel 2>/dev/null || true)
  _jresolved="${_jtop:-$_jstart}"
  _jcanon=$(cd "$_jresolved" 2>/dev/null && pwd -P || echo "$_jresolved")
  _jslug=$(echo "$_jcanon" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
  JARVIS_DIR="$HOME/.jarvis/projects/$_jslug"
  if [ ! -d "$JARVIS_DIR" ]; then
    _jlegacy=$(echo "$_jstart" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
    if [ "$_jlegacy" != "$_jslug" ] && [ -d "$HOME/.jarvis/projects/$_jlegacy" ]; then
      JARVIS_DIR="$HOME/.jarvis/projects/$_jlegacy"
    fi
    unset _jlegacy
  fi
  unset _jstart _jtop _jresolved _jcanon _jslug
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

# Check for disable toggle (persistent marker file)
if [[ -f "$JARVIS_DIR/.jarvis-disabled" ]]; then
  _jarvis_output_json "" "JaRVIS is disabled for this project. Run /jarvis-toggle to re-enable."
  exit 0
fi

# --- Run pending data-dir migrations ---
_jarvis_migration_block=""
_jarvis_migrate_script="$SCRIPT_DIR/../../jarvis-migrate/scripts/migrate.sh"
if [ -f "$_jarvis_migrate_script" ]; then
  if _jarvis_migrate_out=$(bash "$_jarvis_migrate_script" "$JARVIS_DIR" 2>&1); then
    if [ -n "$_jarvis_migrate_out" ]; then
      _jarvis_migration_block="$_jarvis_migrate_out"$'\n\n'
    fi
  else
    _jarvis_migrate_rc=$?
    _jarvis_output_json \
      "JaRVIS migration failed (rc=$_jarvis_migrate_rc):"$'\n'"$_jarvis_migrate_out"$'\n\n'"Fix the issue, then start a new session." \
      "JaRVIS migration failed — see context."
    exit 1
  fi
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
_ctx="$_jarvis_migration_block"
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

# --- Load consolidated memories (fall back to recent if consolidated is empty) ---
if [[ -d "$JARVIS_DIR/memories" ]]; then
  for memfile in "$JARVIS_DIR/memories"/*.md; do
    [[ -f "$memfile" ]] || continue
    # Extract the ## Consolidated section
    consolidated=$(awk '/^## Consolidated$/{found=1; next} /^## /{found=0} found' "$memfile" | head -50 || true)
    # Check if consolidated has real content (not just a placeholder)
    if [[ -n "$consolidated" ]] && ! echo "$consolidated" | grep -qi '^No consolidated .* yet'; then
      basename_no_ext=$(basename "$memfile" .md)
      _ctx+=""$'\n'
      _ctx+="## Memories: $basename_no_ext"$'\n'
      _ctx+=""$'\n'
      _ctx+="$consolidated"$'\n'
    else
      # Fall back to recent entries (latest 50 lines, blank lines stripped)
      recent=$(awk '/^## Recent$/{found=1; next} /^## /{found=0} found' "$memfile" | sed '/^$/d' | tail -50)
      if [[ -n "$recent" ]]; then
        basename_no_ext=$(basename "$memfile" .md)
        _ctx+=""$'\n'
        _ctx+="## Memories: $basename_no_ext"$'\n'
        _ctx+=""$'\n'
        _ctx+="$recent"$'\n'
      fi
    fi
  done
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
unset _jarvis_migration_block _jarvis_migrate_script _jarvis_migrate_out _jarvis_migrate_rc 2>/dev/null
