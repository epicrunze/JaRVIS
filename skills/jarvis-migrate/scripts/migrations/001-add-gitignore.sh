#!/usr/bin/env bash
# 001-add-gitignore.sh — ensure .gitignore excludes session markers + OS noise
set -euo pipefail

JDIR="$1"
. "$(dirname "$0")/_lib.sh"

GITIGNORE="$JDIR/.gitignore"

if [ ! -f "$GITIGNORE" ]; then
  cat > "$GITIGNORE" << 'EOF'
# JaRVIS state
.pending-*

# OS / editor noise
.DS_Store
Thumbs.db
*.swp
*.swo
*~
.idea/
.vscode/
EOF
  log_change "wrote .gitignore (excludes pending markers + OS noise)"
elif ! grep -qE '^\.pending-\*' "$GITIGNORE"; then
  printf '\n# JaRVIS state\n.pending-*\n' >> "$GITIGNORE"
  log_change "appended .pending-* to existing .gitignore"
else
  log_change "no-op (.gitignore already current)"
fi
