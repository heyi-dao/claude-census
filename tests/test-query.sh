#!/usr/bin/env bash
# Tests for query.sh — input validation and subcommands
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUERY="$SCRIPT_DIR/../scripts/query.sh"
TEST_DB="/tmp/claude-census-query-test-$$.db"
PASS=0
FAIL=0

cleanup() { rm -f "$TEST_DB" "$TEST_DB-wal" "$TEST_DB-shm"; }
trap cleanup EXIT

# Setup test DB with sample data
sqlite3 "$TEST_DB" <<'SQL'
CREATE TABLE events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  category TEXT NOT NULL,
  name TEXT NOT NULL,
  session_id TEXT,
  project_path TEXT
);
INSERT INTO events (category, name, session_id, project_path) VALUES
  ('skill', 'commit', 's1', '/project/a'),
  ('skill', 'commit', 's1', '/project/a'),
  ('skill', 'review', 's1', '/project/a'),
  ('agent', 'code-reviewer', 's1', '/project/a'),
  ('mcp', 'playwright/click', 's2', '/project/b'),
  ('command', 'census:census', 's2', '/project/b'),
  ('plan', 'enter', 's2', '/project/b'),
  ('lsp', 'hover', 's2', '/project/b');
SQL

# Override HOME so query.sh finds our test DB
HOME_BACKUP="$HOME"
export HOME="/tmp/claude-census-query-home-$$"
mkdir -p "$HOME/.claude/claude-census/data"
ln -sf "$TEST_DB" "$HOME/.claude/claude-census/data/census.db"

assert_ok() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    FAIL=$((FAIL + 1))
  fi
}

assert_fail() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  ✗ $label (should have failed)"
    FAIL=$((FAIL + 1))
  else
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  fi
}

assert_contains() {
  local label="$1" expected="$2"
  shift 2
  local output
  output=$("$@" 2>&1) || true
  if echo "$output" | grep -q "$expected"; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label: expected to contain '$expected'"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Subcommand Tests ==="

assert_ok "summary" bash "$QUERY" summary
assert_ok "overview" bash "$QUERY" overview
assert_ok "top" bash "$QUERY" top
assert_ok "top with limit" bash "$QUERY" top 5
assert_ok "top-by-category skill" bash "$QUERY" top-by-category skill
assert_ok "used-names" bash "$QUERY" used-names
assert_ok "used-names skill" bash "$QUERY" used-names skill
assert_ok "trends" bash "$QUERY" trends
assert_ok "trends 7" bash "$QUERY" trends 7
assert_ok "trends-by-category" bash "$QUERY" trends-by-category
assert_ok "projects" bash "$QUERY" projects
assert_ok "export" bash "$QUERY" export
assert_ok "count" bash "$QUERY" count

echo ""
echo "=== Input Validation Tests ==="

# Integer validation
assert_fail "top with non-numeric limit" bash "$QUERY" top "abc"
assert_fail "top with SQL injection in limit" bash "$QUERY" top "1; DROP TABLE events;"
assert_fail "trends with non-numeric days" bash "$QUERY" trends "abc"
assert_fail "trends with negative-looking input" bash "$QUERY" trends "-1"
assert_fail "trends-by-category with injection" bash "$QUERY" trends-by-category "1; DROP TABLE events"

# Category whitelist validation
assert_fail "top-by-category with invalid category" bash "$QUERY" top-by-category "invalid"
assert_fail "top-by-category with SQL injection" bash "$QUERY" top-by-category "skill' OR '1'='1"
assert_fail "used-names with invalid category" bash "$QUERY" used-names "'; DROP TABLE events;--"

# Valid categories should all work
for cat in skill agent mcp command plan lsp other; do
  assert_ok "top-by-category $cat" bash "$QUERY" top-by-category "$cat"
done

echo ""
echo "=== Data Integrity Test ==="

# Verify count
count=$(bash "$QUERY" count)
if [ "$count" = "8" ]; then
  echo "  ✓ Event count is 8"
  PASS=$((PASS + 1))
else
  echo "  ✗ Event count: expected 8, got $count"
  FAIL=$((FAIL + 1))
fi

# Cleanup
rm -rf "$HOME"
export HOME="$HOME_BACKUP" 2>/dev/null || true

echo ""
echo "Query: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
