#!/usr/bin/env bash
# Source this file; it sets JARVIS_DIR.
if [ -z "${JARVIS_DIR:-}" ]; then
  _jarvis_project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  _jarvis_slug=$(echo "$_jarvis_project_dir" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
  JARVIS_DIR="$HOME/.jarvis/projects/$_jarvis_slug"
  unset _jarvis_project_dir _jarvis_slug
fi
