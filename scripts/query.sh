#!/usr/bin/env bash
# Claude Census — Query helper script
# Provides common SQL queries for the /census command.
# Usage: bash query.sh <command> [args...]
set -euo pipefail

DB="$HOME/.claude/claude-census/data/census.db"

if [ ! -f "$DB" ]; then
  echo "ERROR: No census database found at $DB"
  echo "The PostToolUse hook has not recorded any events yet."
  echo "Use some skills, agents, or MCP tools first, then try again."
  exit 1
fi

cmd="${1:-summary}"
shift 2>/dev/null || true

# --- Input validation helpers ---
validate_int() {
  local val="$1" name="$2"
  if ! [[ "$val" =~ ^[0-9]+$ ]]; then
    echo "ERROR: $name must be a positive integer, got '$val'" >&2
    exit 1
  fi
}

validate_category() {
  local val="$1"
  case "$val" in
    skill|agent|mcp|command|plan|lsp|other) ;;
    *)
      echo "ERROR: invalid category '$val'. Must be one of: skill, agent, mcp, command, plan, lsp, other" >&2
      exit 1
      ;;
  esac
}

case "$cmd" in
  summary)
    sqlite3 -header -column "$DB" "
      SELECT
        COUNT(*) as total_events,
        COUNT(DISTINCT name) as unique_tools,
        COUNT(DISTINCT session_id) as sessions,
        COUNT(DISTINCT project_path) as projects,
        MIN(ts) as first_event,
        MAX(ts) as last_event
      FROM events;
    "
    ;;

  overview)
    sqlite3 -header -column "$DB" "
      SELECT
        category,
        COUNT(*) as calls,
        COUNT(DISTINCT name) as unique_tools,
        ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM events), 1) as pct
      FROM events
      GROUP BY category
      ORDER BY calls DESC;
    "
    ;;

  top)
    limit="${1:-15}"
    validate_int "$limit" "limit"
    sqlite3 -header -column "$DB" "
      SELECT category, name, COUNT(*) as calls
      FROM events
      GROUP BY category, name
      ORDER BY calls DESC
      LIMIT $limit;
    "
    ;;

  top-by-category)
    cat_filter="${1:-}"
    limit="${2:-15}"
    if [ -n "$cat_filter" ]; then
      validate_category "$cat_filter"
      validate_int "$limit" "limit"
      sqlite3 -header -column "$DB" "
        SELECT name, COUNT(*) as calls
        FROM events
        WHERE category = '$cat_filter'
        GROUP BY name
        ORDER BY calls DESC
        LIMIT $limit;
      "
    else
      echo "Usage: query.sh top-by-category <category> [limit]"
      exit 1
    fi
    ;;

  used-names)
    cat_filter="${1:-}"
    if [ -n "$cat_filter" ]; then
      validate_category "$cat_filter"
      sqlite3 "$DB" "
        SELECT DISTINCT name FROM events
        WHERE category = '$cat_filter'
        ORDER BY name;
      "
    else
      sqlite3 "$DB" "
        SELECT DISTINCT category || ':' || name FROM events
        ORDER BY 1;
      "
    fi
    ;;

  trends)
    days="${1:-30}"
    validate_int "$days" "days"
    sqlite3 -header -column "$DB" "
      SELECT DATE(ts) as day, COUNT(*) as events
      FROM events
      WHERE ts >= DATE('now', '-${days} days')
      GROUP BY day
      ORDER BY day DESC;
    "
    ;;

  trends-by-category)
    days="${1:-30}"
    validate_int "$days" "days"
    sqlite3 -header -column "$DB" "
      SELECT DATE(ts) as day, category, COUNT(*) as events
      FROM events
      WHERE ts >= DATE('now', '-${days} days')
      GROUP BY day, category
      ORDER BY day DESC, events DESC;
    "
    ;;

  projects)
    sqlite3 -header -column "$DB" "
      SELECT
        project_path,
        COUNT(*) as events,
        COUNT(DISTINCT name) as unique_tools,
        COUNT(DISTINCT session_id) as sessions,
        MIN(ts) as first_event,
        MAX(ts) as last_event
      FROM events
      WHERE project_path != ''
      GROUP BY project_path
      ORDER BY events DESC;
    "
    ;;

  export)
    sqlite3 -header -csv "$DB" "
      SELECT ts, category, name, session_id, project_path
      FROM events
      ORDER BY ts;
    "
    ;;

  count)
    sqlite3 "$DB" "SELECT COUNT(*) FROM events;"
    ;;

  reset)
    sqlite3 "$DB" "DELETE FROM events; VACUUM;"
    echo "All census data has been cleared."
    ;;

  *)
    echo "Unknown command: $cmd"
    echo "Available: summary, overview, top, top-by-category, used-names, trends, trends-by-category, projects, export, count, reset"
    exit 1
    ;;
esac
