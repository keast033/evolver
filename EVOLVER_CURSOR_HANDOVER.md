# Evolver 在 Cursor 的改造交接说明（2026-04-20）

本文档用于把本次会话中与 Evolver 相关的改造、优化和新增能力完整交接给团队同事，确保其他人可以直接复用当前方案。

## 1. 改造目标

本次改造前，主要问题是：

- 会话结束时可能出现 `recorded to nowhere (no Hub or local path)`，导致结果丢失。
- Windows 环境下 Hook 使用 Unix 重定向会有噪音报错。
- `0, +0/-0` 的空会话也会写入记录，噪音较大。
- 没有按天的 `YYYY-MM-DD.md` 自动创建和自动追加机制。

本次改造后，目标达成如下：

- 支持默认本地落盘（即使未配置 Hub）。
- 支持 Windows 无噪音执行。
- 过滤空会话记录。
- 会话结束自动创建并追加当天 Markdown 日志。
- 自动日志模板支持“人工补充区”。

---

## 2. 涉及文件总览

### 2.1 Cursor Hook 配置

- `C:/Users/Administrator/.cursor/hooks.json`

当前关键配置：

- `sessionStart` -> `node ./hooks/evolver-session-start.js`
- `afterFileEdit` -> `node ./hooks/evolver-signal-detect.js`
- `stop` -> `node ./hooks/evolver-session-end.js`

### 2.2 关键脚本

- `C:/Users/Administrator/.cursor/hooks/evolver-session-start.js`
- `C:/Users/Administrator/.cursor/hooks/evolver-session-end.js`
- `C:/Users/Administrator/.cursor/hooks/evolver-signal-detect.js`（本次未改逻辑）

### 2.3 Memory 文件

- `E:/git project/evolver/evolver/memory/MEMORY.md`
- `E:/git project/evolver/evolver/memory/2026-04-20.md`

---

## 3. 已完成的核心改动

## 3.1 默认本地落盘（修复 nowhere）

改动文件：`evolver-session-end.js` 与 `evolver-session-start.js`

- 增加了无 Hub 场景的默认路径兜底：
  - `C:/Users/Administrator/.cursor/evolution/memory_graph.jsonl`
- `MEMORY_GRAPH_PATH` 若存在，会优先采用，并自动创建父目录（session-end）。

效果：

- 原先 `recorded to nowhere` 的会话，改为 `recorded to local memory`。

## 3.2 Windows 兼容修复

改动文件：`evolver-session-end.js`

- 将 stderr 重定向按平台处理：
  - Windows：`nul`
  - 其他：`/dev/null`

效果：

- 消除 Windows 下“系统找不到指定路径”的噪音输出。

## 3.3 空会话过滤

改动文件：`evolver-session-end.js`

- 新增 no-op 判定逻辑：
  - `files changed == 0`
  - `insertions == 0`
  - `deletions == 0`
- 命中后直接返回 `{}`，不写 Hub、不写本地、不输出提示。

效果：

- 过滤 `Session end: 0, +0/-0` 这类无效记录，降低日志噪音。

## 3.4 自动创建并追加每日 Markdown

改动文件：`evolver-session-end.js`

- 新增 `findDailyMemoryDir()` 与 `appendDailyMarkdown()`。
- 会话结束（且非空会话）时自动：
  1. 定位日报目录
  2. 不存在则创建 `YYYY-MM-DD.md`
  3. 追加一条会话摘要

目录优先级（从高到低）：

1. 固定项目目录：`E:/git project/evolver/evolver/memory`
2. `EVOLVER_MEMORY_DIR`
3. `EVOLVER_ROOT/memory`
4. `C:/Users/Administrator/.cursor/evolution/daily`

说明：固定目录被放在第一位，确保你当前项目稳定写入目标目录。

## 3.5 自动日志模板升级 + 人工补充区

改动文件：`evolver-session-end.js`

每条自动记录将追加以下结构：

