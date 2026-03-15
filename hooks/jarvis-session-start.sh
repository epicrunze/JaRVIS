#!/usr/bin/env bash
# JaRVIS SessionStart Hook
# Automatically loads agent identity and memories at session start.
# Output goes to stdout and becomes part of Claude's context.
#
# Installation: Add to .claude/settings.json under hooks.SessionStart
# See CLAUDE.md.example for configuration details.

set -euo pipefail

JARVIS_DIR="${CLAUDE_PROJECT_DIR:-.}/.jarvis"

# --- Check for .jarvis/ directory ---
if [[ ! -d "$JARVIS_DIR" ]]; then
  cat <<'EOF'
<jarvis-session-context>
JaRVIS is not set up in this project. Run `/jarvis-init` to scaffold the `.jarvis/` directory and get started.
</jarvis-session-context>
EOF
  exit 0
fi

# --- Begin context block ---
echo "<jarvis-session-context>"

# --- Load identity ---
if [[ -f "$JARVIS_DIR/IDENTITY.md" ]]; then
  IDENTITY=$(cat "$JARVIS_DIR/IDENTITY.md")
  if [[ -n "$IDENTITY" ]]; then
    echo ""
    echo "## Identity"
    echo ""
    echo "$IDENTITY"
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
      echo ""
      echo "## Memories: $basename_no_ext"
      echo ""
      echo "$consolidated"
    fi
  done
fi

# --- Load last journal entry summary ---
if [[ -d "$JARVIS_DIR/journal" ]]; then
  latest_journal=$(ls -1t "$JARVIS_DIR/journal"/*.md 2>/dev/null | head -1)
  if [[ -n "$latest_journal" ]]; then
    # Get the heading (first markdown heading)
    heading=$(grep -m1 '^# ' "$latest_journal" 2>/dev/null || true)
    # Extract the Task Summary section
    task_summary=$(awk '/^## Task Summary$/{found=1; next} /^## /{found=0} found' "$latest_journal" | head -20)
    if [[ -n "$heading" || -n "$task_summary" ]]; then
      echo ""
      echo "## Last Session"
      echo ""
      [[ -n "$heading" ]] && echo "$heading"
      [[ -n "$task_summary" ]] && echo "$task_summary"
    fi
  fi
fi

# --- Closing reminder ---
echo ""
echo "---"
echo "Remember: run \`/jarvis-reflect\` after completing meaningful tasks to capture what you learned."
echo "</jarvis-session-context>"
