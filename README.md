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

## 编译并启动

在 `codex-notch-macos-app/` 目录下执行 `./scripts/run.sh` 会编译并以前台方式启动 debug 版本，执行 `./scripts/run.sh release` 可启动 release 版本。应用运行期间终端会持续显示日志，按 `Ctrl+C` 可以停止应用。

## 打包成 App

在 `codex-notch-macos-app/` 目录下执行 `./scripts/package_app.sh` 可以生成 release 版 `dist/Codex Notch.app`，执行 `./scripts/package_app.sh debug` 可以生成 debug 版。该 app bundle 默认使用 `local.codex.notch` 作为 bundle identifier，也可以通过 `BUNDLE_IDENTIFIER=... ./scripts/package_app.sh` 覆盖。产物是本地未签名 app，后续如果要分发还需要签名和 notarize。

打包脚本会同时复制 SwiftPM 资源 bundle，其中包含 DockCat 猫咪图片和完整第三方许可证。包含这些素材的构建仅限非商业用途。

## iOS 局域网伴侣 App

第一版 iOS 伴侣 App 使用 `iOS/project.yml` 管理 Xcode 工程。安装 XcodeGen 后，在 `iOS/` 目录执行 `xcodegen generate` 可生成本地 `CodexNotchIOS.xcodeproj`；生成的 `.xcodeproj` 不提交到仓库。

macOS 设置页会显示局域网 iOS 连接二维码、地址、端口和 token。iPhone 端扫码后保存 Mac 地址和 token，前台通过 WebSocket 实时订阅状态，并在 App 内刘海屏和 Live Activity / Dynamic Island 展示运行中的 Codex 任务。第一版只保证 iOS App 前台或打开时实时同步，不接入 APNs，不承诺 App 被杀后的可靠提醒。

## 界面行为

- 应用以 accessory 模式运行，不展示 Dock 图标，并支持刘海居中与可拖动悬浮球两种入口模式。
- 悬浮入口使用透明背景的 DockCat 猫咪：绿色状态显示休息猫，黄色状态以 3fps 播放四帧走路动画，红色状态显示站立提醒猫；不绘制圆形底、光环或独立状态点。
- 单击猫咪会在猫咪所在屏幕居中打开或收起深蓝单列 Dashboard；悬停和移出不控制窗口显隐，拖动猫咪不会移动已经展开的 Dashboard。
- Dashboard 主区按最后活动时间展示最近 5 条任务，副标题包含最新消息、项目名和活动时间；底部以“输入、其中缓存、输出、总量”单行展示按本地 00:00 重置的真实 Token 摘要。
- 图钉可让悬浮 Dashboard 保持常驻，设置按钮打开设置页，关闭按钮立即收起；未常驻时窗口失焦或点击外部会自动收起。
- 刘海展开面板高度会适配当前屏幕状态栏高度，不再长期覆盖系统状态栏图标。
- 默认每 1 秒刷新一次本机 Codex 状态。
- 点击刘海区域会展开面板，点击面板外或按 Escape 会收起；悬浮模式只通过单击猫咪切换 Dashboard。
- 右键点击刘海屏可以打开设置或退出应用。
- 状态灯使用红、黄、绿三色：黄色闪烁表示运行中，红色闪烁表示等待输入或失败信号，绿色常亮表示当前无运行中任务或会话完成。

## 数据源

- `~/.codex/state_5.sqlite`：只读读取 thread 元信息，例如 id、标题、工作目录、归档状态和更新时间。
- `~/.codex/sessions/**/*.jsonl`：会话状态只读尾部有限事件；今日 Token 统计按状态库定位的 rollout 增量读取 `token_count` 累计字段。
- `~/.codex/session_index.jsonl`：作为 SQLite 信息不足或不可用时的只读兜底索引。

## 隐私边界

- 应用不写入 `~/.codex` 下任何文件。
- jsonl 会话状态只读取尾部有限事件元数据；Token 统计流式跳过非 `token_count` 内容，不展示用户正文、助手正文或完整对话内容。
- 应用不修改、不注入、不 patch Codex App。
- 应用不上传本地 Codex 数据，所有读取和展示都限定在本机。
- 本地通知只使用会话标题、工作目录名、状态关键词和活动时间，不展示用户正文、助手正文或完整对话内容。
- 局域网 iOS payload 只发送展示字段，包括会话 id、标题、项目名、状态、注意力原因和更新时间，不发送完整工作目录、用户正文、助手正文、工具输出或 jsonl 原始事件。

## 第三方素材与许可

- 悬浮猫咪素材原样取自 [DockCat](https://github.com/Auwuua/DockCat) commit `9dd4c4b678c68d7f5eb987ae9f284093e9d0d58d`，图片像素未修改。
- 本项目只在运行时等比缩放、贴底对齐、按红黄绿状态映射，并以 3fps 播放四帧走路动画。
- DockCat 素材使用 PolyForm Noncommercial License 1.0.0，因此包含这些素材的 Codex Notch 构建仅限非商业用途。
- 完整许可证随资源 bundle 分发，仓库归属与文件清单见 `THIRD_PARTY_NOTICES.md`。

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
- 切换到悬浮模式后，绿色显示休息猫、黄色播放走路动画、红色显示站立猫，且猫咪周围没有圆形光环或状态点。
- 悬停猫咪不会打开 Dashboard；单击猫咪会在当前屏幕居中打开，再次单击会收起，拖动和右键操作不会改变已展开窗口的位置。
- 会话列表不展示用户正文、助手正文或完整对话内容。
- 默认 `Cmd+F1` 能展开面板，设置页修改快捷键后新快捷键能展开面板，上下键能切换高亮行，回车能进入选中会话，`Esc` 能收起面板。
- 等待输入或可能停滞的会话会显示对应短文案，并在通知权限允许时触发本地通知。
- 点击 UUID 形态的会话后，Codex App 会尝试打开对应 thread 深链并被激活。
- 深链或 Codex App 不可用时，Terminal 中能看到 `codex resume <threadID>` 命令被执行。
- 在 `~/.codex` 中没有新增或被修改的文件。