- 场景
- 动作
- 结果
- 信号
- 证据（摘要）
- 结论（下次策略）
- `#### 人工补充区`
  - 背景补充
  - 业务影响
  - 复盘结论

效果：

- 机器自动写基础信息，人类补业务上下文，便于团队知识传递。

---

## 4. 当前运行机制（同事必读）

会话生命周期中的行为：

1. `sessionStart`：
   - 从 `memory_graph.jsonl` 读取最近记录并注入上下文（若有）。
2. `afterFileEdit`：
   - 轻量检测信号并提示可记录（不直接落库）。
3. `stop`（关键）：
   - 计算 git diff 统计与信号
   - 过滤空会话
   - 尝试写 Hub（若配置）
   - 写本地 `memory_graph.jsonl`
   - 自动写入当天 `YYYY-MM-DD.md`

---

## 5. 如何使用（给同事的最短路径）

## 5.1 前置条件

- 本机可执行 `node`
- Cursor 启用 hooks（当前已配置在 `hooks.json`）

## 5.2 日常使用

- 正常使用 Cursor 编码即可。
- 会话结束时自动触发 `stop hook`，无需手工命令。
- 记录结果查看位置：
  - 结构化：`C:/Users/Administrator/.cursor/evolution/memory_graph.jsonl`
  - 日志日报：`E:/git project/evolver/evolver/memory/YYYY-MM-DD.md`

## 5.3 人工补充

- 在当天文件中找到最新 `### [HH:mm] 自动记录：Session End`
- 填写其下方 `#### 人工补充区`

---

## 6. 验证步骤（新同事接手后执行一次）

1. 触发一次正常会话并结束。
2. 观察 stop 输出应包含：
   - `recorded to local memory`
   - 并可能包含 `+ daily markdown`
3. 检查文件：
   - `memory_graph.jsonl` 有新行
   - 当天 `YYYY-MM-DD.md` 被创建/追加
4. 再触发一次“无变更会话”：
   - 应不再出现 `0, +0/-0` 记录

---

## 7. 常见问题排查

## 7.1 仍显示 recorded to nowhere

- 检查 `hooks.json` 是否仍指向 `evolver-session-end.js`
- 检查脚本是否为最新版本（含 `findMemoryGraph` fallback）
- 检查 Node 是否可执行

## 7.2 没有生成 `YYYY-MM-DD.md`

- 检查是否为空会话（`0,+0/-0` 已被过滤，不会写日报）
- 检查目录权限：
  - `E:/git project/evolver/evolver/memory`
- 检查 stop hook 是否实际触发（看 stop 输出）

## 7.3 Windows 出现路径报错

- 确认脚本中使用了平台分支：
  - win32 -> `nul`
  - 其他 -> `/dev/null`

---

## 8. 后续可选优化（本次未做）

- 按项目拆分 `memory_graph.jsonl`，减少跨项目噪音。
- 对 `YYYY-MM-DD.md` 引入轮转或归档策略。
- 增加 `MEMORY.md` 索引自动维护（当前按你的要求未启用）。

---

## 9. 变更结论

Evolver 在 Cursor 的核心闭环已形成：

- 可记录（local/hub）
- 可过滤（空会话）
- 可沉淀（daily markdown）
- 可复盘（人工补充区）

这套方案可以直接给同事复用，不需要额外改业务代码。

---

## 10. 2026-04-21 补充：修复 `NO SESSION LOGS FOUND` 路径问题

本次新增修复目标：当执行 `node index.js` 出现

`Recent session transcript: [NO SESSION LOGS FOUND]`

时，优先读取 Cursor 当前真实存在的会话来源，而不是仅依赖 OpenClaw 的默认路径。

### 10.1 实际定位结果（历史记录）

- 当时执行的是全局安装包：`@evomap/evolver@1.69.3`
- 当时入口：`D:/nodejs/node_global/node_modules/@evomap/evolver/index.js`
- 当时会话目录解析逻辑位于：`D:/nodejs/node_global/node_modules/@evomap/evolver/src/gep/paths.js`
- 既有逻辑默认回落到：
  - `~/.openclaw/agents/<agent>/sessions`

