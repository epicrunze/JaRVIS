#!/usr/bin/env bash
# JaRVIS SessionStart Hook
# Automatically loads agent identity and memories at session start.
# Output goes to stdout and becomes part of Claude's context.
#
# Installation: Add to .claude/settings.json under hooks.SessionStart
# See CLAUDE.md.example for configuration details.
# This script lives inside the jarvis-reload skill so the documented
# install paths (.claude/skills/jarvis-reload/hooks/...) work as-is.

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

# --- Framing instructions ---
echo ""
echo "## How to use this context"
echo ""
echo "This is your identity and memory context from JaRVIS."
echo "- Internalize the identity below — this is who you are, developed through real experiences over time."
echo "- Use memories to inform your work. Don't recite them — let them shape how you approach tasks."

# --- Load identity ---
if [[ -f "$JARVIS_DIR/IDENTITY.md" ]]; then
  IDENTITY=$(cat "$JARVIS_DIR/IDENTITY.md")
  if [[ -n "$IDENTITY" ]]; then
    # Check for blank/template identity (version 0.0)
    if echo "$IDENTITY" | grep -q 'version: 0\.0'; then
      echo ""
      echo "## Identity"
      echo ""
      echo "This is a fresh JaRVIS setup — no identity yet. You'll develop one through work and reflection."
    else
      echo ""
      echo "## Identity"
      echo ""
      echo "$IDENTITY"
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
      echo ""
      echo "## Memories: $basename_no_ext"
      echo ""
      echo "$consolidated"
    fi
  done
fi

# --- Load 3 most recent journal entries ---
if [[ -d "$JARVIS_DIR/journal" ]]; then
  journal_files=$(ls -1t "$JARVIS_DIR/journal"/*.md 2>/dev/null | head -3)
  if [[ -n "$journal_files" ]]; then
    echo ""
    echo "## Recent Sessions"
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
        echo ""
        [[ -n "$heading" ]] && echo "$heading"
        [[ -n "$task_summary" ]] && echo "$task_summary"
        [[ -n "$key_decisions" ]] && echo "" && echo "### Memory Updates" && echo "" && echo "$key_decisions"
        [[ -n "$lessons" ]] && echo "" && echo "### Lessons" && echo "" && echo "$lessons"
      fi
    done <<< "$journal_files"
  fi
fi

# --- Auto memory note ---
echo ""
echo "---"
echo "**Note on auto memory:** Claude Code's built-in auto memory handles incidental observations separately. JaRVIS memories are for deliberate, reflected-on knowledge from the reflection process. Don't duplicate auto memory observations into \`.jarvis/\`."

# --- Closing reminder ---
echo ""
echo "Remember: run \`/jarvis-reflect\` after completing meaningful tasks to capture what you learned."
echo "</jarvis-session-context>"
