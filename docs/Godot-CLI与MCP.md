# Godot 版 CLI / Agent / MCP / 回放

Godot 版不是把 Node.js CLI 原样塞进游戏，而是把**同一套确定性内核**暴露成三种入口：

1. **CLI**：一次命令一张 JSON 或字符地图，适合人调试、脚本化。
2. **JSONL / MCP**：常驻进程，Agent 观察 → 动作 → 观察，思考不消耗游戏时间。
3. **游戏内回放库**：从菜单「对局回放」进入，播放、暂停、倍速、逐帧、拖动定位。

CLI、MCP 与游戏内回放共用 `scripts/cli/BombitCore.gd`，所以动作推进、哈希校验、回放归档是同一套规则。

---

## 1. 启动

### 1.1 在工程里（开发）

```powershell
# CLI（Godot 控制台版）
& "E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" `
  --headless --no-header --path E:\BombitGodot `
  --script res://scripts/cli/BombitCLI.gd -- rules --json

# 导出/正式版：用 autoload 入口（推荐）
.\build\windows\BombitGodot.console.exe --headless --no-header -- --cli rules --json

# MCP stdio
.\build\windows\BombitGodot.console.exe --headless --no-header -- --mcp
```

正式版必须带 `--no-header`，否则 Godot 的启动横幅会写进 stdout。MCP 客户端只读 stdout，stderr 会保留为日志。

### 1.2 绿色包

双击 `启动CLI.bat` 进入人类交互模式；MCP 配置见 `mcp/bombit-mcp.json`。

---

## 2. CLI

```powershell
$exe = "E:\BombitGodot\build\windows\BombitGodot.console.exe"
& $exe --headless --no-header -- --cli new --agent deepseek --mode adventure --seed demo --json
& $exe --headless --no-header -- --cli state --session SESSION --json
& $exe --headless --no-header -- --cli act --session SESSION --bomb --frames 1 --json
& $exe --headless --no-header -- --cli act --session SESSION --move down --frames 12 --json
& $exe --headless --no-header -- --cli wait --session SESSION --frames 60 --json
& $exe --headless --no-header -- --cli finish --session SESSION --json
```

### 2.1 Windows PowerShell 的 JSON 引号

PowerShell 会把参数里的双引号剥掉，`--steps '[{"move":"down","frames":12}]'` 到 Godot 里会变成 `[{move:down,frames:12}]`，不是合法 JSON。用**文件参数**最稳：

```powershell
@'
[
  {"move":"down","frames":36},
  {"bomb":true,"frames":1},
  {"wait":true,"frames":60}
]
'@ | Set-Content -Encoding UTF8 steps.json

& $exe --headless --no-header -- --cli batch --session SESSION --steps-file steps.json --json
```

同样支持 `--actions-file`、`--path-file`。简单目标可以直接写：

```powershell
& $exe --headless --no-header -- --cli goTo --session SESSION --target 3,1 --json
& $exe --headless --no-header -- --cli path --session SESSION --path "1,2;1,3" --json
```

### 2.2 动作语义

- 60 帧/秒；`--frames 1..60`，默认 12。
- `--move up|down|left|right|none`，`--bomb`、`--skill` 只在第一帧触发。
- `--wait` 等价于原地等待，不能和移动/炸弹/技能同用。
- 对战用 `--actions-file` 同时提交双方：
  ```json
  {"p1":{"move":"right"},"p2":{"bomb":true}}
  ```
- 动作推进到玩家阵亡、换关、换回合或整局结束会提前返回；看 `advancedFrames` 与 `stopReason`。
- `requestId` 可安全重试；`expectRevision` 检查过期状态。

### 2.3 会话与回放目录

| 内容 | 开发工程 | 导出绿色包 |
|---|---|---|
| 进行中会话 | `res://.bombit/sessions` | `user://bombit/sessions` |
| 归档回放 | `res://data/replays` | `user://bombit/replays` |

`--session-dir PATH`（或环境变量 `BOMBIT_SESSION_DIR`）可改到测试目录。回放文件名沿用原作规范：

```
YYYYMMDD-HHMMSS-agent-mode-character-outcome-id.replay.json
```