### 10.2 已落地修改（已完成）

已修改 `src/gep/paths.js` 的 `getAgentSessionsDir()`，新增以下优先级：

1. `AGENT_SESSIONS_DIR`（保留）
2. `EVOLVER_SESSION_LOGS_DIR`（新增：手动指定日志目录）
3. 自动发现 Cursor `agent-transcripts`（新增）：
   - 扫描 `~/.cursor/projects/*/agent-transcripts`
   - 仅接受包含 `.jsonl` 的目录
   - 支持 `EVOLVER_CURSOR_PROJECT_ID` 精确锁定项目
   - 默认按“项目名匹配分数 + 最近修改时间”选最优目录
4. 兜底保留旧行为：`~/.openclaw/agents/<agent>/sessions`

### 10.3 对使用方的意义

- 不改业务仓库代码即可修复会话读取来源偏差。
- 在 Cursor 环境下，Evolver 将优先读取真实存在的 `agent-transcripts/*.jsonl`。
- 需要强制路径时可直接设：
  - `EVOLVER_SESSION_LOGS_DIR`
  - `EVOLVER_CURSOR_PROJECT_ID`

### 10.4 备注

- 本次为全局 npm 包内源码热修，后续若升级 `@evomap/evolver` 可能被覆盖。
- 建议后续将该补丁合并到上游仓库，或在升级后重新应用。

---

## 11. 2026-04-21 补充（二）：最终打通与验证结果

### 11.1 问题复盘

虽然已经完成 Cursor transcript 自动发现与桥接，但在 `node index.js` 实测中仍出现：

`Recent session transcript: [NO SESSION LOGS FOUND]`

说明当前版本内部扫描器存在“仅读取 OpenClaw 既有目录约定”的兼容行为。

### 11.2 最终修复（已固化到项目版 index.js）

改动文件：`E:/git project/evolver/evolver/index.js`

在 `ensureCursorTranscriptBridge()` 中，除了写入：

- `memory/cursor-session-bridge/latest.jsonl`

还新增自动镜像到 OpenClaw 目录：

- `~/.openclaw/agents/<AGENT_NAME|main>/sessions/cursor-bridge-latest.jsonl`

并在运行时设置：

- `EVOLVER_SESSION_LOGS_DIR=<repo>/memory/cursor-session-bridge`
- `AGENT_SESSIONS_DIR=~/.openclaw/agents/<agent>/sessions`

这样可同时覆盖“新路径读取”和“旧硬编码读取”两类实现。

### 11.3 最终验证（通过）

执行：`node index.js`

关键结果：

- 不再出现 `[NO SESSION LOGS FOUND]`
- Signals 从仅 `session_logs_missing` 转为多条真实信号（如 `user_feature_request`、`user_improvement_suggestion`、`perf_bottleneck` 等）
- `Recent session transcript` 区块出现真实会话文本（含 `--- SESSION (cursor-bridge-latest.jsonl) ---`）

### 11.4 交接结论

当前项目版 Evolver 已具备“Cursor transcript -> Evolver 可读 transcript”自动桥接能力，无需手工复制文件即可稳定读取会话来源。

### 11.5 开关与按环境切换（新增）

为避免某些环境不希望写入 OpenClaw 目录，新增回滚开关：

- `EVOLVER_DISABLE_OPENCLAW_MIRROR=1`（或 `true`）

行为说明：

1. 默认（不设置）：
   - 继续同时写入
     - `memory/cursor-session-bridge/latest.jsonl`
     - `~/.openclaw/agents/<agent>/sessions/cursor-bridge-latest.jsonl`
   - 兼容性最强，适合混合环境。

2. 设置 `EVOLVER_DISABLE_OPENCLAW_MIRROR=1`：
   - 仅写入 `memory/cursor-session-bridge/latest.jsonl`
   - 不再写入 OpenClaw sessions 目录
   - 适合 Cursor-only 环境或排障场景（减少副作用）。

