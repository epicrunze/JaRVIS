#!/usr/bin/env bash
# JaRVIS Integration Tests
# Tests the 4 shell scripts: session-start, stop, validate, search
# No external dependencies — uses JARVIS_DIR env var for fixture isolation.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SESSION_START="$SCRIPT_DIR/skills/jarvis-reload/scripts/jarvis-session-start.sh"
STOP_HOOK="$SCRIPT_DIR/skills/jarvis-reflect/scripts/jarvis-stop.sh"
VALIDATE="$SCRIPT_DIR/skills/jarvis-validate/scripts/validate.sh"
SEARCH="$SCRIPT_DIR/skills/jarvis-search/scripts/search.sh"
RESOLVE_DIR="$SCRIPT_DIR/skills/jarvis-init/scripts/resolve-dir.sh"
JARVIS_INIT="$SCRIPT_DIR/skills/jarvis-init/scripts/jarvis-init.sh"
CURSOR_SESSION_START="$SCRIPT_DIR/skills/jarvis-reload/scripts/jarvis-session-start-cursor.sh"
CURSOR_STOP="$SCRIPT_DIR/skills/jarvis-reflect/scripts/jarvis-stop-cursor.sh"
COPILOT_SESSION_START="$SCRIPT_DIR/skills/jarvis-reload/scripts/jarvis-session-start-copilot.sh"
COPILOT_SESSION_END="$SCRIPT_DIR/skills/jarvis-reflect/scripts/jarvis-session-end-copilot.sh"
MIGRATE="$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrate.sh"
PLUGIN_LATEST=$(cat "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrations/LATEST" 2>/dev/null || echo 0)

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

assert_file_not_exists() {
  local label="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf "  ${GREEN}PASS${RESET} %s\n" "$label"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf "  ${RED}FAIL${RESET} %s\n" "$label"
    printf "       file should not exist: %s\n" "$path"
  fi
}

assert_equals() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf "  ${GREEN}PASS${RESET} %s\n" "$label"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf "  ${RED}FAIL${RESET} %s\n" "$label"
    printf "       expected: %s\n" "$expected"
    printf "       got: %s\n" "$actual"
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
  local uuid_suffix
  uuid_suffix=$(head -c4 /dev/urandom | xxd -p)
  local filename="${datetime}-${uuid_suffix}.md"
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

