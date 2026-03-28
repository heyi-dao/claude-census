#!/usr/bin/env bash
# Tests for MCP tool name parsing in log-event.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/scripts/log-event.sh"
TEST_DB="/tmp/claude-census-mcp-test-$$.db"
PASS=0
FAIL=0

cleanup() { rm -f "$TEST_DB" "$TEST_DB-wal" "$TEST_DB-shm"; }
trap cleanup EXIT

assert_last_name() {
  local expected="$1" label="$2"
  local actual
  actual=$(sqlite3 "$TEST_DB" "SELECT name FROM events ORDER BY id DESC LIMIT 1;" 2>/dev/null)
  if [ "$actual" = "$expected" ]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label: expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

run_hook() {
  HOME_BACKUP="$HOME"
  export HOME="/tmp/claude-census-mcp-home-$$"
  mkdir -p "$HOME/.claude/claude-census/data"
  ln -sf "$TEST_DB" "$HOME/.claude/claude-census/data/census.db"
  printf '%s' "$1" | bash "$HOOK" 2>/dev/null || true
  export HOME="$HOME_BACKUP"
}

echo "=== MCP Name Parsing Tests ==="

# Test: plugin with duplicate name (playwright_playwright → playwright)
run_hook '{"tool_name":"mcp__plugin_playwright_playwright__browser_navigate","session_id":"s1","tool_input":{}}'
assert_last_name "playwright/browser_navigate" "plugin_playwright_playwright → playwright/browser_navigate"

# Test: plugin with different pkg and class
run_hook '{"tool_name":"mcp__plugin_chrome-devtools-mcp_chrome-devtools__click","session_id":"s1","tool_input":{}}'
assert_last_name "chrome-devtools-mcp_chrome-devtools/click" "Different pkg_class preserved"

# Test: claude_ai prefix
run_hook '{"tool_name":"mcp__claude_ai_Gmail__gmail_search_messages","session_id":"s1","tool_input":{}}'
assert_last_name "Gmail/gmail_search_messages" "claude_ai_Gmail → Gmail/gmail_search_messages"

# Test: claude_ai with multi-word server name
run_hook '{"tool_name":"mcp__claude_ai_Google_Calendar__gcal_list_events","session_id":"s1","tool_input":{}}'
assert_last_name "Google_Calendar/gcal_list_events" "claude_ai_Google_Calendar → Google_Calendar/gcal_list_events"

# Test: unknown mcp format (no plugin_ or claude_ai_ prefix)
run_hook '{"tool_name":"mcp__custom_server__do_thing","session_id":"s1","tool_input":{}}'
assert_last_name "custom_server__do_thing" "Unknown MCP format → raw rest"

# Test: plugin with context7 duplicate
run_hook '{"tool_name":"mcp__plugin_context7_context7__query-docs","session_id":"s1","tool_input":{}}'
assert_last_name "context7/query-docs" "plugin_context7_context7 → context7/query-docs"

# Cleanup
rm -rf "/tmp/claude-census-mcp-home-$$"

echo ""
echo "MCP Parsing: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