---

## 12. 2026-04-21 补充（三）：MEMORY.md 多项目与语言策略重构

### 12.1 背景

用户提出两个问题：

1. `MEMORY.md` 是否必须全英文才能被 Evolver 正确读取。
2. 多项目场景下 `MEMORY.md` 应如何组织，避免项目知识互相干扰。

### 12.2 结论

- `MEMORY.md` 不是“只能英文”。
- 但考虑 Evolver 当前提示词与信号链路偏英文语境，采用“中英混合、英文标签优先”更稳定。
- 多项目推荐“全局索引 + 项目分文件”结构，避免上下文串扰。

### 12.3 已实施改动

改动文件：`E:/git project/evolver/evolver/memory/MEMORY.md`

改动点：

1. 将文件定位从“单项目笔记”升级为“全局记忆索引”。
2. 新增 `Language Policy`：
   - 业务描述可中英文
   - `signals/tags/conclusions` 优先英文关键字
3. 新增 `Global Rules` 与 `Signal Dictionary`（English-first）。
4. 新增 `Cross-Project Patterns`（跨项目复用成功/失败模式）。
5. 新增 `Project Index` 与 `Project Template`，支持项目拆分维护。
6. 保留并标准化当前项目快照（`big-a-stock-analysis`）。

### 12.4 这么做的理由

- **读取稳定性**：英文标签与现有信号识别链更容易匹配。
- **可读性**：中文业务说明便于团队理解与协作。
- **可扩展性**：多项目拆分可避免策略误迁移（context bleed）。
- **可执行性**：强制 `project_id/repo_path` 字段，让结论可追踪、可筛选。

### 12.5 使用建议（后续）

1. 新项目按 `Project Template` 新建 `memory/projects/<project-id>.md`。
2. `MEMORY.md` 仅保留全局规则、信号字典、索引，不堆项目细节。
3. 每条经验优先写成短句规则（Do/Don't），并附英文标签。

---

## 13. 2026-04-21 补充（四）：桥接信号噪音修复（仅保留 user 内容）

### 13.1 问题

在 `cursor transcript -> latest.jsonl` 桥接中，早期实现会提取 assistant 的探索性文本，导致信号扫描器误捕捉到无关语句（如 `Inspecting node_modules`），形成噪音信号。

### 13.2 修复

改动文件：`E:/git project/evolver/evolver/index.js`

新增：

- `normalizeRole()`
- `isUserRoleRecord()`

并在桥接循环中增加角色过滤：

- 仅当记录角色为 `user` 或 `human` 时，才提取并写入桥接文件。
- 支持常见字段与嵌套对象中的角色键：`role/sender/author/source`。

### 13.3 理由

- 降低误报：避免 assistant 自言自语被当成真实演化信号。
- 提高信号质量：桥接输入更接近“用户真实意图”。
- 稳定选择策略：减少无关关键词干扰 gene selection。

### 13.4 二次增强（用户粘贴历史对话场景）

发现另一类噪音：即使记录是 `user`，用户也可能粘贴包含 `**ASSISTANT**:` 的整段历史对话。

因此在桥接中新增 `sanitizeBridgedUserText()`：

- 按行过滤 `**ASSISTANT**:` / `ASSISTANT:` 前缀行；
- 仅将净化后的 user 内容写入桥接文件。

---

## 14. 2026-04-21 补充（五）：无损噪音清理执行记录

### 14.1 清理目标

在不改业务代码语义的前提下，清理历史桥接/记忆中的 assistant 噪音残留，避免继续污染后续信号。

### 14.2 执行动作

1. 先备份（完整可回滚）：
   - `memory/cleanup-backups/20260421-105302/`
   - `memory/cleanup-backups/20260421-105342-scope-clean/`
