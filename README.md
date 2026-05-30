# Codex Notch macOS App

这是一个独立的 macOS SwiftPM MVP，用来在屏幕顶部展示 Codex 桌面刘海屏体验。它只读读取本机 Codex 状态，收起时展示当前会话状态、标题和完成进度，存在运行中或等待处理的会话时会轮播提示；展开后展示最近会话列表，点击会话可尝试通过 Codex 深链回到对应工作上下文。

## 项目目标

- 提供一个不修改 Codex App 的独立顶部刘海屏入口。
- 用红、黄、绿三种状态表达最近会话的健康度和活跃度。
- 收起态优先轮播红黄灯会话，没有红黄灯时展示最近一条会话，并显示已完成/总会话数。
- 展开后展示最多 8 条最近会话，包括标题、工作目录提示、最近活动时间和注意力状态。
- 点击会话后优先打开 `codex://threads/<thread-id>` 深链，并通过可见 Terminal 执行 `codex resume <threadID>` 作为兜底。
- 支持可配置快捷键展开面板，默认 `Cmd+F1`，展开后用上下键切换会话，回车进入选中对话，`Esc` 收起面板。

## 运行方式

在 `codex-notch-macos-app/` 目录下可以执行 `swift run CodexNotch` 启动应用，也可以用 Xcode 打开 `Package.swift` 后运行 `CodexNotch` target。验收以本机手动打开应用和观察行为为主。

## 编译方式

在 `codex-notch-macos-app/` 目录下可以执行 `./scripts/build.sh` 编译 debug 版本，也可以执行 `./scripts/build.sh release` 编译 release 版本。脚本只执行 SwiftPM 编译，不启动应用、不运行测试。

## 打包成 App

在 `codex-notch-macos-app/` 目录下执行 `./scripts/package_app.sh` 可以生成 release 版 `dist/Codex Notch.app`，执行 `./scripts/package_app.sh debug` 可以生成 debug 版。该 app bundle 默认使用 `local.codex.notch` 作为 bundle identifier，也可以通过 `BUNDLE_IDENTIFIER=... ./scripts/package_app.sh` 覆盖。产物是本地未签名 app，后续如果要分发还需要签名和 notarize。

## 界面行为

- 应用以 accessory 模式运行，不展示 Dock 图标，并在右上角状态栏区域显示 Codex 胶囊。
- 胶囊以深色背景展示紧凑状态灯和短状态文案，点击后从状态栏下方展开最近会话面板。
- 展开面板高度会适配当前屏幕状态栏高度，不再长期覆盖系统状态栏图标。
- 默认每 3 秒刷新一次本机 Codex 状态。
- 鼠标悬停刘海区域会展开面板，移出后短暂延迟再收起，窗口失焦也会收起。
- 右键点击刘海屏可以打开设置或退出应用。
- 状态灯使用红、黄、绿三色：黄色闪烁表示运行中，红色闪烁表示等待输入或失败信号，绿色常亮表示任务完成。

## 数据源

- `~/.codex/state_5.sqlite`：只读读取 thread 元信息，例如 id、标题、工作目录、归档状态和更新时间。
- `~/.codex/sessions/**/*.jsonl`：只读读取尾部有限事件元数据，用于辅助判断最近活动、完成、失败或等待状态。
- `~/.codex/session_index.jsonl`：作为 SQLite 信息不足或不可用时的只读兜底索引。

## 隐私边界

- 应用不写入 `~/.codex` 下任何文件。
- jsonl 只读取尾部有限事件元数据，不展示用户正文、助手正文或完整对话内容。
- 应用不修改、不注入、不 patch Codex App。
- 应用不上传本地 Codex 数据，所有读取和展示都限定在本机。
- 本地通知只使用会话标题、工作目录名、状态关键词和活动时间，不展示用户正文、助手正文或完整对话内容。

## 跳转行为

- 点击指定会话时，应用会先校验 thread id 是否是 UUID 形态，再尝试打开 `codex://threads/<thread-id>`。
- 深链打开后会短延迟激活已经运行的 Codex App，避免打开根入口覆盖目标 thread。
- 如果深链无法打开，会先尝试通过 bundle id 或 `/Applications/Codex.app` 打开 Codex App，然后再次尝试深链。
- 只有 Codex App 或深链路径不可用时，才通过 Terminal 可见执行 `codex resume <threadID>` 作为兜底。
- Terminal 兜底会优先使用 Codex App 内置 CLI，然后尝试 `/opt/homebrew/bin/codex`、`/usr/local/bin/codex`，最后退回 `env codex`。
- Terminal 成功启动只表示兜底命令已交给终端执行，不保证后续 Codex CLI 一定存在、认证有效或 resume 成功。

## 快捷键和提醒

- 默认 `Cmd+F1`：展开刘海面板并聚焦键盘选择，可在右键菜单的设置页中修改。
- `↑` / `↓`：在展开面板中切换选中会话。
- `Return`：进入当前选中会话。
- `Esc`：收起展开面板。
- 当会话出现等待输入、权限确认或运行事件超过约 10 分钟没有新活动时，应用会尝试发送本地通知。
- 同一会话的同类提醒默认至少间隔约 10 分钟，避免重复打扰。

## 第一版限制

- 第一版只支持 macOS，不支持 Windows 或 Linux。
- 第一版只展示红黄绿状态，不展示百分比进度。
- 第一版依赖 Codex App 对 `codex://threads/<thread-id>` 的支持；如果本机 Codex App 版本不支持该深链，会退回 Terminal resume。
- 第一版不写入会话状态，也不创建新的 Codex thread。
- 第一版状态判断保持保守，只对等待输入、权限确认、明确阻塞或运行事件超过约 10 分钟没有新活动的会话做额外提醒。

## 手动验收清单

- 启动应用后，刘海屏出现在主屏顶部中间。
- 收起态展示红黄绿状态点、当前标题和已完成/总会话数，保持在状态栏内。
- 存在多个红黄灯会话时，收起态会轮播显示等待输入或运行中的会话。
- 鼠标悬停刘海屏后能展开最近会话列表，移出刘海或窗口失焦时可收起。
- 右键点击刘海屏后，菜单里可以打开设置页或选择退出应用。
- 会话列表不展示用户正文、助手正文或完整对话内容。
- 默认 `Cmd+F1` 能展开面板，设置页修改快捷键后新快捷键能展开面板，上下键能切换高亮行，回车能进入选中会话，`Esc` 能收起面板。
- 等待输入或可能停滞的会话会显示对应短文案，并在通知权限允许时触发本地通知。
- 点击 UUID 形态的会话后，Codex App 会尝试打开对应 thread 深链并被激活。
- 深链或 Codex App 不可用时，Terminal 中能看到 `codex resume <threadID>` 命令被执行。
- 在 `~/.codex` 中没有新增或被修改的文件。
