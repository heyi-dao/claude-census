# TODOS

## Pending

### 智能优化建议功能 (`/census optimize`)
**What:** 新增 `/census optimize` 子命令，基于使用数据给出"建议卸载"和"建议安装"的推荐。
**Why:** 从"告诉你数据"升级到"帮你做决定"，是工具价值的本质升级。
**Context:** 需要跨引用已安装清单（skills、agents、commands）与使用记录，计算使用频率，生成推荐。可参考 `/census zombies` 的 inventory scanning 逻辑。
**Depends on:** 稳定性加固 PR 完成（SQL 注入修复 + MCP 名解析 + 测试）。
**Added:** 2026-03-28
