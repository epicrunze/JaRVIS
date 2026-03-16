#!/usr/bin/env bash
# JaRVIS Stop Hook
# Fires when the agent is about to end its turn.
# Checks if a journal entry was created during this session.
# If not, reminds the agent to reflect before ending.
#
# Installation: Add to your platform's hook configuration (e.g., .claude/settings.local.json for Claude Code)
# See skills/jarvis-init/references/CLAUDE.md.example for configuration details.

set -euo pipefail

if [ -n "${JARVIS_DIR:-}" ]; then
  : # env var already set
else
  _project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  _slug=$(echo "$_project_dir" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
  JARVIS_DIR="$HOME/.jarvis/projects/$_slug"
fi

# --- If JaRVIS isn't set up, stay silent ---
if [[ ! -d "$JARVIS_DIR" ]]; then
  exit 0
fi

# --- If no journal directory, stay silent ---
if [[ ! -d "$JARVIS_DIR/journal" ]]; then
  exit 0
fi

# --- Check for journal entries created in the last 2 hours ---
recent_entries=$(find "$JARVIS_DIR/journal" -name '*.md' -mmin -120 2>/dev/null | head -1)

if [[ -z "$recent_entries" ]]; then
  cat <<'EOF'
<jarvis-stop-reminder>
You haven't reflected on this session yet. Run `/jarvis-reflect` before ending.
</jarvis-stop-reminder>
EOF
fi
