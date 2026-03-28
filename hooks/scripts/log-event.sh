#!/usr/bin/env bash
# Claude Census — PostToolUse hook
# Logs skill, agent, MCP, command, plan mode, and LSP usage to SQLite.
# Zero token cost. Receives JSON on stdin from Claude Code.
set -euo pipefail

DB="$HOME/.claude/claude-census/data/census.db"

# Read stdin
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

# --- JSON parsing: prefer jq, fallback to python3 ---
if command -v jq >/dev/null 2>&1; then
  parse_json() {
    printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null || echo ""
  }
  TOOL_NAME=$(parse_json '.tool_name // ""')
  SESSION_ID=$(parse_json '.session_id // ""')
  SKILL_NAME=$(parse_json '.tool_input.skill // ""')
  AGENT_TYPE=$(parse_json '.tool_input.subagent_type // ""')
  LSP_ACTION=$(parse_json '.tool_input.action // ""')
elif command -v python3 >/dev/null 2>&1; then
  read -r TOOL_NAME SESSION_ID SKILL_NAME AGENT_TYPE LSP_ACTION <<< $(printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    d = json.loads(sys.stdin.read())
    ti = d.get("tool_input", {}) or {}
    print(
        d.get("tool_name", ""),
        d.get("session_id", ""),
        ti.get("skill", ""),
        ti.get("subagent_type", ""),
        ti.get("action", "")
    )
except Exception:
    print("" * 5)
' 2>/dev/null || echo "")
else
  # No JSON parser available, exit silently
  exit 0
fi

[ -z "$TOOL_NAME" ] && exit 0

# --- Classify tool type and extract display name ---
CATEGORY=""
NAME=""

case "$TOOL_NAME" in
  Skill)
    if [ -n "$SKILL_NAME" ]; then
      case "$SKILL_NAME" in
        *:*)
          CATEGORY="command"
          NAME="$SKILL_NAME"
          ;;
        *)
          CATEGORY="skill"
          NAME="$SKILL_NAME"
          ;;
      esac
    else
      exit 0
    fi
    ;;
  Agent)
    CATEGORY="agent"
    NAME="${AGENT_TYPE:-general-purpose}"
    ;;
  EnterPlanMode)
    CATEGORY="plan"
    NAME="enter"
    ;;
  ExitPlanMode)
    CATEGORY="plan"
    NAME="exit"
    ;;
  LSP)
    CATEGORY="lsp"
    NAME="${LSP_ACTION:-unknown}"
    ;;
  mcp__*)
    CATEGORY="mcp"
    # Parse MCP tool name: mcp__plugin_X_Y__action or mcp__claude_ai_X__action
    # Remove "mcp__" prefix, then split on "__" to get server and tool
    _rest="${TOOL_NAME#mcp__}"
    case "$_rest" in
      plugin_*)
        # e.g. plugin_playwright_playwright__browser_navigate
        _server="${_rest%%__*}"
        _server="${_server#plugin_}"
        _tool="${_rest#*__}"
        NAME="${_server}/${_tool}"
        ;;
      claude_ai_*)
        # e.g. claude_ai_Gmail__gmail_search_messages
        _server="${_rest%%__*}"
        _server="${_server#claude_ai_}"
        _tool="${_rest#*__}"
        NAME="${_server}/${_tool}"
        ;;
      *)
        NAME="$_rest"
        ;;
    esac
    ;;
  *)
    # Unknown tool that matched the hook regex — log as "other"
    CATEGORY="other"
    NAME="$TOOL_NAME"
    ;;
esac

[ -z "$CATEGORY" ] && exit 0

PROJECT_PATH="${CLAUDE_PROJECT_DIR:-}"

# --- Initialize DB if needed ---
if [ ! -f "$DB" ]; then
  mkdir -p "$(dirname "$DB")"
  sqlite3 "$DB" <<'SQL'
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  category TEXT NOT NULL,
  name TEXT NOT NULL,
  session_id TEXT,
  project_path TEXT
);
CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts);
CREATE INDEX IF NOT EXISTS idx_events_category ON events(category);
CREATE INDEX IF NOT EXISTS idx_events_name ON events(name);
CREATE INDEX IF NOT EXISTS idx_events_project ON events(project_path);
PRAGMA journal_mode=WAL;
SQL
fi

# --- INSERT using parameterized-style escaping ---
# Escape single quotes for SQL safety
_esc() { printf '%s' "$1" | sed "s/'/''/g"; }

sqlite3 "$DB" "INSERT INTO events (category, name, session_id, project_path) VALUES ('$(_esc "$CATEGORY")','$(_esc "$NAME")','$(_esc "$SESSION_ID")','$(_esc "$PROJECT_PATH")');"

exit 0
