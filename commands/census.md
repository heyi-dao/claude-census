---
description: Show Claude Code tool usage analytics — track skills, agents, MCP tools, commands, and detect zombie configs
argument-hint: "[zombies|trends|projects|export|reset]"
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
---

# /census — Claude Code Usage Analytics

You are the Claude Census reporting engine. Query the usage database and present results as formatted CLI reports.

## Setup

- **Database:** `~/.claude/claude-census/data/census.db`
- **Query helper:** `${CLAUDE_PLUGIN_ROOT}/scripts/query.sh`

First, check if the database exists:

```bash
if [ ! -f "$HOME/.claude/claude-census/data/census.db" ]; then
  echo "NO_DB"
else
  echo "DB_OK"
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" count
fi
```

If `NO_DB`: tell the user the hook hasn't collected data yet. They need to restart Claude Code and use some tools first.

If count is 0: same message.

## Commands

Parse the user's argument to determine which report to run:

- **No argument** or empty → Run the **Default Dashboard**
- **`zombies`** → Run the **Zombie Report**
- **`trends`** → Run the **Trends Report**
- **`projects`** → Run the **Projects Report**
- **`export`** → Run the **Export**
- **`reset`** → Run the **Reset** (ask for confirmation first!)

## Default Dashboard

Run these queries via the query helper:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" summary
bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" overview
bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" top 15
```

Then gather the installed inventory to compute coverage:

```bash
# Installed skills (custom + gstack)
find ~/.claude/skills -maxdepth 2 -name "SKILL.md" 2>/dev/null | wc -l

# Installed agents
ls ~/.claude/agents/*.md 2>/dev/null | wc -l

# Plugin skills — scan all plugin cache directories
find ~/.claude/plugins/cache -path "*/skills/*/SKILL.md" 2>/dev/null | wc -l

# Plugin commands — scan all plugin cache directories
find ~/.claude/plugins/cache -path "*/commands/*.md" 2>/dev/null | wc -l
```

Also get used names per category:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" used-names skill
bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" used-names command
bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" used-names agent
bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" used-names mcp
```

**Format the output as:**

```
📊 Claude Census Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Period: <first_event> ~ <last_event> | Events: <total> | Sessions: <sessions>

── Overview ──────────────────────────────────────────
  <category>  <calls>  (<pct>%)  <used>/<installed> installed  <bar>
  ...

── Skills (<used> used / <installed> installed, <coverage>%) ──
  <name>  <calls>    <name>  <calls>    <name>  <calls>
  ...
  Never used: <list of never-used skills>

── Agents (<used> used / <installed> installed, <coverage>%) ──
  <name>  <calls>    <name>  <calls>
  Never used: <list>

── MCP (<used> used / <total> tracked, <coverage>%) ──
  <name>  <calls>    <name>  <calls>
  Never used: <list or "no MCP tools tracked yet">

── Commands (<used> used / <installed> installed, <coverage>%) ──
  <name>  <calls>    <name>  <calls>
  Never used: <list>
```

For the bar chart, use block characters (█). Scale the longest bar to 20 characters, others proportional.

For "Never used" lists: cross-reference installed inventory against used-names. Group by prefix/theme when possible (e.g., "django-*", "springboot-*").

## Zombie Report (`/census zombies`)

Run the same inventory scan as the Default Dashboard, but with deeper analysis.

For each zombie (installed but never used):

1. Read its SKILL.md or agent .md file to get the description
2. Analyze WHY it was never used. Common reasons:
   - Language/framework mismatch (e.g., Django skill but no Python projects)
   - Trigger condition never met (e.g., build-error-resolver only triggers on build failures)
   - Overlapping functionality with a more popular tool
   - Niche use case that hasn't come up
3. Provide a recommendation: keep, remove, or investigate

**Format:**

```
🔍 Zombie Report — Installed but Never Used
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

── Skills (N never used) ──────────────────────────────
  django-security
    Description: Django security best practices...
    Likely reason: No Django projects detected in usage history
    Recommendation: Remove if not planning Django work

  springboot-tdd
    Description: Test-driven development for Spring Boot...
    Likely reason: No Spring Boot projects detected
    Recommendation: Remove if not planning Java/Spring work
  ...

── Agents (N never used) ──────────────────────────────
  ...

── MCP Tools (N never used) ───────────────────────────
  ...

── Rules (cannot track — listed for manual review) ────
  ~/.claude/rules/java/*.md (5 files)
  ~/.claude/rules/swift/*.md (5 files)
  ...
```

## Trends Report (`/census trends`)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" trends 30
bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" trends-by-category 30
```

**Format:**

```
📈 Usage Trends (Last 30 Days)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

── Daily Total ────────────────────────────────────────
  2026-03-28  42  ████████████████████
  2026-03-27  38  ██████████████████
  2026-03-26  15  ███████
  ...

── By Category (Last 30 Days) ─────────────────────────
  Date        skill  agent  mcp  command  plan  lsp
  2026-03-28     20     12    6       3     1    0
  2026-03-27     18     10    5       4     1    0
  ...

── Week over Week ─────────────────────────────────────
  This week: <N> events (<+/-X%> vs last week)
  Most active day: <day> (<N> events)
  Most used this week: <tool name> (<N> calls)
```

## Projects Report (`/census projects`)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" projects
```

**Format:**

```
📁 Usage by Project
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Project                    Events  Tools  Sessions  Period
  /Users/.../my-app             523     18        12  03-01 ~ 03-28
  /Users/.../another-project    312     11         8  03-05 ~ 03-27
  ...
```

Shorten project paths for readability (show last 2-3 path components).

## Export (`/census export`)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" export
```

Output the raw CSV and tell the user they can redirect it: `/census export > census-data.csv`

Actually, since this runs in Claude, save it to a file:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" export > /tmp/claude-census-export.csv
echo "Exported to /tmp/claude-census-export.csv"
wc -l /tmp/claude-census-export.csv
```

## Reset (`/census reset`)

**IMPORTANT:** Ask the user for explicit confirmation before running reset. Say:

> "This will permanently delete all census data (<N> events). Are you sure? Type 'yes' to confirm."

Only run after confirmation:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" reset
```

## Style Guide

- Use the exact formatting shown above (Unicode box-drawing, aligned columns)
- Use Chinese for any explanatory text (user preference)
- Keep reports concise — show top items inline, don't dump raw SQL output
- For bar charts, use █ characters, max width 20 chars
- Group "never used" items by theme/prefix when possible
- Always show coverage percentage (used/installed)
