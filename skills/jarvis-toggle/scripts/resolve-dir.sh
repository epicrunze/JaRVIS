#!/usr/bin/env bash
# Source this file to set JARVIS_DIR, or execute it to print the path.
#
# Resolution order:
#   1. If JARVIS_DIR is already set, keep it (escape hatch for bind mounts /
#      multi-host setups where path canonicalization isn't enough).
#   2. Start from $CLAUDE_PROJECT_DIR or $(pwd).
#   3. Walk up to the git toplevel if inside a repo (handles "ran from a
#      subdirectory of the project").
#   4. Canonicalize via `cd && pwd -P` (POSIX, resolves symlinks; portable
#      across macOS / Linux / BSD without depending on GNU coreutils).
#   5. Slugify: strip leading slash, replace space/slash with '-', lowercase.
#   6. If the canonical slug dir doesn't exist but a dir at the *legacy* slug
#      (uncanonicalized, no toplevel walk) does, use the legacy dir. This
#      keeps existing data dirs working after the canonicalization upgrade.

if [ -z "${JARVIS_DIR:-}" ]; then
  _jarvis_start_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"

  # Walk up to git toplevel if available
  _jarvis_top=$(git -C "$_jarvis_start_dir" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$_jarvis_top" ]; then
    _jarvis_resolved_dir="$_jarvis_top"
  else
    _jarvis_resolved_dir="$_jarvis_start_dir"
  fi

  # Canonicalize (resolve symlinks, normalize path)
  _jarvis_canonical=$(cd "$_jarvis_resolved_dir" 2>/dev/null && pwd -P || echo "$_jarvis_resolved_dir")

  _jarvis_slug=$(echo "$_jarvis_canonical" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
  JARVIS_DIR="$HOME/.jarvis/projects/$_jarvis_slug"

  # Legacy-slug fallback: if the canonical dir doesn't exist but a dir at the
  # pre-canonicalization slug does, use it. This makes the canonicalization
  # change backward-compatible for existing users.
  if [ ! -d "$JARVIS_DIR" ]; then
    _jarvis_legacy_slug=$(echo "$_jarvis_start_dir" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
    _jarvis_legacy_dir="$HOME/.jarvis/projects/$_jarvis_legacy_slug"
    if [ "$_jarvis_legacy_slug" != "$_jarvis_slug" ] && [ -d "$_jarvis_legacy_dir" ]; then
      JARVIS_DIR="$_jarvis_legacy_dir"
      # Notify on a tty (interactive shells) but stay silent for hook JSON.
      if [ -t 2 ]; then
        echo "jarvis: using legacy data dir $_jarvis_legacy_dir (canonical slug would be $_jarvis_slug)" >&2
      fi
    fi
    unset _jarvis_legacy_slug _jarvis_legacy_dir
  fi

  unset _jarvis_start_dir _jarvis_top _jarvis_resolved_dir _jarvis_canonical _jarvis_slug
fi

# When executed (not sourced), print the resolved path
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "$JARVIS_DIR"
fi