2. 删除桥接产物（自动重建）：
   - `memory/cursor-session-bridge/latest.jsonl`
   - `~/.openclaw/agents/main/sessions/cursor-bridge-latest.jsonl`
3. 定向清洗历史文件中的明显噪音特征：
   - `memory/evolution/**/memory_graph.jsonl`
   - `memory/evolution/**/question_generator_state.json`（清空 `recentQuestions`）

### 14.3 结果

复测 `node index.js` 后：

- 主信号显著收敛（`regex=3, score=1, merged=4`）。
- `Context [Signals]` 收敛为：
  - `protocol_drift`
  - `user_feature_request`
- 能力候选里的参数噪音已消失明显（不再出现长段 assistant 探索文本）。

### 14.4 备注

- 若后续需要回滚，可从上述 `cleanup-backups` 目录恢复。
- 该清理为“无损优先”策略：先备份，再按噪音特征最小范围过滤。

---

## 15. 2026-04-21 补充（六）：一键清理脚本

### 15.1 脚本位置

- `E:/git project/evolver/evolver/memory/scripts/clean-noise.ps1`

### 15.2 脚本功能

执行后会自动完成以下动作（按顺序）：

1. 创建时间戳备份目录（`memory/cleanup-backups/<timestamp>-script`）。
2. 备份以下文件：
   - bridge 本地文件
   - OpenClaw bridge 文件
   - `memory/evolution/**/memory_graph.jsonl`
   - `memory/evolution/**/question_generator_state.json`
3. 删除 bridge 产物（下次运行自动重建）：
   - `memory/cursor-session-bridge/latest.jsonl`
   - `~/.openclaw/agents/main/sessions/cursor-bridge-latest.jsonl`
4. 清理 `memory_graph.jsonl` 中已知 assistant 噪音特征行。
5. 重置 `question_generator_state.json` 的 `recentQuestions`，避免旧候选污染。

### 15.3 使用方式

在 PowerShell 执行：

- 默认路径：
  - `powershell -ExecutionPolicy Bypass -File "E:\git project\evolver\evolver\memory\scripts\clean-noise.ps1"`
- 自定义 memory 根目录：
  - `powershell -ExecutionPolicy Bypass -File "E:\git project\evolver\evolver\memory\scripts\clean-noise.ps1" -Root "E:\git project\evolver\evolver\memory"`

执行后建议立即运行：

- `node index.js`

用于重建干净的 bridge 上下文。

---

## 16. 2026-04-21 补充（七）：一键启动脚本（多项目交接版）

### 16.1 目标

为降低同事接手成本，新增“单文件一键启动”方案，覆盖以下诉求：

- 将常用命令收敛为单入口；
- 支持多项目切换；
- 启动前自动校验关键前置条件；
- 尽量实现“一次执行 99% 成功”。

### 16.2 新增文件

- `E:/git project/evolver/evolver/scripts/start-evolver.ps1`

### 16.3 脚本已集成能力

1. **多项目注册表（内置）**
   - 通过脚本内 `$Projects` 数组维护项目配置；
   - 每个项目包含：
     - `project_id`
     - `repo_root`
     - `memory_dir`
     - `cursor_project_id`
     - `agent_name`
     - `notes`

2. **启动前自检**
   - 校验 `node`、`git` 是否可执行；
   - 校验 `repo_root` 是否存在且为 git work tree；
   - 校验 `index.js` 是否存在；
   - 自动创建缺失目录（`memory`、bridge 目录、OpenClaw sessions 目录）。

3. **统一环境变量注入**
   - `EVOLVE_STRATEGY`
   - `EVOLVER_SESSION_LOGS_DIR`
   - `AGENT_SESSIONS_DIR`
   - `EVOLVER_CURSOR_PROJECT_ID`（配置不为空时）
   - `EVOLVER_DISABLE_OPENCLAW_MIRROR`

4. **运行模式统一**
   - `-Mode loop`（默认）
   - `-Mode run`
   - `-Mode review`
   - 支持 `-DryRun`（仅预览命令，不实际执行）