# Stage a fake migration into a temporary migrations dir for runner tests.
# Args: <migrations-dir> <NNN> <stdout-line> [<exit-code>]
make_fake_migration() {
  local mig_dir="$1" nnn="$2" line="$3" rc="${4:-0}"
  mkdir -p "$mig_dir"
  cat > "$mig_dir/${nnn}-test.sh" << EOF
#!/usr/bin/env bash
. "\$(dirname "\$0")/_lib.sh"
log_change "$line"
exit $rc
EOF
  chmod +x "$mig_dir/${nnn}-test.sh"
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
output=$(echo '{}' | JARVIS_DIR="$test_dir/nonexistent" bash "$SESSION_START" 2>&1)
assert_contains "No data dir → 'not set up' message" "$output" "not set up"

# Test 2: Fresh scaffold (v0.0)
test_dir="$TEST_ROOT/ss2"
scaffold_jarvis_dir "$test_dir"
output=$(echo '{}' | JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
assert_contains "Fresh scaffold → 'fresh JaRVIS setup' message" "$output" "fresh JaRVIS setup"

# Test 3: Populated identity + memories → loads identity and consolidated memories
# (Journal entries are intentionally NOT loaded by the SessionStart hook — the agent
# consults journals via /jarvis-search on demand. This test confirms identity and
# memory loading; journal-loading was removed from the hook.)
test_dir="$TEST_ROOT/ss3"
scaffold_jarvis_dir "$test_dir"
create_populated_identity "$test_dir"
add_consolidated_memory "$test_dir/memories/preferences.md" "- User likes dark mode"
output=$(echo '{}' | JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
assert_contains "Loads identity (TestBot)" "$output" "TestBot"
assert_contains "Loads memories (dark mode)" "$output" "dark mode"

# Test 4: Empty memories dir
test_dir="$TEST_ROOT/ss4"
scaffold_jarvis_dir "$test_dir"
rm -f "$test_dir/memories/"*.md
output=$(echo '{}' | JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
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
output=$(echo '{}' | JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
assert_not_contains "Empty Consolidated → not included" "$output" "Memories: preferences"

# Test 6: SessionStart on unmigrated dir → context includes migration changelog
test_dir="$TEST_ROOT/ss6"
scaffold_jarvis_dir "$test_dir"
# Simulate a pre-migration dir: no stamp, no .gitignore
rm -f "$test_dir/.gitignore" "$test_dir/.jarvis-data-version"
output=$(echo '{"session_id": "ss6"}' | JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
rc=$?
assert_exit_code "Unmigrated dir → hook exit 0" "$rc" 0
assert_contains "Migration changelog in context" "$output" "migrated v0 → v1"
assert_contains "Migration bullet in context" "$output" "001-add-gitignore"
assert_file_exists "Migration ran .gitignore" "$test_dir/.gitignore"

# Test 7: SessionStart on already-migrated dir → no migration block in context
test_dir="$TEST_ROOT/ss7"
scaffold_jarvis_dir "$test_dir"
echo "$PLUGIN_LATEST" > "$test_dir/.jarvis-data-version"
echo ".pending-*" > "$test_dir/.gitignore"
output=$(echo '{"session_id": "ss7"}' | JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
rc=$?
assert_exit_code "Migrated dir → hook exit 0" "$rc" 0
assert_not_contains "No migration block in context" "$output" "migrated v"

# Test 8: SessionStart with a failing migration → hook exits non-zero, error in context
test_dir="$TEST_ROOT/ss8"
fake_plugin="$TEST_ROOT/ss8_plugin"
scaffold_jarvis_dir "$test_dir"
rm -f "$test_dir/.jarvis-data-version"
# Build a fake plugin tree that the hook resolves via SCRIPT_DIR/../../jarvis-migrate/...
mkdir -p "$fake_plugin/skills/jarvis-reload/scripts" "$fake_plugin/skills/jarvis-migrate/scripts/migrations"
cp "$SESSION_START" "$fake_plugin/skills/jarvis-reload/scripts/jarvis-session-start.sh"
cp "$RESOLVE_DIR" "$fake_plugin/skills/jarvis-reload/scripts/resolve-dir.sh"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrate.sh" "$fake_plugin/skills/jarvis-migrate/scripts/migrate.sh"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/resolve-dir.sh" "$fake_plugin/skills/jarvis-migrate/scripts/resolve-dir.sh"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrations/_lib.sh" "$fake_plugin/skills/jarvis-migrate/scripts/migrations/_lib.sh"
make_fake_migration "$fake_plugin/skills/jarvis-migrate/scripts/migrations" "001" "broken migration" 1
echo "1" > "$fake_plugin/skills/jarvis-migrate/scripts/migrations/LATEST"
output=$(echo '{"session_id": "ss8"}' | JARVIS_DIR="$test_dir" bash "$fake_plugin/skills/jarvis-reload/scripts/jarvis-session-start.sh" 2>&1)
rc=$?
assert_exit_code "Failing migration → hook exits 1" "$rc" 1
assert_contains "Failing migration → 'migration failed' in output" "$output" "migration failed"
assert_contains "Failing migration → migration name in output" "$output" "001-test"

# ============================================================
# Group 2: jarvis-stop.sh
# ============================================================
group "jarvis-stop.sh"

# Test 1: No data dir → silent exit
test_dir="$TEST_ROOT/stop1"
mkdir -p "$test_dir"
output=$(echo '{"session_id": "test1"}' | JARVIS_DIR="$test_dir/nonexistent" bash "$STOP_HOOK" 2>&1)
rc=$?
assert_exit_code "No data dir → exit 0" "$rc" 0
assert_not_contains "No data dir → silent (no output)" "$output" "reflect"

# Test 2: No pending marker → silent exit
test_dir="$TEST_ROOT/stop2"
scaffold_jarvis_dir "$test_dir"
output=$(echo '{"session_id": "test2"}' | JARVIS_DIR="$test_dir" bash "$STOP_HOOK" 2>&1)
rc=$?
assert_exit_code "No pending marker → exit 0" "$rc" 0
assert_not_contains "No pending marker → silent" "$output" "block"

# Test 3: Aged pending marker without transcript → blocks via rule 5 (Cursor fallback)
test_dir="$TEST_ROOT/stop3"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-test3"
# Age the marker past 5 minutes so rule 5 (no transcript + age >= 300s) fires.
touch -d '10 minutes ago' "$test_dir/.pending-test3"
mkdir -p "$test_dir/empty-project"
output=$(echo '{"session_id": "test3"}' | JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$STOP_HOOK" 2>&1)
assert_contains "Aged marker, no transcript → blocking JSON" "$output" '"decision"'
assert_contains "Aged marker, no transcript → block value" "$output" '"block"'
assert_contains "Aged marker, no transcript → has reason" "$output" "Reminder to reflect"

# Test 4: Different session's pending marker → silent
test_dir="$TEST_ROOT/stop4"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-other"
output=$(echo '{"session_id": "test4"}' | JARVIS_DIR="$test_dir" bash "$STOP_HOOK" 2>&1)
assert_not_contains "Different session's marker → silent" "$output" "block"

# Test 5: stop_hook_active=true → silent exit (prevents infinite loop)
test_dir="$TEST_ROOT/stop5"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-test5"
output=$(echo '{"session_id": "test5", "stop_hook_active": true}' | JARVIS_DIR="$test_dir" bash "$STOP_HOOK" 2>&1)
rc=$?
assert_exit_code "stop_hook_active=true → exit 0" "$rc" 0
assert_not_contains "stop_hook_active=true → no output" "$output" "block"

# Test 6: No session_id in stdin → silent (can't check without session ID)
test_dir="$TEST_ROOT/stop6"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-something"
output=$(echo '{}' | JARVIS_DIR="$test_dir" bash "$STOP_HOOK" 2>&1)
assert_not_contains "No session_id → silent" "$output" "block"

# --- Helper for transcript fixtures (used by gate tests below) ---
make_transcript() {
  local path="$1"; shift
  : > "$path"
  for line in "$@"; do printf '%s\n' "$line" >> "$path"; done
}

# Test 7: Rule 1 — last message is a question, no mutating tool calls → SKIP
test_dir="$TEST_ROOT/stop7"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-q1"
touch -d '10 minutes ago' "$test_dir/.pending-q1"
mkdir -p "$test_dir/empty-project"
tx="$test_dir/transcript.jsonl"
make_transcript "$tx" \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"Should I use option A or B?"}]}}'
output=$(echo "{\"session_id\":\"q1\",\"transcript_path\":\"$tx\"}" | \
  JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$STOP_HOOK" 2>&1)
assert_not_contains "Rule 1: question + no tools → silent" "$output" "block"

# Test 8: Rule 1 with markdown bold around the question → still SKIP
test_dir="$TEST_ROOT/stop8"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-q2"
touch -d '10 minutes ago' "$test_dir/.pending-q2"
mkdir -p "$test_dir/empty-project"
tx="$test_dir/transcript.jsonl"
make_transcript "$tx" \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"**Continue?**"}]}}'
output=$(echo "{\"session_id\":\"q2\",\"transcript_path\":\"$tx\"}" | \
  JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$STOP_HOOK" 2>&1)
assert_not_contains "Rule 1: bold question → silent" "$output" "block"

# Test 9: Rule 1 takes precedence over Rule 2 — trailing question + Edit → SKIP
test_dir="$TEST_ROOT/stop9"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-edit1"
touch -d '10 minutes ago' "$test_dir/.pending-edit1"
mkdir -p "$test_dir/empty-project"
tx="$test_dir/transcript.jsonl"
make_transcript "$tx" \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"Done?"},{"type":"tool_use","name":"Edit","input":{}}]}}'
output=$(echo "{\"session_id\":\"edit1\",\"transcript_path\":\"$tx\"}" | \
  JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$STOP_HOOK" 2>&1)
assert_not_contains "Rule 1 precedence: question wins over Edit → silent" "$output" "block"

# Test 9b: Rule 2 — Edit tool with no question in last paragraph → BLOCK
test_dir="$TEST_ROOT/stop9b"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-edit2"
touch -d '10 minutes ago' "$test_dir/.pending-edit2"
mkdir -p "$test_dir/empty-project"
tx="$test_dir/transcript.jsonl"
make_transcript "$tx" \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"Done."},{"type":"tool_use","name":"Edit","input":{}}]}}'
output=$(echo "{\"session_id\":\"edit2\",\"transcript_path\":\"$tx\"}" | \
  JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$STOP_HOOK" 2>&1)
assert_contains "Rule 2: Edit tool, no question → block" "$output" '"block"'

# Test 10: Rule 3 — file modified since marker mtime → BLOCK (no transcript)
test_dir="$TEST_ROOT/stop10"
scaffold_jarvis_dir "$test_dir"
mkdir -p "$test_dir/proj"
touch "$test_dir/.pending-fs1"
touch -d '2 hours ago' "$test_dir/.pending-fs1"
echo "x" > "$test_dir/proj/somefile.txt"
output=$(echo '{"session_id":"fs1"}' | \
  JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/proj" bash "$STOP_HOOK" 2>&1)
assert_contains "Rule 3: file modified after marker → block" "$output" '"block"'

# Test 11: Pure-read session — 5 read-only Read calls, no question → SKIP
# (v0.1.3 removed Rule 4 entirely; read-only exploration no longer triggers the reminder.)
test_dir="$TEST_ROOT/stop11"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-r1"
touch -d '10 minutes ago' "$test_dir/.pending-r1"
mkdir -p "$test_dir/empty-project"
tx="$test_dir/transcript.jsonl"
make_transcript "$tx" \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{}}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{}}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{}}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{}}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{}}]}}'
output=$(echo "{\"session_id\":\"r1\",\"transcript_path\":\"$tx\"}" | \
  JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$STOP_HOOK" 2>&1)
assert_not_contains "Pure-read session → silent" "$output" "block"

# Test 11b: Rule 1 — '?' followed by a brief clarification tag → SKIP
# Mirrors the dcc-launch transcript: question in penultimate sentence, period at end.
test_dir="$TEST_ROOT/stop11b"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-tag1"
touch -d '10 minutes ago' "$test_dir/.pending-tag1"
mkdir -p "$test_dir/empty-project"
tx="$test_dir/transcript.jsonl"
make_transcript "$tx" \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"Which VPN are we targeting? That decides between option 1 and 2."}]}}'
output=$(echo "{\"session_id\":\"tag1\",\"transcript_path\":\"$tx\"}" | \
  JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$STOP_HOOK" 2>&1)
assert_not_contains "Rule 1: question + clarification tag → silent" "$output" "block"

# Test 11c: Rule 1 — deferring phrase ("Let me know") with no '?' → SKIP
test_dir="$TEST_ROOT/stop11c"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-defer1"
touch -d '10 minutes ago' "$test_dir/.pending-defer1"
mkdir -p "$test_dir/empty-project"
tx="$test_dir/transcript.jsonl"
make_transcript "$tx" \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"Two options above. Let me know which one you prefer."}]}}'
output=$(echo "{\"session_id\":\"defer1\",\"transcript_path\":\"$tx\"}" | \
  JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$STOP_HOOK" 2>&1)
assert_not_contains "Rule 1: deferring phrase → silent" "$output" "block"

# Test 11d: Last-paragraph scope — '?' in an earlier paragraph does NOT save a final "Done." paragraph → BLOCK
test_dir="$TEST_ROOT/stop11d"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-multi1"
touch -d '10 minutes ago' "$test_dir/.pending-multi1"
mkdir -p "$test_dir/empty-project"
tx="$test_dir/transcript.jsonl"
make_transcript "$tx" \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"Why did I do this? Because Y.\n\nDone."},{"type":"tool_use","name":"Edit","input":{}}]}}'
output=$(echo "{\"session_id\":\"multi1\",\"transcript_path\":\"$tx\"}" | \
  JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$STOP_HOOK" 2>&1)
assert_contains "Rule 1 paragraph-scope: earlier '?' does not save → block" "$output" '"block"'

# Test 11e: Documented limitation — rhetorical '?' in last paragraph false-SKIPs.
# Accepted tradeoff: bias toward silence over question-precision.
test_dir="$TEST_ROOT/stop11e"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-rhet1"
touch -d '10 minutes ago' "$test_dir/.pending-rhet1"
mkdir -p "$test_dir/empty-project"
tx="$test_dir/transcript.jsonl"
make_transcript "$tx" \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"Done refactoring. Why? Because the old code was confusing."},{"type":"tool_use","name":"Edit","input":{}}]}}'
output=$(echo "{\"session_id\":\"rhet1\",\"transcript_path\":\"$tx\"}" | \
  JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$STOP_HOOK" 2>&1)
assert_not_contains "Rule 1 rhetorical-? in last paragraph → silent (accepted tradeoff)" "$output" "block"

# Test 12: Rule 5 — no transcript, marker aged > 5 min → BLOCK (Cursor fallback)
test_dir="$TEST_ROOT/stop12"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-age1"
touch -d '10 minutes ago' "$test_dir/.pending-age1"
mkdir -p "$test_dir/empty-project"
output=$(echo '{"session_id":"age1"}' | \
  JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$STOP_HOOK" 2>&1)
assert_contains "Rule 5: no transcript + old marker → block" "$output" '"block"'

# Test 13: Rule 6 — fresh marker, no transcript → SKIP (young session)
test_dir="$TEST_ROOT/stop13"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-young1"
mkdir -p "$test_dir/empty-project"
output=$(echo '{"session_id":"young1"}' | \
  JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$STOP_HOOK" 2>&1)
assert_not_contains "Rule 6: fresh marker → silent" "$output" "block"

# Test 14: Unhappy path — transcript_path points to a missing file → falls through gracefully
test_dir="$TEST_ROOT/stop14"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-miss1"
mkdir -p "$test_dir/empty-project"
output=$(echo '{"session_id":"miss1","transcript_path":"/nonexistent/transcript.jsonl"}' | \
  JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$STOP_HOOK" 2>&1)
rc=$?
assert_exit_code "Missing transcript → exit 0 (no crash)" "$rc" 0
assert_not_contains "Missing transcript + fresh marker → silent" "$output" "block"

# Test 15: Unhappy path — malformed transcript → SKIP (parse fails, falls through)
test_dir="$TEST_ROOT/stop15"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-bad1"
mkdir -p "$test_dir/empty-project"
tx="$test_dir/transcript.jsonl"
printf 'not-json\n{"type":"assistant"\nbroken\n' > "$tx"
output=$(echo "{\"session_id\":\"bad1\",\"transcript_path\":\"$tx\"}" | \
  JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$STOP_HOOK" 2>&1)
rc=$?
assert_exit_code "Malformed transcript → exit 0 (no crash)" "$rc" 0
assert_not_contains "Malformed transcript + fresh marker → silent" "$output" "block"

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
# Create a bad-named journal (copy from whichever UUID-named file was created)
good_journal=$(ls -1 "$test_dir/journal/"*.md | head -1)
cp "$good_journal" "$test_dir/journal/my-journal.md"
output=$(bash "$VALIDATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Bad journal filename → exit 1" "$rc" 1
assert_contains "Bad journal filename message" "$output" "should match YYYY-MM-DD-HH-MM"  # matches both old and new format error

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
output=$(echo '{}' | JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
assert_contains "JARVIS_DIR override → uses custom path" "$output" "jarvis-session-context"

# Test 2: CLAUDE_PROJECT_DIR slug resolution
test_dir="$TEST_ROOT/path2"
fake_home="$TEST_ROOT/fakehome"
expected_slug="data-test-my-project"
mkdir -p "$fake_home/.jarvis/projects/$expected_slug"
scaffold_jarvis_dir "$fake_home/.jarvis/projects/$expected_slug"
output=$(echo '{}' | unset JARVIS_DIR; HOME="$fake_home" CLAUDE_PROJECT_DIR="/data/test/My Project" bash "$SESSION_START" 2>&1)
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
output=$(cd "$work_dir" && echo '{}' | unset JARVIS_DIR; unset CLAUDE_PROJECT_DIR; HOME="$fake_home" bash "$SESSION_START" 2>&1)
assert_contains "pwd fallback slug resolution" "$output" "jarvis-session-context"

# ============================================================
# Group 6: resolve-dir.sh
# ============================================================
group "resolve-dir.sh"

# Test 1: JARVIS_DIR env var takes precedence
output=$(JARVIS_DIR="/custom/path" bash -c 'source '"$RESOLVE_DIR"'; echo "$JARVIS_DIR"' 2>&1)
assert_contains "JARVIS_DIR env var preserved" "$output" "/custom/path"

# Test 2: CLAUDE_PROJECT_DIR slugification
output=$(unset JARVIS_DIR; CLAUDE_PROJECT_DIR="/data/test/My Project" HOME="$TEST_ROOT" bash -c 'source '"$RESOLVE_DIR"'; echo "$JARVIS_DIR"' 2>&1)
assert_contains "CLAUDE_PROJECT_DIR slug → lowercase" "$output" "data-test-my-project"
assert_contains "CLAUDE_PROJECT_DIR slug → under ~/.jarvis/projects/" "$output" ".jarvis/projects/"

# Test 3: Spaces replaced with hyphens
output=$(unset JARVIS_DIR; CLAUDE_PROJECT_DIR="/path/with spaces/in it" HOME="$TEST_ROOT" bash -c 'source '"$RESOLVE_DIR"'; echo "$JARVIS_DIR"' 2>&1)
assert_contains "Spaces → hyphens" "$output" "path-with-spaces-in-it"

# Test 4: Uppercase converted to lowercase
output=$(unset JARVIS_DIR; CLAUDE_PROJECT_DIR="/Users/Bob/Projects/MyApp" HOME="$TEST_ROOT" bash -c 'source '"$RESOLVE_DIR"'; echo "$JARVIS_DIR"' 2>&1)
assert_contains "Uppercase → lowercase" "$output" "users-bob-projects-myapp"

# Test 5: Temporary vars are cleaned up
output=$(unset JARVIS_DIR; CLAUDE_PROJECT_DIR="/test" HOME="$TEST_ROOT" bash -c 'source '"$RESOLVE_DIR"'; echo "slug=${_jarvis_slug:-UNSET} dir=${_jarvis_project_dir:-UNSET}"' 2>&1)
assert_contains "Temp vars cleaned up" "$output" "slug=UNSET dir=UNSET"

# ============================================================
# Group 7: jarvis-init.sh
# ============================================================
group "jarvis-init.sh"

# Test 1: Fresh scaffold creates directory structure
test_dir="$TEST_ROOT/init1"
fake_home="$TEST_ROOT/inithome1"
mkdir -p "$fake_home"
output=$(unset JARVIS_DIR; HOME="$fake_home" CLAUDE_PROJECT_DIR="/test/project" bash "$JARVIS_INIT" 2>&1)
expected_dir="$fake_home/.jarvis/projects/test-project"
assert_contains "Fresh init → prints path" "$output" "$expected_dir"
assert_file_exists "Scaffold creates IDENTITY.md" "$expected_dir/IDENTITY.md"
assert_file_exists "Scaffold creates GROWTH.md" "$expected_dir/GROWTH.md"
assert_file_exists "Scaffold creates preferences.md" "$expected_dir/memories/preferences.md"
assert_file_exists "Scaffold creates decisions.md" "$expected_dir/memories/decisions.md"

# Test 2: Scaffold has git repo
git_output=$(cd "$expected_dir" && git log --oneline 2>&1)
assert_contains "Scaffold has git commit" "$git_output" "jarvis: initial scaffold"

# Test 3: Idempotency — running again prints ALREADY_EXISTS
output=$(unset JARVIS_DIR; HOME="$fake_home" CLAUDE_PROJECT_DIR="/test/project" bash "$JARVIS_INIT" 2>&1)
assert_contains "Second run → ALREADY_EXISTS" "$output" "ALREADY_EXISTS"

# Test 5: --project-dir flag
test_dir="$TEST_ROOT/init5"
fake_home="$TEST_ROOT/inithome5"
mkdir -p "$fake_home" "$test_dir"
output=$(unset JARVIS_DIR; unset CLAUDE_PROJECT_DIR; HOME="$fake_home" bash "$JARVIS_INIT" --project-dir "/custom/project/path" 2>&1)
assert_contains "--project-dir → uses custom path slug" "$output" "custom-project-path"

# Test 6: Migration — --migrate with existing .jarvis/
test_dir="$TEST_ROOT/init6"
fake_home="$TEST_ROOT/inithome6"
project_dir="$TEST_ROOT/init6_project"
mkdir -p "$fake_home" "$project_dir/.jarvis/memories"
echo "# Old Identity" > "$project_dir/.jarvis/IDENTITY.md"
echo "# Old Prefs" > "$project_dir/.jarvis/memories/preferences.md"
output=$(unset JARVIS_DIR; HOME="$fake_home" bash "$JARVIS_INIT" --project-dir "$project_dir" --migrate 2>&1)
assert_contains "Migration → prints MIGRATED" "$output" "MIGRATED"
# Check that old content was copied
migrated_slug=$(echo "$project_dir" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
migrated_dir="$fake_home/.jarvis/projects/$migrated_slug"
if [[ -f "$migrated_dir/IDENTITY.md" ]]; then
  migrated_content=$(cat "$migrated_dir/IDENTITY.md")
  assert_contains "Migration copies old IDENTITY.md content" "$migrated_content" "Old Identity"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "  ${RED}FAIL${RESET} Migration copies IDENTITY.md\n"
fi

# Test 7: Template content matches scaffolding expectations
test_dir="$TEST_ROOT/init7"
fake_home="$TEST_ROOT/inithome7"
mkdir -p "$fake_home"
output=$(unset JARVIS_DIR; HOME="$fake_home" CLAUDE_PROJECT_DIR="/test/templates" bash "$JARVIS_INIT" 2>&1)
template_dir="$fake_home/.jarvis/projects/test-templates"
identity_content=$(cat "$template_dir/IDENTITY.md")
assert_contains "Template has Core section" "$identity_content" "## Core"
assert_contains "Template has version 0.0" "$identity_content" "0.0"
growth_content=$(cat "$template_dir/GROWTH.md")
assert_contains "Template has Growth Log table" "$growth_content" "| Date | Version |"

# Test 8: Init creates .gitignore with .pending-* pattern
assert_file_exists "Scaffold creates .gitignore" "$template_dir/.gitignore"
gitignore_content=$(cat "$template_dir/.gitignore")
assert_contains ".gitignore has .pending-* pattern" "$gitignore_content" ".pending-\*"

# Test 9: .gitignore is in initial commit
git_files=$(cd "$template_dir" && git ls-files)
assert_contains ".gitignore is tracked in git" "$git_files" ".gitignore"

# Test 10: Init writes .jarvis-data-version at LATEST
assert_file_exists "Init creates .jarvis-data-version" "$template_dir/.jarvis-data-version"
stamp_content=$(cat "$template_dir/.jarvis-data-version")
expected_latest=$(cat "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrations/LATEST")
assert_equals "Init stamp == migrations/LATEST" "$stamp_content" "$expected_latest"

# Test 11: After init, migrate.sh is a no-op
output=$(bash "$MIGRATE" "$template_dir" 2>&1)
rc=$?
assert_exit_code "Post-init migrate → exit 0" "$rc" 0
assert_equals "Post-init migrate → silent" "$output" ""

# ============================================================
# Group 7b: Canonicalization (symlinks, subdirs, legacy fallback)
# ============================================================
group "Path canonicalization"

# Test 1: Symlinked path produces same slug as canonical path
test_dir="$TEST_ROOT/canon1"
mkdir -p "$test_dir/real-project"
ln -s "$test_dir/real-project" "$test_dir/sym-project"
real_slug=$(unset JARVIS_DIR; CLAUDE_PROJECT_DIR="$test_dir/real-project" HOME="$TEST_ROOT/canon1home" bash -c 'source '"$RESOLVE_DIR"'; echo "$JARVIS_DIR"')
sym_slug=$(unset JARVIS_DIR; CLAUDE_PROJECT_DIR="$test_dir/sym-project" HOME="$TEST_ROOT/canon1home" bash -c 'source '"$RESOLVE_DIR"'; echo "$JARVIS_DIR"')
assert_equals "Symlink and real path → same slug" "$sym_slug" "$real_slug"

# Test 2: Subdirectory of git repo walks up to toplevel
test_dir="$TEST_ROOT/canon2"
mkdir -p "$test_dir/repo/sub/deeper"
( cd "$test_dir/repo" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
top_slug=$(unset JARVIS_DIR; CLAUDE_PROJECT_DIR="$test_dir/repo" HOME="$TEST_ROOT/canon2home" bash -c 'source '"$RESOLVE_DIR"'; echo "$JARVIS_DIR"')
sub_slug=$(unset JARVIS_DIR; CLAUDE_PROJECT_DIR="$test_dir/repo/sub/deeper" HOME="$TEST_ROOT/canon2home" bash -c 'source '"$RESOLVE_DIR"'; echo "$JARVIS_DIR"')
assert_equals "Subdir of git repo → same slug as toplevel" "$sub_slug" "$top_slug"

# Test 3: Non-git, non-existent path stays as-is (no canonicalization possible)
slug=$(unset JARVIS_DIR; CLAUDE_PROJECT_DIR="/nonexistent/Path/Test" HOME="$TEST_ROOT/canon3home" bash -c 'source '"$RESOLVE_DIR"'; echo "$JARVIS_DIR"')
assert_contains "Non-existent path → falls back to slug of input" "$slug" "nonexistent-path-test"

# Test 4: Legacy slug fallback — pre-existing data dir at uncanonicalized slug
test_dir="$TEST_ROOT/canon4"
mkdir -p "$test_dir/real-project"
ln -s "$test_dir/real-project" "$test_dir/sym-project"
fake_home="$TEST_ROOT/canon4home"
# Seed a data dir using the legacy slug (uncanonicalized symlink path)
legacy_slug=$(echo "$test_dir/sym-project" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
mkdir -p "$fake_home/.jarvis/projects/$legacy_slug"
# Resolve from the symlink path — should pick the legacy dir, not the canonical one
resolved=$(unset JARVIS_DIR; CLAUDE_PROJECT_DIR="$test_dir/sym-project" HOME="$fake_home" bash -c 'source '"$RESOLVE_DIR"'; echo "$JARVIS_DIR"' 2>/dev/null)
assert_equals "Legacy slug dir exists → resolver uses it over canonical" "$resolved" "$fake_home/.jarvis/projects/$legacy_slug"

# Test 5: All 7 resolve-dir.sh copies are byte-identical
unique_hashes=$(md5sum "$SCRIPT_DIR/skills"/*/scripts/resolve-dir.sh | awk '{print $1}' | sort -u | wc -l)
assert_equals "All 7 resolve-dir.sh copies byte-identical" "$unique_hashes" "1"

# ============================================================
# Group 7c: finalize-reflection.sh
# ============================================================
group "finalize-reflection.sh"

FINALIZE="$SCRIPT_DIR/skills/jarvis-reflect/scripts/finalize-reflection.sh"

# Helper: write a valid journal entry that passes validation.
write_valid_journal() {
  local jdir="$1" filename="$2" summary="$3"
  cat > "$jdir/journal/$filename" << EOF
---
date: 2026-05-05
time: 12:00
tags: [test, finalize]
task_type: feature
---

# Reflection

## Task Summary
$summary

## Actions Taken
- Did stuff

## What Worked
- It worked

## What Didn't Work
- Nothing notable

## Lessons Learned
- Tested

## Memory Updates
None.

## Identity Impact
None.
EOF
}

# Test 1: Happy path — pending marker removed, commit created with extracted summary, summary printed
test_dir="$TEST_ROOT/fin1"
fake_home="$TEST_ROOT/fin1home"
mkdir -p "$fake_home"
unset JARVIS_DIR
HOME="$fake_home" CLAUDE_PROJECT_DIR="/fin1/proj" bash "$JARVIS_INIT" >/dev/null 2>&1
jdir="$fake_home/.jarvis/projects/fin1-proj"
touch "$jdir/.pending-fin1-session"
write_valid_journal "$jdir" "2026-05-05-12-00-aabbccdd.md" "Tested finalize happy path"
output=$(HOME="$fake_home" CLAUDE_PROJECT_DIR="/fin1/proj" bash "$FINALIZE" "$jdir/journal/2026-05-05-12-00-aabbccdd.md" 2>&1)
rc=$?
assert_exit_code "Happy path → exit 0" "$rc" 0
assert_contains "Happy path → FINALIZE_OK" "$output" "FINALIZE_OK"
assert_contains "Happy path → commit_summary extracted" "$output" "commit_summary=Tested finalize happy path"
assert_contains "Happy path → journal_entries=1" "$output" "journal_entries=1"
assert_contains "Happy path → evolution_due=false" "$output" "evolution_due=false"
assert_file_not_exists "Pending marker removed" "$jdir/.pending-fin1-session"
last_msg=$(cd "$jdir" && git log -1 --format=%s)
assert_contains "Commit message uses extracted summary" "$last_msg" "reflect: Tested finalize happy path"
last_files=$(cd "$jdir" && git log -1 --name-only --format=)
assert_not_contains "Pending marker NOT in last commit" "$last_files" ".pending-"

# Test 2: Validation failure — finalize exits non-zero, no commit
test_dir="$TEST_ROOT/fin2"
fake_home="$TEST_ROOT/fin2home"
mkdir -p "$fake_home"
unset JARVIS_DIR
HOME="$fake_home" CLAUDE_PROJECT_DIR="/fin2/proj" bash "$JARVIS_INIT" >/dev/null 2>&1
jdir="$fake_home/.jarvis/projects/fin2-proj"
# Bad journal: missing required sections
cat > "$jdir/journal/2026-05-05-13-00-baadbaad.md" << 'EOF'
no frontmatter

## Task Summary
broken
EOF
output=$(HOME="$fake_home" CLAUDE_PROJECT_DIR="/fin2/proj" bash "$FINALIZE" "$jdir/journal/2026-05-05-13-00-baadbaad.md" 2>&1)
rc=$?
assert_exit_code "Bad journal → finalize exits non-zero" "$rc" 1
assert_contains "Bad journal → 'validation failed' message" "$output" "validation failed"
last_msg=$(cd "$jdir" && git log -1 --format=%s)
assert_equals "Bad journal → no new commit (still on initial scaffold)" "$last_msg" "jarvis: initial scaffold"

# Test 3: 5 journals → evolution_due=true
test_dir="$TEST_ROOT/fin3"
fake_home="$TEST_ROOT/fin3home"
mkdir -p "$fake_home"
unset JARVIS_DIR
HOME="$fake_home" CLAUDE_PROJECT_DIR="/fin3/proj" bash "$JARVIS_INIT" >/dev/null 2>&1
jdir="$fake_home/.jarvis/projects/fin3-proj"
for i in 1 2 3 4 5; do
  write_valid_journal "$jdir" "2026-05-05-14-0${i}-deadbeef.md" "Batch $i"
done
output=$(HOME="$fake_home" CLAUDE_PROJECT_DIR="/fin3/proj" bash "$FINALIZE" "$jdir/journal/2026-05-05-14-05-deadbeef.md" 2>&1)
assert_contains "5 journals → evolution_due=true" "$output" "evolution_due=true"
assert_contains "5 journals → journal_entries=5" "$output" "journal_entries=5"

# Test 4: Consolidation warning when memory > 100 lines
test_dir="$TEST_ROOT/fin4"
fake_home="$TEST_ROOT/fin4home"
mkdir -p "$fake_home"
unset JARVIS_DIR
HOME="$fake_home" CLAUDE_PROJECT_DIR="/fin4/proj" bash "$JARVIS_INIT" >/dev/null 2>&1
jdir="$fake_home/.jarvis/projects/fin4-proj"
# Inflate preferences.md
{
  echo "# User Preferences"
  echo ""
  echo "## Consolidated"
  for i in $(seq 1 150); do echo "- Pref $i"; done
  echo "## Recent"
} > "$jdir/memories/preferences.md"
write_valid_journal "$jdir" "2026-05-05-15-00-cafef00d.md" "Trigger warn"
output=$(HOME="$fake_home" CLAUDE_PROJECT_DIR="/fin4/proj" bash "$FINALIZE" "$jdir/journal/2026-05-05-15-00-cafef00d.md" 2>&1)
assert_contains "Memory > 100 lines → consolidation_warn line" "$output" "consolidation_warn=preferences.md:"

# Test 5: finalize on unmigrated dir → migrate runs first, .gitignore created via migration
test_dir="$TEST_ROOT/fin5"
fake_home="$TEST_ROOT/fin5home"
mkdir -p "$fake_home"
unset JARVIS_DIR
HOME="$fake_home" CLAUDE_PROJECT_DIR="/fin5/proj" bash "$JARVIS_INIT" >/dev/null 2>&1
jdir="$fake_home/.jarvis/projects/fin5-proj"
# Roll the dir back to v0 to simulate a pre-migration state
rm -f "$jdir/.gitignore" "$jdir/.jarvis-data-version"
write_valid_journal "$jdir" "2026-05-05-16-00-feeddead.md" "Self-heal test"
HOME="$fake_home" CLAUDE_PROJECT_DIR="/fin5/proj" bash "$FINALIZE" "$jdir/journal/2026-05-05-16-00-feeddead.md" >/dev/null 2>&1
assert_file_exists "Migration ran during finalize → .gitignore exists" "$jdir/.gitignore"
gitignore_content=$(cat "$jdir/.gitignore")
assert_contains "Migration-recreated .gitignore has .pending-*" "$gitignore_content" ".pending-\*"
assert_equals "Stamp advanced to LATEST after finalize" "$(cat $jdir/.jarvis-data-version)" "$PLUGIN_LATEST"

# Test 6: JARVIS_SESSION_ID limits cleanup to that session's marker
test_dir="$TEST_ROOT/fin6"
fake_home="$TEST_ROOT/fin6home"
mkdir -p "$fake_home"
unset JARVIS_DIR
HOME="$fake_home" CLAUDE_PROJECT_DIR="/fin6/proj" bash "$JARVIS_INIT" >/dev/null 2>&1
jdir="$fake_home/.jarvis/projects/fin6-proj"
touch "$jdir/.pending-mine" "$jdir/.pending-other"
write_valid_journal "$jdir" "2026-05-05-17-00-12345678.md" "Targeted cleanup"
JARVIS_SESSION_ID=mine HOME="$fake_home" CLAUDE_PROJECT_DIR="/fin6/proj" bash "$FINALIZE" "$jdir/journal/2026-05-05-17-00-12345678.md" >/dev/null 2>&1
assert_file_not_exists "Mine marker removed" "$jdir/.pending-mine"
assert_file_exists "Other session's marker preserved" "$jdir/.pending-other"

# ============================================================
# Group 7d: jarvis-migrate runner
# ============================================================
group "jarvis-migrate runner"

# PLUGIN_LATEST is defined at the top of this file (top-level constant).

# Test 1: Up-to-date data dir (stamp == LATEST) → silent exit 0
test_dir="$TEST_ROOT/mig1"
scaffold_jarvis_dir "$test_dir"
echo "$PLUGIN_LATEST" > "$test_dir/.jarvis-data-version"
output=$(bash "$MIGRATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Up-to-date dir → exit 0" "$rc" 0
assert_equals "Up-to-date dir → silent (no output)" "$output" ""

# Test 2: Up-to-date dir, no stamp file (treated as 0) and a fake plugin with LATEST=0 → silent exit 0
test_dir="$TEST_ROOT/mig2"
fake_plugin="$TEST_ROOT/mig2_plugin"
scaffold_jarvis_dir "$test_dir"
mkdir -p "$fake_plugin/migrations"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrations/_lib.sh" "$fake_plugin/migrations/_lib.sh"
echo "0" > "$fake_plugin/migrations/LATEST"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrate.sh" "$fake_plugin/migrate.sh"
output=$(bash "$fake_plugin/migrate.sh" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Absent stamp + LATEST=0 → exit 0" "$rc" 0
assert_equals "Absent stamp + LATEST=0 → silent" "$output" ""

# Test 3: Missing data dir → exit 2
output=$(bash "$MIGRATE" "$TEST_ROOT/nonexistent-mig" 2>&1)
rc=$?
assert_exit_code "Missing data dir → exit 2" "$rc" 2
assert_contains "Missing data dir → 'data dir not found' on stderr" "$output" "data dir not found"

# Test 4: Stamp > LATEST (downgrade) → exit 3
test_dir="$TEST_ROOT/mig4"
scaffold_jarvis_dir "$test_dir"
echo "9" > "$test_dir/.jarvis-data-version"
output=$(bash "$MIGRATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Stamp > LATEST → exit 3" "$rc" 3
assert_contains "Stamp > LATEST → downgrade message" "$output" "plugin was downgraded"
# Stamp must NOT be modified by a downgrade refusal
stamp_after=$(cat "$test_dir/.jarvis-data-version")
assert_equals "Downgrade refusal does not touch stamp" "$stamp_after" "9"

# Test 5: Garbage stamp content → treated as 0 (uses fake plugin with LATEST=0 to assert silent no-op)
test_dir="$TEST_ROOT/mig5"
fake_plugin="$TEST_ROOT/mig5_plugin"
scaffold_jarvis_dir "$test_dir"
printf 'not-an-integer' > "$test_dir/.jarvis-data-version"
mkdir -p "$fake_plugin/migrations"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrations/_lib.sh" "$fake_plugin/migrations/_lib.sh"
echo "0" > "$fake_plugin/migrations/LATEST"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrate.sh" "$fake_plugin/migrate.sh"
output=$(bash "$fake_plugin/migrate.sh" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Garbage stamp → treated as 0, exit 0" "$rc" 0
assert_equals "Garbage stamp → silent" "$output" ""

# Test 6: One pending migration → runs it, advances stamp, prints changelog
test_dir="$TEST_ROOT/mig6"
fake_plugin="$TEST_ROOT/mig6_plugin"
scaffold_jarvis_dir "$test_dir"
mkdir -p "$fake_plugin/migrations"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrations/_lib.sh" "$fake_plugin/migrations/_lib.sh"
make_fake_migration "$fake_plugin/migrations" "001" "did the thing"
echo "1" > "$fake_plugin/migrations/LATEST"
fake_runner="$fake_plugin/migrate.sh"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrate.sh" "$fake_runner"
output=$(bash "$fake_runner" "$test_dir" 2>&1)
rc=$?
assert_exit_code "One pending migration → exit 0" "$rc" 0
assert_contains "Changelog header present" "$output" "migrated v0 → v1"
assert_contains "Migration line aggregated" "$output" "001-test: did the thing"
assert_equals "Stamp advanced to LATEST" "$(cat $test_dir/.jarvis-data-version)" "1"

# Test 7: Failing migration → exit 4, stamp NOT advanced
test_dir="$TEST_ROOT/mig7"
fake_plugin="$TEST_ROOT/mig7_plugin"
scaffold_jarvis_dir "$test_dir"
mkdir -p "$fake_plugin/migrations"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrations/_lib.sh" "$fake_plugin/migrations/_lib.sh"
make_fake_migration "$fake_plugin/migrations" "001" "should not appear" 1
echo "1" > "$fake_plugin/migrations/LATEST"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrate.sh" "$fake_plugin/migrate.sh"
output=$(bash "$fake_plugin/migrate.sh" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Failing migration → exit 4" "$rc" 4
assert_contains "Failing migration → name in stderr" "$output" "001-test"
assert_file_not_exists "Stamp NOT written on failure" "$test_dir/.jarvis-data-version"

# Test 8: Filename gap (LATEST=2 but only 001 present) → exit 5
test_dir="$TEST_ROOT/mig8"
fake_plugin="$TEST_ROOT/mig8_plugin"
scaffold_jarvis_dir "$test_dir"
mkdir -p "$fake_plugin/migrations"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrations/_lib.sh" "$fake_plugin/migrations/_lib.sh"
make_fake_migration "$fake_plugin/migrations" "001" "first"
echo "2" > "$fake_plugin/migrations/LATEST"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrate.sh" "$fake_plugin/migrate.sh"
output=$(bash "$fake_plugin/migrate.sh" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Filename gap → exit 5" "$rc" 5
assert_contains "Filename gap → packaging bug message" "$output" "packaging bug"

# Test 9: Two pending migrations → both run, in order
test_dir="$TEST_ROOT/mig9"
fake_plugin="$TEST_ROOT/mig9_plugin"
scaffold_jarvis_dir "$test_dir"
mkdir -p "$fake_plugin/migrations"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrations/_lib.sh" "$fake_plugin/migrations/_lib.sh"
make_fake_migration "$fake_plugin/migrations" "001" "did first"
make_fake_migration "$fake_plugin/migrations" "002" "did second"
echo "2" > "$fake_plugin/migrations/LATEST"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrate.sh" "$fake_plugin/migrate.sh"
output=$(bash "$fake_plugin/migrate.sh" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Two migrations → exit 0" "$rc" 0
assert_contains "First migration appears" "$output" "001-test: did first"
assert_contains "Second migration appears" "$output" "002-test: did second"
first_pos=$(echo "$output" | grep -n "001-test" | head -1 | cut -d: -f1)
second_pos=$(echo "$output" | grep -n "002-test" | head -1 | cut -d: -f1)
if [ "$first_pos" -lt "$second_pos" ]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  printf "  ${GREEN}PASS${RESET} Migrations run in filename order\n"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "  ${RED}FAIL${RESET} Migrations run in filename order (got 001 at line %s, 002 at line %s)\n" "$first_pos" "$second_pos"
fi
assert_equals "Stamp advanced to 2" "$(cat $test_dir/.jarvis-data-version)" "2"

# Test 10: Resume from CURRENT — already at v1, only 002 should run
test_dir="$TEST_ROOT/mig10"
fake_plugin="$TEST_ROOT/mig10_plugin"
scaffold_jarvis_dir "$test_dir"
echo "1" > "$test_dir/.jarvis-data-version"
mkdir -p "$fake_plugin/migrations"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrations/_lib.sh" "$fake_plugin/migrations/_lib.sh"
make_fake_migration "$fake_plugin/migrations" "001" "should be skipped"
make_fake_migration "$fake_plugin/migrations" "002" "second only"
echo "2" > "$fake_plugin/migrations/LATEST"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrate.sh" "$fake_plugin/migrate.sh"
output=$(bash "$fake_plugin/migrate.sh" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Resume → exit 0" "$rc" 0
assert_not_contains "001 not re-run" "$output" "should be skipped"
assert_contains "002 ran" "$output" "second only"
assert_equals "Stamp advanced to 2" "$(cat $test_dir/.jarvis-data-version)" "2"

# Test 11: Real migration 001 on a fresh data dir without .gitignore
test_dir="$TEST_ROOT/mig11"
mkdir -p "$test_dir/memories" "$test_dir/journal"
# No .gitignore, no stamp — simulate a pre-migration data dir
output=$(bash "$MIGRATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Real 001 → exit 0" "$rc" 0
assert_contains "Real 001 → changelog header" "$output" "migrated v0 → v1"
assert_contains "Real 001 → 'wrote .gitignore'" "$output" "wrote .gitignore"
assert_file_exists "Real 001 → .gitignore created" "$test_dir/.gitignore"
gitignore_content=$(cat "$test_dir/.gitignore")
assert_contains "Real 001 → .gitignore has .pending-*" "$gitignore_content" ".pending-\*"
assert_equals "Real 001 → stamp at 1" "$(cat $test_dir/.jarvis-data-version)" "1"

# Test 12: Re-run migration 001 — should be no-op (idempotent)
output=$(bash "$MIGRATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Re-run → exit 0" "$rc" 0
assert_equals "Re-run → silent no-op" "$output" ""

# Test 13: Migration 001 against a dir with a partial .gitignore (no .pending-*)
test_dir="$TEST_ROOT/mig13"
mkdir -p "$test_dir/memories" "$test_dir/journal"
echo "*.log" > "$test_dir/.gitignore"
output=$(bash "$MIGRATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Partial .gitignore → exit 0" "$rc" 0
assert_contains "Partial .gitignore → 'appended .pending-*'" "$output" "appended .pending-\*"
content=$(cat "$test_dir/.gitignore")
assert_contains "Partial .gitignore → still has *.log" "$content" "\*.log"
assert_contains "Partial .gitignore → now has .pending-*" "$content" ".pending-\*"

# Test 14: Partial-failure recovery — first run fails at #2, fix #2, re-run; expect #1 idempotent + #2 succeeds
test_dir="$TEST_ROOT/mig_recovery"
fake_plugin="$TEST_ROOT/mig_recovery_plugin"
scaffold_jarvis_dir "$test_dir"
mkdir -p "$fake_plugin/migrations"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrations/_lib.sh" "$fake_plugin/migrations/_lib.sh"
# Migration 001: idempotent counter (only writes once)
cat > "$fake_plugin/migrations/001-counter.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
JDIR="$1"
if [ ! -f "$JDIR/.counter" ]; then
  echo "1" > "$JDIR/.counter"
  log_change "wrote counter"
else
  log_change "no-op (counter present)"
fi
EOF
chmod +x "$fake_plugin/migrations/001-counter.sh"
# Migration 002: fails the first time
make_fake_migration "$fake_plugin/migrations" "002" "should not appear" 1
echo "2" > "$fake_plugin/migrations/LATEST"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrate.sh" "$fake_plugin/migrate.sh"
# First run: 001 succeeds, 002 fails
output=$(bash "$fake_plugin/migrate.sh" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Recovery: first run fails at 002" "$rc" 4
assert_file_exists "Recovery: 001 effect persisted" "$test_dir/.counter"
assert_file_not_exists "Recovery: stamp not advanced" "$test_dir/.jarvis-data-version"
# Fix 002: replace with a working version
make_fake_migration "$fake_plugin/migrations" "002" "now works" 0
# Second run: 001 should be no-op (idempotent), 002 should succeed, stamp advances to 2
output=$(bash "$fake_plugin/migrate.sh" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Recovery: second run succeeds" "$rc" 0
assert_contains "Recovery: 001 ran idempotent" "$output" "no-op (counter present)"
assert_contains "Recovery: 002 ran on retry" "$output" "now works"
assert_equals "Recovery: counter unchanged (idempotent)" "$(cat $test_dir/.counter)" "1"
assert_equals "Recovery: stamp at LATEST" "$(cat $test_dir/.jarvis-data-version)" "2"

# Test 15: Existing-user upgrade — .gitignore already current (from prior reliability pass)
test_dir="$TEST_ROOT/mig_upgrade"
mkdir -p "$test_dir/memories" "$test_dir/journal"
# Pre-existing .gitignore matching what the prior reliability pass wrote
cat > "$test_dir/.gitignore" << 'EOF'
# JaRVIS state
.pending-*

# OS / editor noise
.DS_Store
EOF
# No stamp — pre-migration-system data dir
output=$(bash "$MIGRATE" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Upgrade: exit 0" "$rc" 0
assert_contains "Upgrade: changelog header" "$output" "migrated v0 → v1"
assert_contains "Upgrade: 'no-op (.gitignore already current)'" "$output" "already current"
assert_equals "Upgrade: stamp at LATEST" "$(cat $test_dir/.jarvis-data-version)" "$PLUGIN_LATEST"
upgrade_gitignore=$(cat "$test_dir/.gitignore")
assert_contains "Upgrade: .gitignore preserved (.pending-*)" "$upgrade_gitignore" ".pending-\*"
assert_contains "Upgrade: .gitignore preserved (DS_Store)" "$upgrade_gitignore" ".DS_Store"

# Test 16: Migration with missing _lib.sh fails loudly
test_dir="$TEST_ROOT/mig_no_lib"
fake_plugin="$TEST_ROOT/mig_no_lib_plugin"
scaffold_jarvis_dir "$test_dir"
mkdir -p "$fake_plugin/migrations"
# Migration that sources a non-existent _lib.sh — deliberately don't copy _lib.sh
cat > "$fake_plugin/migrations/001-broken.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
log_change "should never get here"
EOF
chmod +x "$fake_plugin/migrations/001-broken.sh"
echo "1" > "$fake_plugin/migrations/LATEST"
cp "$SCRIPT_DIR/skills/jarvis-migrate/scripts/migrate.sh" "$fake_plugin/migrate.sh"
output=$(bash "$fake_plugin/migrate.sh" "$test_dir" 2>&1)
rc=$?
assert_exit_code "Missing _lib.sh → exit 4" "$rc" 4
assert_contains "Missing _lib.sh → migration name in stderr" "$output" "001-broken"

# Test 17: Stamp file edge cases — parser tolerates whitespace and rejects non-integer formats
# Each case sets a stamp value and asserts whether migrate runs to v1 (parsed-as-0) or no-ops (parsed-as-LATEST).
# (LATEST is currently 1, so "parsed as 1" is a no-op and "parsed as 0" runs migration 001.)

# 17a: Trailing newlines → parsed as 1, no-op
test_dir="$TEST_ROOT/mig_stamp_a"
mkdir -p "$test_dir/memories" "$test_dir/journal"
echo ".pending-*" > "$test_dir/.gitignore"
printf '1\n\n\n' > "$test_dir/.jarvis-data-version"
output=$(bash "$MIGRATE" "$test_dir" 2>&1)
assert_equals "Stamp '1\\n\\n\\n' → no-op" "$output" ""

# 17b: Zero-padded → parsed as 1, no-op
test_dir="$TEST_ROOT/mig_stamp_b"
mkdir -p "$test_dir/memories" "$test_dir/journal"
echo ".pending-*" > "$test_dir/.gitignore"
printf '01' > "$test_dir/.jarvis-data-version"
output=$(bash "$MIGRATE" "$test_dir" 2>&1)
assert_equals "Stamp '01' → parsed as 1, no-op" "$output" ""

# 17c: Surrounded whitespace → parsed as 1, no-op
test_dir="$TEST_ROOT/mig_stamp_c"
mkdir -p "$test_dir/memories" "$test_dir/journal"
echo ".pending-*" > "$test_dir/.gitignore"
printf '  1  \n' > "$test_dir/.jarvis-data-version"
output=$(bash "$MIGRATE" "$test_dir" 2>&1)
assert_equals "Stamp '  1  ' → parsed as 1, no-op" "$output" ""

# 17d: Negative → fails regex, treated as 0, runs migration
test_dir="$TEST_ROOT/mig_stamp_d"
mkdir -p "$test_dir/memories" "$test_dir/journal"
printf '%s' '-1' > "$test_dir/.jarvis-data-version"
output=$(bash "$MIGRATE" "$test_dir" 2>&1)
assert_contains "Stamp '-1' → treated as 0, runs migration" "$output" "migrated v0 → v1"

# 17e: Decimal → fails regex, treated as 0, runs migration
test_dir="$TEST_ROOT/mig_stamp_e"
mkdir -p "$test_dir/memories" "$test_dir/journal"
printf '%s' '1.5' > "$test_dir/.jarvis-data-version"
output=$(bash "$MIGRATE" "$test_dir" 2>&1)
assert_contains "Stamp '1.5' → treated as 0, runs migration" "$output" "migrated v0 → v1"

# ============================================================
# Group 8: jarvis-session-start-cursor.sh
# ============================================================
group "jarvis-session-start-cursor.sh"

# Test 1: Populated data dir → output is valid JSON with agent_message key
test_dir="$TEST_ROOT/cursor_ss1"
scaffold_jarvis_dir "$test_dir"
create_populated_identity "$test_dir"
add_consolidated_memory "$test_dir/memories/preferences.md" "- User likes dark mode"
output=$(echo '{"conversation_id": "cursor-123"}' | JARVIS_DIR="$test_dir" bash "$CURSOR_SESSION_START" 2>&1)
assert_contains "Populated dir → has agent_message key" "$output" '"agent_message"'

# Test 2: agent_message contains identity context (TestBot)
assert_contains "agent_message contains identity (TestBot)" "$output" "TestBot"

# Test 3: JARVIS_DISABLE=true → empty agent_message
output=$(echo '{"conversation_id": "cursor-123"}' | JARVIS_DISABLE=true JARVIS_DIR="$test_dir" bash "$CURSOR_SESSION_START" 2>&1)
assert_contains "JARVIS_DISABLE=true → has agent_message key" "$output" '"agent_message"'
assert_not_contains "JARVIS_DISABLE=true → no identity in output" "$output" "TestBot"

# Test 4: No data dir → output contains "not set up" in agent_message
test_dir="$TEST_ROOT/cursor_ss2"
mkdir -p "$test_dir"
output=$(echo '{"conversation_id": "cursor-456"}' | JARVIS_DIR="$test_dir/nonexistent" bash "$CURSOR_SESSION_START" 2>&1)
assert_contains "No data dir → 'not set up' message" "$output" "not set up"

# Test 5: Cursor wrapper propagates migration changelog into agent_message
test_dir="$TEST_ROOT/cursor_mig"
scaffold_jarvis_dir "$test_dir"
rm -f "$test_dir/.gitignore" "$test_dir/.jarvis-data-version"
output=$(echo '{"conversation_id": "cursor-mig"}' | JARVIS_DIR="$test_dir" bash "$CURSOR_SESSION_START" 2>&1)
assert_contains "Cursor: migration changelog in agent_message" "$output" "migrated v0 → v1"
assert_contains "Cursor: 001-add-gitignore in agent_message" "$output" "001-add-gitignore"
assert_file_exists "Cursor: migration ran .gitignore" "$test_dir/.gitignore"

# ============================================================
# Group 9: jarvis-stop-cursor.sh
# ============================================================
group "jarvis-stop-cursor.sh"

# Test 1: Aged pending marker → output has agent_message with blocking reason (rule 5 fallback)
test_dir="$TEST_ROOT/cursor_stop1"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-cursor-456"
touch -d '10 minutes ago' "$test_dir/.pending-cursor-456"
mkdir -p "$test_dir/empty-project"
output=$(echo '{"conversation_id": "cursor-456"}' | JARVIS_DIR="$test_dir" CLAUDE_PROJECT_DIR="$test_dir/empty-project" bash "$CURSOR_STOP" 2>&1)
assert_contains "Aged marker → has agent_message" "$output" '"agent_message"'
assert_contains "Aged marker → has reflect reminder" "$output" "reflect"

# Test 2: No pending marker → empty/silent JSON
test_dir="$TEST_ROOT/cursor_stop2"
scaffold_jarvis_dir "$test_dir"
output=$(echo '{"conversation_id": "cursor-789"}' | JARVIS_DIR="$test_dir" bash "$CURSOR_STOP" 2>&1)
assert_contains "No pending marker → has agent_message key" "$output" '"agent_message"'
assert_not_contains "No pending marker → no reflect reminder" "$output" "reflect"

# Test 3: JARVIS_DISABLE=true → empty JSON output
test_dir="$TEST_ROOT/cursor_stop3"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-cursor-disabled"
output=$(echo '{"conversation_id": "cursor-disabled"}' | JARVIS_DISABLE=true JARVIS_DIR="$test_dir" bash "$CURSOR_STOP" 2>&1)
assert_contains "JARVIS_DISABLE=true → has agent_message key" "$output" '"agent_message"'
assert_not_contains "JARVIS_DISABLE=true → no blocking" "$output" "reflect"

# ============================================================
# Group 10: jarvis-session-start-copilot.sh
# ============================================================
group "jarvis-session-start-copilot.sh"

# Test 1: Valid input → creates .pending-copilot-* marker file
test_dir="$TEST_ROOT/copilot_ss1"
scaffold_jarvis_dir "$test_dir"
output=$(echo '{"timestamp": 1710500000}' | JARVIS_DIR="$test_dir" bash "$COPILOT_SESSION_START" 2>&1)
assert_file_exists "Creates pending marker" "$test_dir/.pending-copilot-1710500000"

# Test 2: Output is always {}
assert_equals "Output is {}" "$(echo "$output" | tr -d '[:space:]')" "{}"

# Test 3: JARVIS_DISABLE=true → no marker created, output {}
test_dir="$TEST_ROOT/copilot_ss2"
scaffold_jarvis_dir "$test_dir"
output=$(echo '{"timestamp": 1710500001}' | JARVIS_DISABLE=true JARVIS_DIR="$test_dir" bash "$COPILOT_SESSION_START" 2>&1)
assert_file_not_exists "JARVIS_DISABLE=true → no marker" "$test_dir/.pending-copilot-1710500001"
assert_equals "JARVIS_DISABLE=true → output {}" "$(echo "$output" | tr -d '[:space:]')" "{}"

# Test 4: Missing timestamp → falls back to current epoch, still creates marker
test_dir="$TEST_ROOT/copilot_ss3"
scaffold_jarvis_dir "$test_dir"
output=$(echo '{}' | JARVIS_DIR="$test_dir" bash "$COPILOT_SESSION_START" 2>&1)
# Should create a .pending-copilot-<epoch> marker
marker_count=$(ls -1 "$test_dir"/.pending-copilot-* 2>/dev/null | wc -l)
if [[ "$marker_count" -ge 1 ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  printf "  ${GREEN}PASS${RESET} Missing timestamp → fallback marker created\n"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "  ${RED}FAIL${RESET} Missing timestamp → fallback marker created\n"
  printf "       no .pending-copilot-* marker found\n"
fi

# Test 5: Copilot wrapper runs migrations as a side effect (output is empty {})
test_dir="$TEST_ROOT/copilot_mig"
scaffold_jarvis_dir "$test_dir"
rm -f "$test_dir/.gitignore" "$test_dir/.jarvis-data-version"
output=$(echo '{"timestamp": 1000000}' | JARVIS_DIR="$test_dir" bash "$COPILOT_SESSION_START" 2>&1)
assert_equals "Copilot: output is {}" "$(echo "$output" | tr -d '[:space:]')" "{}"
assert_file_exists "Copilot: migration advanced stamp" "$test_dir/.jarvis-data-version"
assert_equals "Copilot: stamp at LATEST" "$(cat $test_dir/.jarvis-data-version)" "$PLUGIN_LATEST"
assert_file_exists "Copilot: migration created .gitignore" "$test_dir/.gitignore"

# ============================================================
# Group 11: jarvis-session-end-copilot.sh
# ============================================================
group "jarvis-session-end-copilot.sh"

# Test 1: Existing .pending-copilot-* markers → all cleaned up
test_dir="$TEST_ROOT/copilot_end1"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-copilot-111" "$test_dir/.pending-copilot-222" "$test_dir/.pending-copilot-333"
output=$(echo '{"timestamp": 999}' | JARVIS_DIR="$test_dir" bash "$COPILOT_SESSION_END" 2>&1)
marker_count=$(ls -1 "$test_dir"/.pending-copilot-* 2>/dev/null | wc -l)
assert_equals "All copilot markers cleaned up" "$marker_count" "0"

# Test 2: Output is always {}
assert_equals "Output is {}" "$(echo "$output" | tr -d '[:space:]')" "{}"

# Test 3: JARVIS_DISABLE=true → exit silently
test_dir="$TEST_ROOT/copilot_end2"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-copilot-444"
output=$(echo '{"timestamp": 999}' | JARVIS_DISABLE=true JARVIS_DIR="$test_dir" bash "$COPILOT_SESSION_END" 2>&1)
assert_equals "JARVIS_DISABLE=true → output {}" "$(echo "$output" | tr -d '[:space:]')" "{}"
# Note: markers may or may not be cleaned when disabled — the env var check exits early

# Test 4: .jarvis-disabled marker → exit silently
test_dir="$TEST_ROOT/copilot_end3"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-copilot-555" "$test_dir/.jarvis-disabled"
output=$(echo '{"timestamp": 999}' | JARVIS_DIR="$test_dir" bash "$COPILOT_SESSION_END" 2>&1)
assert_equals ".jarvis-disabled marker → output {}" "$(echo "$output" | tr -d '[:space:]')" "{}"

# ============================================================
# Group 12: JARVIS_DISABLE env var
# ============================================================
group "JARVIS_DISABLE env var"

# Test 1: session-start with JARVIS_DISABLE=true → minimal JSON, no identity context
test_dir="$TEST_ROOT/disable_env1"
scaffold_jarvis_dir "$test_dir"
create_populated_identity "$test_dir"
output=$(echo '{"session_id": "dis1"}' | JARVIS_DISABLE=true JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
assert_not_contains "JARVIS_DISABLE → no identity in session-start" "$output" "TestBot"

# Test 2: stop hook with JARVIS_DISABLE=true → no blocking
test_dir="$TEST_ROOT/disable_env2"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-dis2"
output=$(echo '{"session_id": "dis2"}' | JARVIS_DISABLE=true JARVIS_DIR="$test_dir" bash "$STOP_HOOK" 2>&1)
assert_not_contains "JARVIS_DISABLE → no blocking on stop" "$output" "block"

# Test 3: Markers NOT created when disabled
test_dir="$TEST_ROOT/disable_env3"
scaffold_jarvis_dir "$test_dir"
output=$(echo '{"session_id": "dis3", "source": "startup"}' | JARVIS_DISABLE=true JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
assert_file_not_exists "JARVIS_DISABLE → no pending marker created" "$test_dir/.pending-dis3"

# ============================================================
# Group 13: .jarvis-disabled marker file
# ============================================================
group ".jarvis-disabled marker file"

# Test 1: session-start with .jarvis-disabled → no identity context
test_dir="$TEST_ROOT/disable_marker1"
scaffold_jarvis_dir "$test_dir"
create_populated_identity "$test_dir"
touch "$test_dir/.jarvis-disabled"
output=$(echo '{"session_id": "mkr1"}' | JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)
assert_not_contains ".jarvis-disabled → no identity loaded" "$output" "TestBot"

# Test 2: stop hook with .jarvis-disabled → no blocking
test_dir="$TEST_ROOT/disable_marker2"
scaffold_jarvis_dir "$test_dir"
touch "$test_dir/.pending-mkr2" "$test_dir/.jarvis-disabled"
output=$(echo '{"session_id": "mkr2"}' | JARVIS_DIR="$test_dir" bash "$STOP_HOOK" 2>&1)
assert_not_contains ".jarvis-disabled → no blocking on stop" "$output" "block"

# ============================================================
# Group 14: Stale marker cleanup
# ============================================================
group "Stale marker cleanup"

# Test 1: Old markers (>24h) are cleaned up by session-start
test_dir="$TEST_ROOT/stale1"
scaffold_jarvis_dir "$test_dir"
# Create stale markers and set their mtime to 25 hours ago
touch "$test_dir/.pending-stale-old1" "$test_dir/.pending-stale-old2"
# Use touch -d to set time to 25 hours ago
stale_time=$(date -d '25 hours ago' '+%Y%m%d%H%M.%S' 2>/dev/null || date -v-25H '+%Y%m%d%H%M.%S' 2>/dev/null)
if [[ -n "$stale_time" ]]; then
  touch -t "${stale_time%.*}" "$test_dir/.pending-stale-old1" "$test_dir/.pending-stale-old2" 2>/dev/null || \
    touch -d '25 hours ago' "$test_dir/.pending-stale-old1" "$test_dir/.pending-stale-old2" 2>/dev/null || true
fi
# Create a fresh marker
touch "$test_dir/.pending-fresh"

# Run session-start to trigger cleanup
output=$(echo '{"session_id": "stale-test"}' | JARVIS_DIR="$test_dir" bash "$SESSION_START" 2>&1)

# Verify stale markers removed (only if we could set mtime)
if [[ -n "$stale_time" ]]; then
  assert_file_not_exists "Stale marker old1 cleaned up" "$test_dir/.pending-stale-old1"
  assert_file_not_exists "Stale marker old2 cleaned up" "$test_dir/.pending-stale-old2"
else
  printf "  ${YELLOW:-}SKIP${RESET} Stale marker cleanup (touch -t not available)\n"
fi

# Verify fresh marker is preserved
assert_file_exists "Fresh marker preserved" "$test_dir/.pending-fresh"

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
