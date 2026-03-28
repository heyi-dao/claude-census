#!/usr/bin/env bash
# Tests for log-event.sh — tool classification logic
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/scripts/log-event.sh"
TEST_DB="/tmp/claude-census-test-$$.db"
PASS=0
FAIL=0

cleanup() { rm -f "$TEST_DB" "$TEST_DB-wal" "$TEST_DB-shm"; }
trap cleanup EXIT

assert_last_event() {
  local expected_cat="$1" expected_name="$2" label="$3"
  local row
  row=$(sqlite3 "$TEST_DB" "SELECT category, name FROM events ORDER BY id DESC LIMIT 1;" 2>/dev/null)
  local expected="${expected_cat}|${expected_name}"
  if [ "$row" = "$expected" ]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label: expected '$expected', got '$row'"
    FAIL=$((FAIL + 1))
  fi
}

run_hook() {
  # Override DB path via HOME redirection
  local input="$1"
  HOME_BACKUP="$HOME"
  export HOME="/tmp/claude-census-test-home-$$"
  mkdir -p "$HOME/.claude/claude-census/data"
  # Symlink DB so hook writes to our test DB
  ln -sf "$TEST_DB" "$HOME/.claude/claude-census/data/census.db"
  printf '%s' "$input" | bash "$HOOK" 2>/dev/null || true
  export HOME="$HOME_BACKUP"
}

echo "=== Tool Classification Tests ==="

# Test: Skill (no colon → skill category)
run_hook '{"tool_name":"Skill","session_id":"s1","tool_input":{"skill":"commit"}}'
assert_last_event "skill" "commit" "Skill without colon → skill"

# Test: Command (with colon → command category)
run_hook '{"tool_name":"Skill","session_id":"s1","tool_input":{"skill":"census:census"}}'
assert_last_event "command" "census:census" "Skill with colon → command"

# Test: Agent with subagent_type
run_hook '{"tool_name":"Agent","session_id":"s1","tool_input":{"subagent_type":"code-reviewer"}}'
assert_last_event "agent" "code-reviewer" "Agent with subagent_type"

# Test: Agent without subagent_type → general-purpose
run_hook '{"tool_name":"Agent","session_id":"s1","tool_input":{}}'
assert_last_event "agent" "general-purpose" "Agent without subagent_type → general-purpose"

# Test: EnterPlanMode
run_hook '{"tool_name":"EnterPlanMode","session_id":"s1","tool_input":{}}'
assert_last_event "plan" "enter" "EnterPlanMode → plan/enter"

# Test: ExitPlanMode
run_hook '{"tool_name":"ExitPlanMode","session_id":"s1","tool_input":{}}'
assert_last_event "plan" "exit" "ExitPlanMode → plan/exit"

# Test: LSP
run_hook '{"tool_name":"LSP","session_id":"s1","tool_input":{"action":"hover"}}'
assert_last_event "lsp" "hover" "LSP with action"

# Test: Empty input → no event (should not crash)
event_count_before=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM events;" 2>/dev/null || echo "0")
run_hook ''
event_count_after=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM events;" 2>/dev/null || echo "0")
if [ "$event_count_before" = "$event_count_after" ]; then
  echo "  ✓ Empty input → no event"
  PASS=$((PASS + 1))
else
  echo "  ✗ Empty input → should not create event"
  FAIL=$((FAIL + 1))
fi

# Cleanup temp home
rm -rf "/tmp/claude-census-test-home-$$"

echo ""
echo "Classification: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