### 16.4 对同事的标准用法（直接复制）

1. 查看可用项目：

`powershell -ExecutionPolicy Bypass -File "E:\git project\evolver\evolver\scripts\start-evolver.ps1" -ListProjects`

2. 正式启动循环（推荐）：

`powershell -ExecutionPolicy Bypass -File "E:\git project\evolver\evolver\scripts\start-evolver.ps1" -ProjectId big-a -Mode loop`

3. 演练模式（不执行，仅预览）：

`powershell -ExecutionPolicy Bypass -File "E:\git project\evolver\evolver\scripts\start-evolver.ps1" -ProjectId big-a -Mode loop -DryRun`

### 16.5 新增项目时如何配置

在 `start-evolver.ps1` 顶部 `$Projects` 中复制一个项目块并修改：

- `project_id`（唯一 ID）
- `repo_root`
- `memory_dir`
- `cursor_project_id`（可留空）
- `agent_name`（默认 `main`）

建议：

- 一个业务仓库对应一个 `project_id`；
- `memory_dir` 与该项目绑定，避免跨项目记忆串扰；
- 交接时先执行一次 `-DryRun`，确认路径与变量注入正确，再执行 `-Mode loop`。

### 16.6 交接结论（本次新增）

在现有 hook 自动记录链路不变的前提下，启动层已经标准化为“单命令入口 + 多项目配置”，可直接用于团队交接与批量复用。

---

## 17. 2026-04-21 补充（八）：二次修复 `NO SESSION LOGS FOUND` + Windows 路径空格问题

### 17.1 背景

在项目版 `node index.js` 的后续实测中，仍出现两类问题：

1. 继续出现 `Recent session transcript: [NO SESSION LOGS FOUND]`。
2. `review --approve` 时 `validate-suite` 在路径含空格（如 `E:/git project/...`）下误失败，触发回滚。

### 17.2 根因定位

1. **Cursor transcript 目录结构兼容缺失**  
   实际目录是：
   - `~/.cursor/projects/<project>/agent-transcripts/<uuid>/<uuid>.jsonl`  
   早期探测仅按“`agent-transcripts` 目录下直接存在 `.jsonl` 文件”判断，导致误判无日志。

2. **桥接文件记录格式不兼容当前解析器**  
   解析链路更稳定识别的是 Cursor 风格记录（`role + message.content`），而不是简化 `type/text` 结构。

3. **测试脚本命令拼接问题**  
   `scripts/validate-suite.js` 早期使用字符串拼接执行命令，路径包含空格时参数被错误拆分。

### 17.3 本次已落地修复

改动文件：

- `E:/git project/evolver/evolver/src/gep/paths.js`
- `E:/git project/evolver/evolver/index.js`
- `E:/git project/evolver/evolver/scripts/validate-suite.js`

具体修复：

1. `paths.js`
   - `getAgentSessionsDir()` 优先级补齐：
     1) `AGENT_SESSIONS_DIR`
     2) `EVOLVER_SESSION_LOGS_DIR`
     3) Cursor `agent-transcripts` 自动发现
     4) scope/agent fallback 到 OpenClaw
   - 增强 Cursor 自动发现，支持：
     - `agent-transcripts/*.jsonl`
     - `agent-transcripts/<uuid>/*.jsonl`
   - 新增并导出辅助函数：
     - `hasJsonlFiles()`
     - `getLatestJsonlDir()`
     - `findCursorTranscriptDir()`

2. `index.js`
   - 新增/恢复 bridge 逻辑：
     - `ensureCursorTranscriptBridge()`
     - `normalizeRole()`
     - `isUserRoleRecord()`
     - `extractCursorRecordText()`
     - `sanitizeBridgedUserText()`
   - 启动时自动执行 bridge：
     - 从 Cursor transcript 提取 user/human 内容
     - 写入 `memory/cursor-session-bridge/latest.jsonl`
     - 默认镜像到 OpenClaw sessions（可由 `EVOLVER_DISABLE_OPENCLAW_MIRROR` 关闭）
   - 桥接输出使用兼容结构（`role + message.content`）。

