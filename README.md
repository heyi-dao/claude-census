# Claude Census

Track and analyze your Claude Code tool usage. Discover which skills, agents, MCP tools, and commands are actually used — and which are zombie configs gathering dust.

## Features

- **Real-time tracking** — PostToolUse hook automatically logs every skill, agent, MCP tool, and command invocation
- **Zero token cost** — Hook runs as a shell script, no LLM calls
- **Usage dashboard** — `/census` shows a complete report with per-category breakdowns
- **Zombie detection** — Find installed-but-never-used extensions with AI-powered reasoning
- **Trend analysis** — Track usage patterns over time
- **Multi-project support** — Usage is tagged by project path and session

## What Gets Tracked

| Category | How It's Detected | Example |
|----------|-------------------|---------|
| Skills | `Skill` tool, name without `:` | `/plan`, `/browse`, `/review` |
| Commands | `Skill` tool, name with `:` | `commit-commands:commit` |
| Agents | `Agent` tool | `code-reviewer`, `planner` |
| MCP tools | `mcp__*` tool names | `playwright/browser_navigate` |
| Plan Mode | `EnterPlanMode`/`ExitPlanMode` | — |
| LSP | `LSP` tool | — |

**Not trackable:** Rules (passively loaded into context) and Hooks (the observer itself).

## Installation

Add to your `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "claude-census": {
      "source": {
        "source": "git",
        "url": "https://github.com/heyi-dao/claude-census.git"
      },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "claude-census@claude-census": true
  }
}
```

Then restart Claude Code. The plugin will be automatically downloaded and enabled.

## Usage

### Default Dashboard

```
/census
```

Shows a complete report: global overview + per-category breakdowns (skills, agents, MCP, commands) with usage counts, coverage percentages, and never-used items.

### Zombie Report

```
/census zombies
```

Deep analysis of installed-but-never-used extensions. For each zombie, Claude reads its description and suggests why it was never triggered and whether to keep or remove it.

### Trends

```
/census trends
```

Daily usage trends for the last 30 days, broken down by category. Includes week-over-week comparison.

### Projects

```
/census projects
```

Compare tool usage across different projects.

### Export

```
/census export
```

Export all raw data as CSV.

### Reset

```
/census reset
```

Clear all collected data (requires confirmation).

## How It Works

1. A **PostToolUse hook** fires after every matching tool call (`Skill|Agent|mcp__.*|EnterPlanMode|ExitPlanMode|LSP`)
2. The hook script (`log-event.sh`) classifies the tool call and inserts a row into a SQLite database
3. The `/census` command queries the database and formats the results

### Performance

- Hook execution: **< 10ms** (uses `jq` when available, falls back to `python3`)
- Zero token cost (pure shell script, no LLM involvement)
- SQLite with WAL mode for safe concurrent writes from multiple sessions
- Database size: ~150 bytes per event, ~27MB per year at 500 events/day

### Data Storage

The SQLite database is stored at `~/.claude/claude-census/data/census.db`, separate from the plugin installation directory. This ensures your data survives plugin updates.

## Dependencies

- `sqlite3` (pre-installed on macOS and most Linux distributions)
- `jq` (recommended, for faster JSON parsing) or `python3` (fallback)

## License

MIT
