#!/usr/bin/env bash
# JaRVIS Integration Tests
# Tests the 4 shell scripts: session-start, stop, validate, search
# No external dependencies — uses JARVIS_DIR env var for fixture isolation.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SESSION_START="$SCRIPT_DIR/skills/jarvis-reload/hooks/jarvis-session-start.sh"
STOP_HOOK="$SCRIPT_DIR/skills/jarvis-reflect/hooks/jarvis-stop.sh"
VALIDATE="$SCRIPT_DIR/skills/jarvis-validate/references/validate.sh"
SEARCH="$SCRIPT_DIR/skills/jarvis-search/references/search.sh"

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
CURRENT_GROUP=""

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Assertion helpers ---
assert_contains() {
  local label="$1" output="$2" expected="$3"
  if echo "$output" | grep -qi "$expected"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf "  ${GREEN}PASS${RESET} %s\n" "$label"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf "  ${RED}FAIL${RESET} %s\n" "$label"
    printf "       expected to contain: %s\n" "$expected"
    printf "       got: %.200s\n" "$output"
  fi
}

assert_not_contains() {
  local label="$1" output="$2" unexpected="$3"
  if echo "$output" | grep -qi "$unexpected"; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf "  ${RED}FAIL${RESET} %s\n" "$label"
    printf "       should NOT contain: %s\n" "$unexpected"
  else
    PASS_COUNT=$((PASS_COUNT + 1))
    printf "  ${GREEN}PASS${RESET} %s\n" "$label"
  fi
}

assert_exit_code() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf "  ${GREEN}PASS${RESET} %s\n" "$label"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf "  ${RED}FAIL${RESET} %s\n" "$label"
    printf "       expected exit code %s, got %s\n" "$expected" "$actual"
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf "  ${GREEN}PASS${RESET} %s\n" "$label"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf "  ${RED}FAIL${RESET} %s\n" "$label"
    printf "       file not found: %s\n" "$path"
  fi
}

# --- Fixture helpers ---
scaffold_jarvis_dir() {
  local dir="$1"
  mkdir -p "$dir/memories" "$dir/journal"

  cat > "$dir/IDENTITY.md" << 'IDEOF'
# Agent Identity

## Core
- **Name**: (unnamed — awaiting first session)
- **Version**: 0.0
- **Last evolved**: never

## Personality
Not yet established. Identity emerges through work and reflection.

## Expertise
No demonstrated expertise yet. This section grows only through completed tasks.

## Principles
No principles established. These emerge from real experience, not aspiration.

## Tool Mastery
No tools mastered yet. Tracks effective patterns and pitfalls discovered through use.

## User Model
No observations yet. Preferences noted during collaboration appear here.
IDEOF

  cat > "$dir/GROWTH.md" << 'GEOF'
# Growth Log

| Date | Version | What changed | Why |
|------|---------|-------------|-----|
GEOF

  cat > "$dir/memories/preferences.md" << 'MEOF'
# User Preferences

## Consolidated
No consolidated preferences yet.

## Recent
MEOF

  cat > "$dir/memories/decisions.md" << 'DEOF'
# Key Decisions

## Consolidated
No consolidated decisions yet.

## Recent
DEOF
}

create_journal_entry() {
  local dir="$1" datetime="$2" tags="$3" task_type="$4" keyword="$5"
  # datetime format: 2026-03-15-14-30
  local filename="${datetime}.md"
  local date_part="${datetime:0:10}"
  local time_part="${datetime:11:2}:${datetime:14:2}"

  cat > "$dir/journal/$filename" << EOF
---
date: ${date_part}
time: ${time_part}
tags: [${tags}]
task_type: ${task_type}
---

# Session: ${keyword} work

## Task Summary
Worked on ${keyword} implementation and related tasks.

## Actions Taken
- Implemented ${keyword} functionality
- Tested the changes

## What Worked
The ${keyword} approach was effective.

## What Didn't Work
Some edge cases in ${keyword} needed extra handling.

## Lessons Learned
${keyword} requires careful attention to detail.

## Memory Updates
No memory updates needed.

## Identity Impact
Gained experience with ${keyword}.
EOF
}

