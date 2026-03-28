# Claude Census — Design Spec

## Context

Claude Code 用户会安装大量扩展（skills、agents、plugins、MCP servers、rules 等），但缺乏可观测性——不知道哪些在被使用、使用频率如何、哪些是从未触发的"僵尸配置"。

Claude Census 是一个 Claude Code Plugin，通过 PostToolUse Hook 实时采集工具调用事件，并提供 `/census` 命令输出分析报告。

目标：开源到 GitHub，让所有 Claude Code 用户都能使用。

## Architecture

两个核心组件：

1. **PostToolUse Hook** — 实时采集 Skill/Agent/MCP/Command/PlanMode/LSP 的调用事件，写入 SQLite
2. **Command `/census`** — 查询 SQLite 并输出分析报告

### 项目结构

```
claude-census/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── hooks/
│   ├── hooks.json               # PostToolUse hook 配置
│   └── scripts/
│       └── log-event.sh         # 采集脚本
├── commands/
│   └── census.md                # /census 命令定义
├── scripts/
│   └── query.sh                 # SQL 查询辅助脚本
├── docs/
│   └── design.md                # 本文件
├── README.md
├── LICENSE                      # MIT
└── .gitignore
```

### 安装方式

与 claude-hud 等第三方 plugin 相同，通过 Claude Code 标准 marketplace 机制：

```json
// ~/.claude/settings.json
{
  "extraKnownMarketplaces": {
    "claude-census": {
      "source": {
        "source": "git",
        "url": "git@github.com:用户名/claude-census.git"
      },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "claude-census@claude-census": true
  }
}
```

Claude Code 会自动 clone 到 `~/.claude/plugins/cache/claude-census/` 下。

### 数据存储

- SQLite DB 路径：`~/.claude/claude-census/data/census.db`
- 放在 `~/.claude/` 下，不在 plugin cache 内，避免 plugin 更新时丢失数据
- DB 目录在首次写入时由 `log-event.sh` 自动创建
- 每条记录约 150 bytes，500 次/天 ≈ 27MB/年

## Component 1: PostToolUse Hook

### hooks/hooks.json

```json
{
  "description": "Track skill, agent, MCP, command, plan mode, and LSP usage",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Skill|Agent|mcp__.*|EnterPlanMode|ExitPlanMode|LSP",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/log-event.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

`matcher` 做预过滤，只匹配 6 类工具。其他工具（Read/Write/Bash 等）不会触发脚本，零开销。

### 采集脚本 log-event.sh

**输入：** stdin 接收 JSON，包含 `tool_name`、`tool_input`、`session_id`、`cwd` 等字段。环境变量 `$CLAUDE_PROJECT_DIR` 提供项目路径。

**分类逻辑：**

| tool_name | category | name 提取方式 |
|-----------|----------|---------------|
| `Skill` 且 `tool_input.skill` 含 `:` | `command` | `tool_input.skill`（如 `commit-commands:commit`） |
| `Skill` 且 `tool_input.skill` 不含 `:` | `skill` | `tool_input.skill`（如 `plan`） |
| `Agent` | `agent` | `tool_input.subagent_type` 或 `general-purpose` |
| `mcp__plugin_*` | `mcp` | 解析出 `server/tool`（如 `playwright/browser_navigate`） |
| `mcp__claude_ai_*` | `mcp` | 解析出 `server/tool`（如 `Gmail/gmail_search_messages`） |
| `EnterPlanMode` | `plan` | `enter` |
| `ExitPlanMode` | `plan` | `exit` |
| `LSP` | `lsp` | `tool_input.action` 或 `unknown` |

**JSON 解析兼容策略：**
1. 优先用 `jq`（~5ms）
2. fallback 到 `python3 -c`（~30ms）
3. 两者都没有 → `exit 0` 静默退出，不阻塞

**性能：** 整个脚本执行 < 10ms（jq 路径），零 token 消耗，PostToolUse 不阻塞用户交互。

### SQLite Schema

```sql
CREATE TABLE events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
  category TEXT NOT NULL,   -- 'skill', 'command', 'agent', 'mcp', 'plan', 'lsp'
  name TEXT NOT NULL,       -- e.g. 'plan', 'code-reviewer', 'playwright/browser_navigate'
  session_id TEXT,
  project_path TEXT
);

CREATE INDEX idx_events_ts ON events(ts);
CREATE INDEX idx_events_category ON events(category);
CREATE INDEX idx_events_name ON events(name);
CREATE INDEX idx_events_project ON events(project_path);