3. `validate-suite.js`
   - 从字符串命令执行改为参数数组执行（`execFileSync(process.execPath, ['--test', ...files])`），消除路径空格拆分失败。

### 17.4 验证结果

1. 执行：
   - `node "E:/git project/evolver/evolver/index.js"`
2. 结果：
   - 不再出现 `Recent session transcript: [NO SESSION LOGS FOUND]`
   - `Recent session transcript` 区块出现：
     - `--- SESSION (cursor-bridge-latest.jsonl) ---`
     - 多条 `**USER**` 内容
3. 额外验证：
   - `node scripts/validate-suite.js` 在 `E:/git project/...` 路径下通过（不再因空格路径误失败）。

### 17.5 `review --approve` 成功样例（当天实测）

执行：

- `node "E:/git project/evolver/evolver/index.js" review --approve`

关键输出（节选）：

- `[SOLIDIFY] SUCCESS`
- 输出 Gene：
  - `id: gene_gep_repair_from_errors`
  - `category: repair`
  - `schema_version: 1.6.0`
  - `learning_history[0].outcome: success`
  - `epigenetic_marks[0].boost: 0.1`

判定：

- 说明 review 审批链路已恢复稳定；
- `solidify -> validation -> knowledge update` 全流程闭环通过。

### 17.6 交接建议

- 正式运行建议统一使用：
  - `powershell -ExecutionPolicy Bypass -File "E:\git project\evolver\evolver\scripts\start-evolver.ps1" -ProjectId big-a -Mode loop`
- 若排障需要禁用 OpenClaw 镜像：
  - `EVOLVER_DISABLE_OPENCLAW_MIRROR=1`
- 若需强制锁定某个 Cursor 项目：
  - `EVOLVER_CURSOR_PROJECT_ID=<project-id>`

---

---

## 18. 2026-04-21 补充（九）：修复 loop 自动拒绝 + 强化信号防污染

### 18.1 背景

在 `--loop` 实测日志中出现两类问题：

1. `Auto-rejected pending run because bridge is disabled in loop mode`
2. `signals` 中仍混入超长用户粘贴文本（如 `</user_query>`、`**USER**` 片段）

### 18.2 根因

1. `index.js` 在 loop 模式下默认将 `EVOLVE_BRIDGE` 设为 `false`（未显式配置时）。
2. bridge 文本净化规则只过滤了 assistant 前缀，未对 query 标签和会话标记做强过滤，也未限制长度。

### 18.3 修复内容（已落地）

改动文件：

- `E:/git project/evolver/evolver/index.js`
- `E:/git project/evolver/evolver/scripts/start-evolver.ps1`

改动点：

1. `index.js`
   - loop 默认值改为：
     - `EVOLVE_BRIDGE=true`（仅在未显式设置时）
   - 强化 `sanitizeBridgedUserText()`：
     - 过滤 `</user_query>`、`**USER**`、`**ASSISTANT**`、独立 `<user_query>` 标签行
     - 压缩连续空白为单空格
     - 单条桥接文本截断到 400 字符（防止 signal 爆长污染）

2. `start-evolver.ps1`
   - 启动时显式注入：
     - `EVOLVE_BRIDGE=true`
   - 启动信息新增显示：
     - `Loop bridge : true`

### 18.4 预期效果

- loop 模式不再因 bridge 默认关闭而自动拒绝 pending run。
- `signals` 中“长串粘贴文本污染”显著减少，gene 选择更稳定。
- 同事接手时默认行为更贴近“可持续自动闭环”。

## 19. 2026-04-21 补充（十）：生产闭环补齐（Gene/Capsule/Event -> Cursor Rules/提示词/子流程）

### 19.1 背景

仅将进化资产写入 `assets/gep/` 还不够；生产上需要把资产同步到 Cursor 可直接消费的位置，形成“学到 -> 用上”的闭环。

