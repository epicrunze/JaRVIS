#!/usr/bin/env bash
# JaRVIS Validate — checks JaRVIS artifacts for format correctness
# Usage: validate.sh <path-to-.jarvis>

set -euo pipefail

if [ -n "${1:-}" ]; then
  JARVIS_DIR="$1"
elif [ -f "$HOME/.jarvis/bin/resolve-dir.sh" ]; then
  # shellcheck source=/dev/null
  source "$HOME/.jarvis/bin/resolve-dir.sh"
elif [ -z "${JARVIS_DIR:-}" ]; then
  _project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  _slug=$(echo "$_project_dir" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
  JARVIS_DIR="$HOME/.jarvis/projects/$_slug"
  unset _project_dir _slug
fi

# --- Color support ---
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BOLD=''
  RESET=''
fi

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf "${GREEN}PASS${RESET} %s\n" "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "${RED}FAIL${RESET} %s\n" "$1"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf "${YELLOW}WARN${RESET} %s\n" "$1"
}

# --- Check JaRVIS data dir exists ---
if [[ ! -d "$JARVIS_DIR" ]]; then
  fail "JaRVIS data directory not found at $JARVIS_DIR"
  echo ""
  printf "${BOLD}Summary:${RESET} 0 passed, 1 failed, 0 warnings\n"
  exit 1
fi

pass "JaRVIS data directory exists"

# --- Validate IDENTITY.md ---
echo ""
printf "${BOLD}=== Identity ===${RESET}\n"

IDENTITY_FILE="$JARVIS_DIR/IDENTITY.md"
if [[ -f "$IDENTITY_FILE" ]]; then
  pass "IDENTITY.md exists"

  for section in "Core" "Personality" "Expertise" "Principles" "Tool Mastery" "User Model"; do
    if grep -qi "^## $section" "$IDENTITY_FILE"; then
      pass "IDENTITY.md has section: $section"
    else
      fail "IDENTITY.md missing section: $section"
    fi
  done

  # Check Core contains Name, Version, Last evolved
  core_section=$(awk '/^## Core/,/^## [^C]/' "$IDENTITY_FILE")
  if echo "$core_section" | grep -qi 'name'; then
    pass "IDENTITY.md Core has Name"
  else
    fail "IDENTITY.md Core missing Name"
  fi
  if echo "$core_section" | grep -qE '[0-9]+\.[0-9]+'; then
    pass "IDENTITY.md Core has valid version (N.N format)"
  else
    fail "IDENTITY.md Core missing valid version (expected N.N format)"
  fi
  if echo "$core_section" | grep -qi 'last evolved'; then
    pass "IDENTITY.md Core has Last evolved"
  else
    fail "IDENTITY.md Core missing Last evolved"
  fi
else
  fail "IDENTITY.md not found"
fi

# --- Validate GROWTH.md ---
echo ""
printf "${BOLD}=== Growth Log ===${RESET}\n"