### 2.4 字符地图

省略 `--json` 时输出带坐标的字符地图：

```
# = 硬墙   + = 可炸砖   . = 地面
1 / 2 = 玩家   E = 小怪   X = BOSS
o = 炸弹   * = 火焰   i = 道具   ! = 毒刺
```

---

## 3. Agent：JSONL 与 MCP

### 3.1 JSONL `serve`

```powershell
& $exe --headless --no-header -- --serve --memory
```

每行一个 JSON 请求，每行一个 JSON 响应；操作与 CLI 相同（`new/state/act/batch/path/goTo/checkpoint/finish/replay/export/rules`）。`--memory` 不逐步写盘，`checkpoint` 才落盘；EOF 或主动收尾时自动 `finish` 归档。

### 3.2 MCP stdio

```json
{
  "mcpServers": {
    "bombit": {
      "command": "E:\\BombitGodot\\build\\windows\\BombitGodot.console.exe",
      "args": ["--headless", "--no-header", "--", "--mcp"]
    }
  }
}
```

MCP 实现是 Godot 原生 stdio JSON-RPC，不依赖 Node/Python。支持：

- `initialize` / `notifications/initialized` / `ping`
- `tools/list` / `tools/call`

工具：

| 工具 | 作用 |
|---|---|
| `bombit_rules` | 模式、角色、技能、时序、道具 |
| `bombit_new` | 建局，返回 `session/revision/state` |
| `bombit_state` | 读取局面，不推进时间 |
| `bombit_act` | 推进 1–60 帧 |
| `bombit_batch` | 1–1024 个动作，遇事件提前停 |
| `bombit_path` | 走相邻格序列 |
| `bombit_goto` | 最短路径走到目标格 |
| `bombit_checkpoint` | 落盘恢复点 |
| `bombit_finish` | 全量校验并归档唯一回放 |
| `bombit_replay` | 校验会话或回放文件 |
| `bombit_export` | 返回回放 JSON，不归档 |
| `bombit_list_replays` | 列出本机回放 |

典型循环：

1. `bombit_new`（`agent` 标识你的模型）。
2. `bombit_state` 读 `players/map.terrain/bombs/flames/poison`。
3. `bombit_act` / `bombit_batch` / `bombit_goto`。
4. `state.match.over == true` 后 `bombit_finish`，确认 `verified: true` 与 `replayFile`。

MCP 进程在内存中保留世界；思考、`bombit_state`、`bombit_list_replays` 都不推进时间。

---

## 4. 游戏内回放播放器

菜单右上角「对局回放」→ 回放库。

- **GODOT 标签**：Godot 原生回放，加载时逐动作重演并比对 SHA-256，顶部显示「已验证」。
- **JS COMPAT 标签**：原作 `bombit-replay/1` 回放，动作兼容重演，但快照哈希算法不同，显示「原作兼容 · 未校验」。
- 播放/暂停：`Space`；逐秒：`←/→`；5 秒：`Shift+←/→`；倍速：`↑/↓` 或按钮；拖动进度条定位；`Esc` 返回回放库/菜单。
- 进度条上的青色刻度是关卡/回合，红色是阵亡；定位在后台分块重演，不会卡住主循环。
- 也可以「打开文件…」加载任意 `.replay.json`。

回放只重演，不会覆盖存档。Godot 回放的哈希由 `BombitCore.state_hash()` 计算，用于检测规则/状态漂移。

---

## 5. 目录与扩展

```text
scripts/cli/
├── BombitCore.gd      会话、动作、观察、哈希、寻路、归档
├── CliApp.gd          CLI / JSONL / MCP 的协议实现
├── BombitCLI.gd       开发期 --script 入口
└── CliBootstrap.gd    导出包 autoload 入口
scripts/ReplayUI.gd    回放库 + 播放器 UI
data/replays/          随包回放样例
```

回归：

```powershell
godot --headless --path . --script res://tests/test_core.gd
godot --headless --path . --script res://tests/test_play.gd
godot --headless --path . --script res://tests/test_cli_core.gd
```

结果：`42 / 35 / 20` 项，0 失败。
