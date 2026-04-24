# Evolver 在 Claude Code 的交接说明（2026-04-20）

本文档用于把当前项目中 Evolver 与 Claude Code 的集成方式完整交接给团队同事，目标是让同事可在不同机器上快速复用，并尽量达到“一次执行高成功率”。

---

## 1. 目标与范围

本交接文档聚焦：

- Claude Code 平台下 Evolver hooks 的安装与运行；
- 日常开发中 `run/review/loop` 的推荐流程；
- 多项目协作时的统一启动方式；
- 常见故障排查与验证清单。

说明：

- 本文档是 Claude Code 版本；
- Cursor 版本请参考：`memory/EVOLVER_CURSOR_HANDOVER_2026-04-20.md`。

---

## 2. 关键文件与入口

### 2.1 Evolver 入口

- `E:/git project/evolver/evolver/index.js`

### 2.2 Claude Code 适配器

- `E:/git project/evolver/evolver/src/adapters/claudeCode.js`
- `E:/git project/evolver/evolver/src/adapters/hookAdapter.js`

### 2.3 Claude Code hooks 配置（由 setup-hooks 生成/更新）

- `<项目根>/.claude/settings.json`
- `<项目根>/.claude/hooks/evolver-session-start.js`
- `<项目根>/.claude/hooks/evolver-signal-detect.js`
- `<项目根>/.claude/hooks/evolver-session-end.js`
- `<项目根>/CLAUDE.md`（自动注入 Evolver 段落）

---

## 3. Claude Code 事件映射（与 Cursor 差异）

根据当前适配器实现，Claude Code hooks 映射如下：

- `SessionStart` -> `node .claude/hooks/evolver-session-start.js`
- `PostToolUse (matcher=Write)` -> `node .claude/hooks/evolver-signal-detect.js`
- `Stop` -> `node .claude/hooks/evolver-session-end.js`

说明：

- Claude Code 使用 `PostToolUse + Write` 作为“文件修改后信号检测”触发点；
- 这与 Cursor 的 `afterFileEdit` 在语义上等价，但事件名称不同。

---

## 4. 安装步骤（给同事的最短路径）

在 `E:/git project/evolver/evolver` 执行：

1. 安装依赖（如未安装）  
   - `npm install`
2. 安装 Claude Code hooks  
   - `node index.js setup-hooks --platform=claude-code --force`
3. 验证文件是否生成  
   - `.claude/settings.json`
   - `.claude/hooks/evolver-session-*.js`
4. 重启 Claude Code 会话。

---

## 5. 日常使用流程（推荐）

### 5.1 单次演化（手动）

- `node index.js`

适用场景：

- 需要先看本轮生成的 GEP 提示词；
- 先观察再决定是否进入 review/approve。

### 5.2 审查模式（推荐）

1. 生成候选：
   - `node index.js`
2. 审查：
   - `node index.js --review`
3. 通过：
   - `node index.js review --approve`

### 5.3 持续循环（守护）

- `node index.js --loop`

建议：

- 使用统一启动脚本（见第 6 节）；
- 避免直接在多人共享终端重复启动多个 loop 进程。

---

## 6. 多项目统一启动（推荐）

当前项目已提供统一脚本：

- `E:/git project/evolver/evolver/scripts/start-evolver.ps1`

它适用于 Claude Code 同事（不仅限 Cursor），因为其核心是统一注入 Evolver 环境变量并启动 `index.js`。

常用命令：

- 查看项目清单：
  - `powershell -ExecutionPolicy Bypass -File "E:\git project\evolver\evolver\scripts\start-evolver.ps1" -ListProjects`
- 启动 loop：
  - `powershell -ExecutionPolicy Bypass -File "E:\git project\evolver\evolver\scripts\start-evolver.ps1" -ProjectId big-a -Mode loop`
- 演练（不执行）：
  - `powershell -ExecutionPolicy Bypass -File "E:\git project\evolver\evolver\scripts\start-evolver.ps1" -ProjectId big-a -Mode loop -DryRun`

当前脚本已默认：

- `EVOLVE_BRIDGE=true`（避免 loop 中 pending run 被自动拒绝）；
- `EVOLVER_SESSION_LOGS_DIR` 与 `AGENT_SESSIONS_DIR` 注入；
- `EVOLVER_DISABLE_OPENCLAW_MIRROR` 开关可控。

---

## 7. 验证清单（接手当天执行）

### 7.1 安装验证

执行：

- `node index.js setup-hooks --platform=claude-code --force`

期望：

- 输出安装完成；
- `.claude/settings.json` 中出现 `SessionStart/PostToolUse/Stop` 对应命令。

### 7.2 功能验证

执行一次开发会话并结束后，检查：

1. `node index.js --review` 能看到 pending run；
2. `node index.js review --approve` 返回 `[SOLIDIFY] SUCCESS`（若校验通过）；
3. `memory/evolution/evolution_solidify_state.json` 的 `last_run/last_solidify` 更新。

### 7.3 路径空格验证（Windows 关键）

执行：

- `node scripts/validate-suite.js`

期望：

- 不因 `E:/git project/...` 路径空格导致误失败（已修复为参数数组执行）。

---

## 8. 常见问题排查

### 8.1 hooks 看起来没生效

- 重新执行：
  - `node index.js setup-hooks --platform=claude-code --force`
- 检查 `.claude/settings.json` 是否有 Evolver hooks；
- 确认会话已重启。

### 8.2 `--loop` 中出现 auto-rejected 提示

- 检查是否存在 `EVOLVE_BRIDGE=false` 的外部覆盖；
- 推荐通过 `start-evolver.ps1` 启动（默认 `EVOLVE_BRIDGE=true`）。

### 8.3 signals 出现超长污染文本

- 当前已在 bridge 清洗逻辑中增加标签过滤与长度截断；
- 若仍出现，优先执行一次 `--review` 看 `Signals` 是否干净，再定位具体样本。

---

## 9. 交接结论

当前项目已具备 Claude Code 可复用集成能力：

- 平台适配器与 hooks 自动安装链路完整；
- `run/review/approve/loop` 流程可直接复用；
- Windows 路径空格、loop bridge 默认值、信号污染等关键问题已有修复；
- 可与 Cursor 版本并行维护，适配团队多平台协作。

---

## 10. 可拷贝启动脚本（跨项目）

`start-evolver.ps1` 已支持“复制到任意项目根直接使用”的模式，适用于 Claude Code 同事：

1. 首次初始化（指定 evolver 根路径）：
   - `powershell -ExecutionPolicy Bypass -File ".\start-evolver.ps1" -Init -EvolverRoot "<path-to-evolver-root>"`
2. 默认执行（review）：
   - `powershell -ExecutionPolicy Bypass -File ".\start-evolver.ps1"`
3. 持续循环：
   - `powershell -ExecutionPolicy Bypass -File ".\start-evolver.ps1" -Mode loop`

脚本会自动：

- 写入当前项目信息（`project_id/project_root/...`）；
- 注入运行环境（含 `EVOLVE_BRIDGE=true`）；
- 在 `solidify` 与 `review --approve` 成功后，将 runtime `.mdc` 覆盖导出到当前项目：
  - `.cursor/rules/evolver-runtime.mdc`
  - `.claude/rules/evolver-runtime.mdc`