GROWTH_FILE="$JARVIS_DIR/GROWTH.md"
if [[ -f "$GROWTH_FILE" ]]; then
  pass "GROWTH.md exists"

  # Check for table header
  if grep -qE '^\|.*Date.*\|.*Version.*\|' "$GROWTH_FILE"; then
    pass "GROWTH.md has table header"
  else
    fail "GROWTH.md missing table header (expected | Date | Version | ...)"
  fi

  # Check for separator row
  if grep -qE '^\|[-]+\|' "$GROWTH_FILE"; then
    pass "GROWTH.md has table separator"
  else
    fail "GROWTH.md missing table separator row"
  fi

  # Validate data rows if any exist
  data_rows=$(grep -E '^\|[^-]' "$GROWTH_FILE" | grep -v -i 'Date' || true)
  if [[ -n "$data_rows" ]]; then
    row_num=0
    while IFS= read -r row; do
      row_num=$((row_num + 1))
      # Count non-empty columns (split by |, trim whitespace)
      col_count=$(echo "$row" | awk -F'|' '{
        count=0
        for(i=2; i<NF; i++) {
          gsub(/^[ \t]+|[ \t]+$/, "", $i)
          if ($i != "") count++
        }
        print count
      }')
      if [[ "$col_count" -ge 4 ]]; then
        pass "GROWTH.md data row $row_num has $col_count non-empty columns"
      else
        fail "GROWTH.md data row $row_num has only $col_count non-empty columns (expected 4)"
      fi

      # Check date format in first column
      date_val=$(echo "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
      if echo "$date_val" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        pass "GROWTH.md data row $row_num has valid date: $date_val"
      else
        fail "GROWTH.md data row $row_num has invalid date: $date_val (expected YYYY-MM-DD)"
      fi

      # Check version format in second column
      version_val=$(echo "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}')
      if echo "$version_val" | grep -qE '^[0-9]+\.[0-9]+$'; then
        pass "GROWTH.md data row $row_num has valid version: $version_val"
      else
        fail "GROWTH.md data row $row_num has invalid version: $version_val (expected N.N)"
      fi
    done <<< "$data_rows"
  fi
else
  fail "GROWTH.md not found"
fi

# --- Validate Memories ---
echo ""
printf "${BOLD}=== Memories ===${RESET}\n"

if [[ -d "$JARVIS_DIR/memories" ]]; then
  pass "memories/ directory exists"

  mem_files=$(ls -1 "$JARVIS_DIR/memories/"*.md 2>/dev/null || true)
  if [[ -z "$mem_files" ]]; then
    warn "No memory files found in memories/"
  else
    while IFS= read -r memfile; do
      basename_file=$(basename "$memfile")

      # Check filename is lowercase-with-hyphens.md
      if echo "$basename_file" | grep -qE '^[a-z0-9]([a-z0-9-]*[a-z0-9])?\.md$'; then
        pass "memories/$basename_file: valid filename"
      else
        fail "memories/$basename_file: filename should be lowercase-with-hyphens.md"
      fi

      # Check for top-level heading
      if grep -qE '^# ' "$memfile"; then
        pass "memories/$basename_file: has top-level heading"
      else
        fail "memories/$basename_file: missing top-level heading"
      fi

      # Check for Consolidated section
      if grep -qi '^## Consolidated' "$memfile"; then
        pass "memories/$basename_file: has ## Consolidated section"
      else
        fail "memories/$basename_file: missing ## Consolidated section"
      fi

      # Check for Recent section
      if grep -qi '^## Recent' "$memfile"; then
        pass "memories/$basename_file: has ## Recent section"
      else
        fail "memories/$basename_file: missing ## Recent section"
      fi
    done <<< "$mem_files"
  fi
else
  fail "memories/ directory not found"
fi

# --- Validate Journal Entries ---
echo ""
printf "${BOLD}=== Journal Entries ===${RESET}\n"

if [[ -d "$JARVIS_DIR/journal" ]]; then
  pass "journal/ directory exists"

  journal_files=$(ls -1 "$JARVIS_DIR/journal/"*.md 2>/dev/null || true)
  if [[ -z "$journal_files" ]]; then
    warn "No journal entries found (this is fine for a fresh setup)"
  else
    REQUIRED_SECTIONS=("Task Summary" "Actions Taken" "What Worked" "What Didn't Work" "Lessons Learned" "Memory Updates" "Identity Impact")

    while IFS= read -r jfile; do
      basename_file=$(basename "$jfile")
      echo ""
      printf "${BOLD}%s${RESET}\n" "--- $basename_file ---"

      # Check filename format: YYYY-MM-DD-HH-MM.md or YYYY-MM-DD-HH-MM-XXXXXXXX.md
      if echo "$basename_file" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}(-[0-9a-f]{8})?\.md$'; then
        pass "Filename format valid"
      else
        fail "Filename should match YYYY-MM-DD-HH-MM.md or YYYY-MM-DD-HH-MM-XXXXXXXX.md"
      fi

      # Check for YAML frontmatter
      first_line=$(head -1 "$jfile")
      if [[ "$first_line" == "---" ]]; then
        pass "Has YAML frontmatter"

        # Extract frontmatter
        frontmatter=$(awk 'NR==1 && /^---$/{found=1; next} found && /^---$/{exit} found' "$jfile")

        # Check required frontmatter fields
        if echo "$frontmatter" | grep -qE '^date:'; then
          pass "Frontmatter has date"
        else
          fail "Frontmatter missing date field"
        fi

        if echo "$frontmatter" | grep -qE '^time:'; then
          pass "Frontmatter has time"
        else
          fail "Frontmatter missing time field"
        fi

        if echo "$frontmatter" | grep -qE '^tags:.*\['; then
          pass "Frontmatter has tags (list)"
        else
          fail "Frontmatter missing tags field (expected list format)"
        fi

        if echo "$frontmatter" | grep -qE '^task_type: *(feature|bugfix|refactor|docs|research|config|other)'; then
          pass "Frontmatter has valid task_type"
        else
          task_type_val=$(echo "$frontmatter" | grep -oE '^task_type: *(.+)' | sed 's/task_type: *//' || true)
          if [[ -n "$task_type_val" ]]; then
            fail "Frontmatter task_type '$task_type_val' is not valid (expected: feature|bugfix|refactor|docs|research|config|other)"
          else
            fail "Frontmatter missing task_type field"
          fi
        fi
      else
        warn "No YAML frontmatter (older entry — consider adding frontmatter for searchability)"
      fi

      # Check required sections
      for section in "${REQUIRED_SECTIONS[@]}"; do
        if grep -qi "^## $section" "$jfile"; then
          # Check section is non-empty
          section_content=$(awk -v sect="$section" '
            BEGIN { IGNORECASE=1 }
            $0 ~ "^## "sect"$" { found=1; next }
            /^## / { found=0 }
            found { content = content $0 }
            END { print content }
          ' "$jfile" | tr -d '[:space:]')
          if [[ -n "$section_content" ]]; then
            pass "Section: $section (non-empty)"
          else
            fail "Section: $section is empty"
          fi
        else
          fail "Missing section: $section"
        fi
      done
    done <<< "$journal_files"
  fi
else
  fail "journal/ directory not found"
fi

# --- Summary ---
echo ""
echo "================================"
TOTAL=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
printf "${BOLD}Summary:${RESET} ${GREEN}%d passed${RESET}, ${RED}%d failed${RESET}, ${YELLOW}%d warnings${RESET} (%d total checks)\n" \
  "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT" "$TOTAL"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