create_populated_identity() {
  local dir="$1"
  cat > "$dir/IDENTITY.md" << 'IDEOF'
# Agent Identity

## Core
- **Name**: TestBot
- **Version**: 1.2
- **Last evolved**: 2026-03-10

## Personality
Methodical and thorough. Prefers explicit over implicit.

## Expertise
- Shell scripting and testing
- Markdown processing

## Principles
- Test before committing
- Keep things simple

## Tool Mastery
- Bash: proficient with pipelines and process substitution
- grep/awk: effective for structured text extraction

## User Model
Prefers concise output with clear error messages.
IDEOF
}

add_consolidated_memory() {
  local file="$1" content="$2"
  # Replace the line after ## Consolidated with the content
  local tmp
  tmp=$(mktemp)
  awk -v content="$content" '
    /^## Consolidated$/ { print; print content; skip=1; next }
    skip && /^$/ { skip=0; next }
    skip && /^## / { skip=0 }
    !skip { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

group() {
  CURRENT_GROUP="$1"
  echo ""
  printf "${BOLD}=== %s ===${RESET}\n" "$CURRENT_GROUP"
}

# ============================================================
# Group 1: jarvis-session-start.sh
# ============================================================
group "jarvis-session-start.sh"

# Test 1: No data dir
test_dir="$TEST_ROOT/ss1"
mkdir -p "$test_dir"
output=$(JARVIS_DIR="$test_dir/nonexistent" bash "$SESSION_START" 2>&1)
assert_contains "No data dir → 'not set up' message" "$output" "not set up"

# Test 2: Fresh scaffold (v0.0)
test_dir="$TEST_ROOT/ss2"
scaffold_jarvis_dir "$test_dir"
output=$(JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
assert_contains "Fresh scaffold → 'fresh JaRVIS setup' message" "$output" "fresh JaRVIS setup"

# Test 3: Populated identity + memories + 4 journals → loads identity, memories, 3 most recent
test_dir="$TEST_ROOT/ss3"
scaffold_jarvis_dir "$test_dir"
create_populated_identity "$test_dir"
add_consolidated_memory "$test_dir/memories/preferences.md" "- User likes dark mode"
create_journal_entry "$test_dir" "2026-03-10-09-00" "setup" "config" "alpha"
create_journal_entry "$test_dir" "2026-03-11-10-00" "testing" "feature" "beta"
create_journal_entry "$test_dir" "2026-03-12-11-00" "bugfix" "bugfix" "gamma"
create_journal_entry "$test_dir" "2026-03-13-14-00" "deploy" "feature" "delta"
output=$(JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
assert_contains "Loads identity (TestBot)" "$output" "TestBot"
assert_contains "Loads memories (dark mode)" "$output" "dark mode"
assert_contains "Loads most recent journal (delta)" "$output" "delta"
assert_not_contains "Does NOT load 4th oldest journal (alpha)" "$output" "alpha"

# Test 4: Empty memories dir
test_dir="$TEST_ROOT/ss4"
scaffold_jarvis_dir "$test_dir"
rm -f "$test_dir/memories/"*.md
output=$(JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
assert_not_contains "Empty memories dir → no Memories section" "$output" "## Memories:"

# Test 5: Memory with empty Consolidated
test_dir="$TEST_ROOT/ss5"
scaffold_jarvis_dir "$test_dir"
# Default scaffold has "No consolidated preferences yet." which is non-empty text
# Replace with truly empty consolidated
cat > "$test_dir/memories/preferences.md" << 'EOF'
# User Preferences

## Consolidated

## Recent
EOF
output=$(JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
assert_not_contains "Empty Consolidated → not included" "$output" "Memories: preferences"

# ============================================================
# Group 2: jarvis-stop.sh
# ============================================================
group "jarvis-stop.sh"

# Test 1: No data dir → silent exit
test_dir="$TEST_ROOT/stop1"
mkdir -p "$test_dir"
output=$(JARVIS_DIR="$test_dir/nonexistent" bash "$STOP_HOOK" 2>&1)
rc=$?
assert_exit_code "No data dir → exit 0" "$rc" 0
assert_not_contains "No data dir → silent (no output)" "$output" "reflect"

# Test 2: No journal dir → silent exit
test_dir="$TEST_ROOT/stop2"
mkdir -p "$test_dir"
output=$(JARVIS_DIR="$test_dir" bash "$STOP_HOOK" 2>&1)
rc=$?
assert_exit_code "No journal dir → exit 0" "$rc" 0

# Test 3: No recent entries → outputs reminder
test_dir="$TEST_ROOT/stop3"
scaffold_jarvis_dir "$test_dir"
create_journal_entry "$test_dir" "2026-03-10-09-00" "old" "feature" "oldwork"
# Set mtime to 4 hours ago
touch -t 202603100100.00 "$test_dir/journal/2026-03-10-09-00.md"
output=$(JARVIS_DIR="$test_dir" bash "$STOP_HOOK" 2>&1)
assert_contains "No recent entries → reminder" "$output" "haven't reflected"

# Test 4: Recent entry exists → silent
test_dir="$TEST_ROOT/stop4"
scaffold_jarvis_dir "$test_dir"
create_journal_entry "$test_dir" "2026-03-15-14-00" "recent" "feature" "freshwork"
# Touch to now to ensure it's recent
touch "$test_dir/journal/2026-03-15-14-00.md"
output=$(JARVIS_DIR="$test_dir" bash "$STOP_HOOK" 2>&1)
assert_not_contains "Recent entry → silent" "$output" "reflect"

# ============================================================
# Group 3: validate.sh
# ============================================================
group "validate.sh"

# Test 1: Valid fresh scaffold → exit 0
test_dir="$TEST_ROOT/val1"
scaffold_jarvis_dir "$test_dir"
output=$(bash "$VALIDATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Valid fresh scaffold → exit 0" "$rc" 0
assert_contains "Valid fresh scaffold → 0 failed" "$output" "0 failed"

# Test 2: Valid scaffold + well-formed journal → exit 0
test_dir="$TEST_ROOT/val2"
scaffold_jarvis_dir "$test_dir"
create_journal_entry "$test_dir" "2026-03-15-14-30" "testing" "feature" "widgets"
output=$(bash "$VALIDATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Valid scaffold + journal → exit 0" "$rc" 0
assert_contains "Valid scaffold + journal → 0 failed" "$output" "0 failed"

# Test 3: Missing IDENTITY.md → FAIL
test_dir="$TEST_ROOT/val3"
scaffold_jarvis_dir "$test_dir"
rm "$test_dir/IDENTITY.md"
output=$(bash "$VALIDATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Missing IDENTITY.md → exit 1" "$rc" 1
assert_contains "Missing IDENTITY.md → FAIL message" "$output" "IDENTITY.md not found"

# Test 4: IDENTITY.md missing sections → FAIL
test_dir="$TEST_ROOT/val4"
scaffold_jarvis_dir "$test_dir"
# Remove the Expertise and Principles sections
cat > "$test_dir/IDENTITY.md" << 'EOF'
# Agent Identity

## Core
- **Name**: Incomplete
- **Version**: 0.1
- **Last evolved**: never

## Personality
Some personality.
EOF
output=$(bash "$VALIDATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Missing identity sections → exit 1" "$rc" 1
assert_contains "Missing Expertise section" "$output" "missing section: Expertise"

# Test 5: GROWTH.md missing table → FAIL
test_dir="$TEST_ROOT/val5"
scaffold_jarvis_dir "$test_dir"
echo "# Growth Log" > "$test_dir/GROWTH.md"
output=$(bash "$VALIDATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "GROWTH.md missing table → exit 1" "$rc" 1
assert_contains "Missing table header" "$output" "missing table header"

# Test 6: GROWTH.md invalid date row → FAIL
test_dir="$TEST_ROOT/val6"
scaffold_jarvis_dir "$test_dir"
cat > "$test_dir/GROWTH.md" << 'EOF'
# Growth Log

| Date | Version | What changed | Why |
|------|---------|-------------|-----|
| march-ten | 1.0 | Something | Because |
EOF
output=$(bash "$VALIDATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Invalid date row → exit 1" "$rc" 1
assert_contains "Invalid date message" "$output" "invalid date"

# Test 7: Memory bad filename → FAIL
test_dir="$TEST_ROOT/val7"
scaffold_jarvis_dir "$test_dir"
cp "$test_dir/memories/preferences.md" "$test_dir/memories/Bad_Name.md"
output=$(bash "$VALIDATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Bad memory filename → exit 1" "$rc" 1
assert_contains "Bad filename message" "$output" "lowercase-with-hyphens"

# Test 8: Memory missing Consolidated → FAIL
test_dir="$TEST_ROOT/val8"
scaffold_jarvis_dir "$test_dir"
cat > "$test_dir/memories/preferences.md" << 'EOF'
# User Preferences

## Recent
Some recent stuff.
EOF
output=$(bash "$VALIDATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Missing Consolidated section → exit 1" "$rc" 1
assert_contains "Missing Consolidated" "$output" "missing ## Consolidated"

# Test 9: Journal wrong filename format → FAIL
test_dir="$TEST_ROOT/val9"
scaffold_jarvis_dir "$test_dir"
create_journal_entry "$test_dir" "2026-03-15-14-30" "testing" "feature" "good"
# Create a bad-named journal
cp "$test_dir/journal/2026-03-15-14-30.md" "$test_dir/journal/my-journal.md"
output=$(bash "$VALIDATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Bad journal filename → exit 1" "$rc" 1
assert_contains "Bad journal filename message" "$output" "should match YYYY-MM-DD-HH-MM"

# Test 10: Journal empty section → FAIL
test_dir="$TEST_ROOT/val10"
scaffold_jarvis_dir "$test_dir"
cat > "$test_dir/journal/2026-03-15-14-30.md" << 'EOF'
---
date: 2026-03-15
time: 14:30
tags: [testing]
task_type: feature
---

# Session: empty sections

## Task Summary
Did some work.

## Actions Taken

## What Worked
Something worked.

## What Didn't Work
Nothing failed.

## Lessons Learned
Learned stuff.

## Memory Updates
No updates.

## Identity Impact
Some impact.
EOF
output=$(bash "$VALIDATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Empty journal section → exit 1" "$rc" 1
assert_contains "Empty section detected" "$output" "Actions Taken is empty"

# Test 11: Journal with invalid task_type → FAIL
test_dir="$TEST_ROOT/val11"
scaffold_jarvis_dir "$test_dir"
cat > "$test_dir/journal/2026-03-15-14-30.md" << 'EOF'
---
date: 2026-03-15
time: 14:30
tags: [testing]
task_type: banana
---

# Session: invalid task_type

## Task Summary
Did some work.

## Actions Taken
- Implemented something

## What Worked
Something worked.

## What Didn't Work
Nothing failed.

## Lessons Learned
Learned stuff.

## Memory Updates
No updates.

## Identity Impact
Some impact.
EOF
output=$(bash "$VALIDATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Invalid task_type 'banana' → exit 1" "$rc" 1
assert_contains "Invalid task_type message" "$output" "not valid"

# Test 12: Journal missing tags field → FAIL
test_dir="$TEST_ROOT/val12"
scaffold_jarvis_dir "$test_dir"
cat > "$test_dir/journal/2026-03-15-14-30.md" << 'EOF'
---
date: 2026-03-15
time: 14:30
task_type: feature
---

# Session: missing tags

## Task Summary
Did some work.

## Actions Taken
- Implemented something

## What Worked
Something worked.

## What Didn't Work
Nothing failed.

## Lessons Learned
Learned stuff.

## Memory Updates
No updates.

## Identity Impact
Some impact.
EOF
output=$(bash "$VALIDATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Missing tags field → exit 1" "$rc" 1
assert_contains "Missing tags message" "$output" "missing tags"

# Test 13: GROWTH.md invalid version format → FAIL
test_dir="$TEST_ROOT/val13"
scaffold_jarvis_dir "$test_dir"
cat > "$test_dir/GROWTH.md" << 'EOF'
# Growth Log

| Date | Version | What changed | Why |
|------|---------|-------------|-----|
| 2026-03-15 | abc | Something changed | Because reasons |
EOF
output=$(bash "$VALIDATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Invalid version 'abc' → exit 1" "$rc" 1
assert_contains "Invalid version message" "$output" "invalid version"

# ============================================================
# Group 4: search.sh
# ============================================================
group "search.sh"

# Setup shared search fixtures
SEARCH_DIR="$TEST_ROOT/search"
scaffold_jarvis_dir "$SEARCH_DIR"
create_populated_identity "$SEARCH_DIR"
add_consolidated_memory "$SEARCH_DIR/memories/preferences.md" "- User likes dark mode"
create_journal_entry "$SEARCH_DIR" "2026-03-10-09-00" "api, backend" "feature" "authentication"
create_journal_entry "$SEARCH_DIR" "2026-03-12-11-00" "frontend, css" "bugfix" "dashboard"
create_journal_entry "$SEARCH_DIR" "2026-03-14-15-00" "api, testing" "feature" "pagination"

# Test 1: --query keyword match
output=$(JARVIS_DIR="$SEARCH_DIR" bash "$SEARCH" --query "authentication" 2>&1)
assert_contains "Query keyword match → finds entry" "$output" "authentication"

# Test 2: --query no match
output=$(JARVIS_DIR="$SEARCH_DIR" bash "$SEARCH" --query "xyznonexistent" 2>&1)
assert_contains "Query no match → 'No matches'" "$output" "No matches found"

# Test 3: --type journal filter
output=$(JARVIS_DIR="$SEARCH_DIR" bash "$SEARCH" --type journal --query "dark mode" 2>&1)
assert_contains "Type journal → excludes memory results" "$output" "No matches found"

# Test 4: --tag filter
output=$(JARVIS_DIR="$SEARCH_DIR" bash "$SEARCH" --tag "frontend" --query "dashboard" 2>&1)
assert_contains "Tag filter → finds matching entry" "$output" "dashboard"
output2=$(JARVIS_DIR="$SEARCH_DIR" bash "$SEARCH" --tag "frontend" --query "authentication" 2>&1)
assert_contains "Tag filter → excludes non-matching" "$output2" "No matches found"

# Test 5: --task-type filter
output=$(JARVIS_DIR="$SEARCH_DIR" bash "$SEARCH" --task-type "bugfix" --query "dashboard" 2>&1)
assert_contains "Task-type filter → finds bugfix entry" "$output" "dashboard"
output2=$(JARVIS_DIR="$SEARCH_DIR" bash "$SEARCH" --task-type "bugfix" --query "authentication" 2>&1)
assert_contains "Task-type filter → excludes feature entry" "$output2" "No matches found"

# Test 6: --from/--to date range
output=$(JARVIS_DIR="$SEARCH_DIR" bash "$SEARCH" --from "2026-03-11" --to "2026-03-13" --query "dashboard" 2>&1)
assert_contains "Date range includes match" "$output" "dashboard"
output2=$(JARVIS_DIR="$SEARCH_DIR" bash "$SEARCH" --from "2026-03-11" --to "2026-03-13" --query "authentication" 2>&1)
assert_contains "Date range excludes out-of-range" "$output2" "No matches found"

# Test 7: --section filter
output=$(JARVIS_DIR="$SEARCH_DIR" bash "$SEARCH" --section "Lessons Learned" --query "authentication" 2>&1)
assert_contains "Section filter → searches within section" "$output" "authentication"

# Test 8: --type memory filter
output=$(JARVIS_DIR="$SEARCH_DIR" bash "$SEARCH" --type memory --query "dark mode" 2>&1)
assert_contains "Type memory → finds memory result" "$output" "dark mode"
output2=$(JARVIS_DIR="$SEARCH_DIR" bash "$SEARCH" --type memory --query "authentication" 2>&1)
assert_contains "Type memory → excludes journal results" "$output2" "No matches found"

# Test 9: Combined filters (tag + date range + query)
output=$(JARVIS_DIR="$SEARCH_DIR" bash "$SEARCH" --tag "api" --from "2026-03-13" --to "2026-03-15" --query "pagination" 2>&1)
assert_contains "Combined filters → finds matching entry" "$output" "pagination"
output2=$(JARVIS_DIR="$SEARCH_DIR" bash "$SEARCH" --tag "api" --from "2026-03-13" --to "2026-03-15" --query "authentication" 2>&1)
assert_contains "Combined filters → excludes out-of-range" "$output2" "No matches found"

# Test 10: Empty data dir (no journals, no memories)
empty_search_dir="$TEST_ROOT/search_empty"
mkdir -p "$empty_search_dir/journal" "$empty_search_dir/memories"
cat > "$empty_search_dir/IDENTITY.md" << 'IDEOF'
# Agent Identity

## Core
- **Name**: (unnamed)
- **Version**: 0.0
- **Last evolved**: never
IDEOF
cat > "$empty_search_dir/GROWTH.md" << 'GEOF'
# Growth Log

| Date | Version | What changed | Why |
|------|---------|-------------|-----|
GEOF
output=$(JARVIS_DIR="$empty_search_dir" bash "$SEARCH" --query "anything" 2>&1)
assert_contains "Empty data dir → no matches (graceful)" "$output" "No matches found"

# Test 11: --jarvis-dir flag
output=$(bash "$SEARCH" --jarvis-dir "$SEARCH_DIR" --query "authentication" 2>&1)
assert_contains "--jarvis-dir flag → overrides default" "$output" "authentication"

# Test 12: --type journal excludes memory (reverse of test 3, for completeness - already covered)
# (Test 3 already covers --type journal excluding memories)

# ============================================================
# Group 5: Path resolution
# ============================================================
group "Path resolution"

# Test 1: JARVIS_DIR env var override
test_dir="$TEST_ROOT/path1"
scaffold_jarvis_dir "$test_dir"
output=$(JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
assert_contains "JARVIS_DIR override → uses custom path" "$output" "jarvis-session-context"

# Test 2: CLAUDE_PROJECT_DIR slug resolution
test_dir="$TEST_ROOT/path2"
fake_home="$TEST_ROOT/fakehome"
expected_slug="data-test-my-project"
mkdir -p "$fake_home/.jarvis/projects/$expected_slug"
scaffold_jarvis_dir "$fake_home/.jarvis/projects/$expected_slug"
output=$(unset JARVIS_DIR; HOME="$fake_home" CLAUDE_PROJECT_DIR="/data/test/My Project" bash "$SESSION_START" 2>&1)
assert_contains "CLAUDE_PROJECT_DIR slug resolution" "$output" "jarvis-session-context"

# Test 3: pwd fallback
test_dir="$TEST_ROOT/path3"
fake_home="$TEST_ROOT/fakehome2"
# pwd-based slug: simulate by deriving slug from a known directory
work_dir="$TEST_ROOT/workdir"
mkdir -p "$work_dir"
work_slug=$(echo "$work_dir" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
mkdir -p "$fake_home/.jarvis/projects/$work_slug"
scaffold_jarvis_dir "$fake_home/.jarvis/projects/$work_slug"
output=$(cd "$work_dir" && unset JARVIS_DIR; unset CLAUDE_PROJECT_DIR; HOME="$fake_home" bash "$SESSION_START" 2>&1)
assert_contains "pwd fallback slug resolution" "$output" "jarvis-session-context"

# ============================================================
# Summary
# ============================================================
echo ""
echo "========================================"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf "${BOLD}Results:${RESET} ${GREEN}%d passed${RESET}, ${RED}%d failed${RESET} (%d total)\n" \
  "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