PRAGMA journal_mode=WAL;
```

WAL 模式确保并发写入安全（多个 Claude 窗口同时写入）。

## Component 2: /census Command

### 可追踪的 6 类工具

| 类别 | 怎么识别 | 能追踪 |
|------|----------|--------|
| Skills | `tool_name="Skill"`, 不含 `:` | ✅ |
| Commands | `tool_name="Skill"`, 含 `:` | ✅ |
| Agents | `tool_name="Agent"` | ✅ |
| MCP tools | `tool_name` 以 `mcp__` 开头 | ✅ |
| Plan Mode | `EnterPlanMode` / `ExitPlanMode` | ✅ |
| LSP | `tool_name="LSP"` | ✅ |

**不可追踪：**
- **Rules** — 被动加载到 context，无工具调用事件。报告中列出全部 rules 文件供手动审查。
- **Hooks** — 是观察者本身，不产生工具调用事件。

### 子命令

| 命令 | 说明 |
|------|------|
| `/census` | 完整报告：全局概览 + 各类别详情 + 僵尸摘要 |
| `/census zombies` | 僵尸深度分析，附 Claude 推断的"可能原因" |
| `/census trends` | 最近 30 天每日趋势，全局 + 各类别 |
| `/census projects` | 所有项目的使用对比 |
| `/census export` | 导出为 CSV |
| `/census reset` | 清空数据（需用户确认） |

### /census 默认报告格式

一个命令展示全貌 + 各科目钻取：

```
📊 Claude Census Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Period: 2026-03-01 ~ 2026-03-28 | Events: 1,247 | Sessions: 43

── Overview ─────────────────────────────
  skill     623  (49.9%)  24/83 installed  ████████████████████
  agent     312  (25.0%)   8/13 installed  ██████████
  mcp       201  (16.1%)  15/45 installed  ██████
  command    89  ( 7.1%)  12/20 installed  ███
  plan       18  ( 1.4%)                   █
  lsp         4  ( 0.3%)

── Skills (24 used / 83 installed, 28.9%) ──────
  /plan           142    /browse          98    /review         63
  /tdd             45    /ship            31    ...
  Never used: django-*, springboot-*, swift-*, nuxt4-*...

── Agents (8 used / 13 installed, 61.5%) ───────
  code-reviewer    87    planner          64    tdd-guide       52
  Never used: java-reviewer, java-build-resolver, e2e-runner

── MCP (15 used / 45 installed, 33.3%) ─────────
  playwright/*     76    context7/*       55    chrome-devtools/* 38
  Never used: Google_Calendar/*, Gmail/*

── Commands (12 used / 20 installed, 60.0%) ────
  commit           34    commit-push-pr   22    ...
```

Overview 是跨类别的全局占比，下面各 section 是**类别内部**的排行 + 覆盖率 + 僵尸摘要。

### 僵尸检测 — Inventory Sources

| 类别 | 安装清单来源 |
|------|-------------|
| Skills | `~/.claude/skills/*/SKILL.md` + plugin 内 skills |
| Agents | `~/.claude/agents/*.md` + plugin 内 agents |
| Commands | plugin 内 `commands/*.md` |
| MCP tools | 扫描 plugin 的 `.mcp.json` + deferred tools 列表中 `mcp__` 开头的 |
| Rules | `~/.claude/rules/**/*.md`（仅列出，无法追踪使用） |

**僵尸 = 安装清单 − 使用记录。**

`/census zombies` 会让 Claude 读取每个僵尸的 description/SKILL.md，推断从未使用的可能原因，例如：
- "该 skill 仅适用于 Django 项目，你当前没有 Django 项目"
- "该 agent 的触发条件是 Java 构建失败，可能从未遇到过"
- "该 MCP server 已连接但从未在对话中被需要"

## Implementation Steps

### Step 1: 项目初始化
- 创建目录结构
- 写 `.claude-plugin/plugin.json`、`.gitignore`、`LICENSE`（MIT）
- `git init`

### Step 2: Hook 采集脚本
- 写 `hooks/hooks.json`
- 写 `hooks/scripts/log-event.sh`（jq/python3 兼容、SQLite 初始化、分类逻辑）

### Step 3: /census 命令
- 写 `commands/census.md`（命令定义 + 查询模板 + 输出格式）
- 写 `scripts/query.sh`（封装 SQL 查询）

### Step 4: 安装 Plugin 到本地 Claude Code
- 在 `~/.claude/plugins/installed_plugins.json` 中注册
- 在 `~/.claude/settings.json` 的 `enabledPlugins` 中启用
- 开发期间用 symlink 方便迭代，正式发布后用户通过 `extraKnownMarketplaces` 安装

### Step 5: README
- 项目介绍、安装说明、使用方式、命令参考

### Step 6: Git 提交
- 初始提交，不推送远程

### Step 7: 测试验证
- 启动新 session，使用 skills/agents/MCP tools
- 运行 `/census` 验证采集和报告
- 验证各子命令

## Verification Checklist

1. **Hook 触发：** `sqlite3 ~/.claude/claude-census/data/census.db "SELECT * FROM events ORDER BY ts DESC LIMIT 10;"` 有新记录
2. **分类准确：** Skill/Agent/MCP/Command 各触发一次，检查 category 和 name 正确
3. **报告完整：** `/census` 输出包含 Overview + 各类别 section
4. **僵尸检测：** `/census zombies` 列出未使用项，不误报已使用项
5. **多项目隔离：** `/census projects` 正确区分不同项目
6. **性能：** hook 脚本执行 < 50ms