### 19.2 新增文件

- `E:/git project/evolver/evolver/scripts/export-runtime-assets.js`

### 19.3 同步目标（自动生成）

每次导出会生成/覆盖以下文件：

1. Cursor Rules
   - `E:/git project/evolver/evolver/.cursor/rules/evolver-runtime.mdc`
2. 提示词快照
   - `E:/git project/evolver/evolver/memory/prompts/evolver-latest.md`
3. 子流程手册
   - `E:/git project/evolver/evolver/memory/workflows/evolver-subflow.md`

### 19.4 数据来源

- Gene：`assets/gep/genes.json`
- Capsule：`assets/gep/capsules.json`
- Event：`assets/gep/events.jsonl`（取最新一条）

### 19.5 自动触发点（已接入）

改动文件：`E:/git project/evolver/evolver/index.js`

在以下成功路径自动调用导出脚本：

1. `node index.js solidify` 且结果 `ok=true`
2. `node index.js review --approve` 且结果 `ok=true`

### 19.6 使用方式

1. 手工导出（需要时）：
   - `node scripts/export-runtime-assets.js`
2. 自动导出：
   - 走 `solidify` 或 `review --approve` 成功后自动执行，无需手工介入。

### 19.7 交接结论

当前 Evolver 已从“仅沉淀资产”升级为“资产可被 Cursor 规则/提示词/子流程直接消费”的生产闭环，减少知识漂移与平台割裂。

  
## 20. 2026-04-21 补充（十一）：`start-evolver.ps1` 可拷贝即用改造

### 20.1 目标

让同事把 `start-evolver.ps1` 直接放到自己的项目目录即可使用，且默认行为更贴近生产。

### 20.2 改动文件

- `E:/git project/evolver/evolver/scripts/start-evolver.ps1`
- `E:/git project/evolver/evolver/scripts/export-runtime-assets.js`
- `E:/git project/evolver/evolver/index.js`（保持自动触发导出）

### 20.3 新行为

1. **脚本可拷贝到任意项目根使用**
   - 项目根按脚本所在目录自动识别；
   - 首次运行自动生成：
     - `.evolver.start.json`（本项目启动配置）
     - `.evolver.project.json`（本项目信息快照）

2. **默认模式改为 review**
   - 未显式传参时，默认执行 `--review`。

3. **自动写入当前项目信息**
   - 自动记录 `project_id/project_root/evolver_root/memory_dir/bridge_dir`。

4. **环境变量注入（启动即生效）**
   - `EVOLVE_BRIDGE=true`
   - `EVOLVER_TARGET_PROJECT_ROOT=<当前项目根>`
   - `EVOLVER_PROJECT_ID=<自动生成或配置值>`
   - `EVOLVE_STRATEGY`
   - `EVOLVER_SESSION_LOGS_DIR`
   - `AGENT_SESSIONS_DIR`
   - `EVOLVER_CURSOR_PROJECT_ID`（如配置）

5. **导出的 `.mdc` 同时支持 Cursor / ClaudeCode**
   - 覆盖输出到：
     - `<project>/.cursor/rules/evolver-runtime.mdc`
     - `<project>/.claude/rules/evolver-runtime.mdc`

6. **自动覆盖触发点（已接入）**
   - `solidify` 成功后自动导出覆盖
   - `review --approve` 成功后自动导出覆盖

### 20.4 同事使用方式（最短）

1. 把 `start-evolver.ps1` 复制到目标项目根目录。
2. 首次初始化（指定 evolver 根路径）：
   - `powershell -ExecutionPolicy Bypass -File ".\start-evolver.ps1" -Init -EvolverRoot "<path-to-evolver-root>"`
3. 日常执行（默认 review）：
   - `powershell -ExecutionPolicy Bypass -File ".\start-evolver.ps1"`
4. 运行 loop：
   - `powershell -ExecutionPolicy Bypass -File ".\start-evolver.ps1" -Mode loop`

---