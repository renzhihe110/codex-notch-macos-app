# iOS LAN Notch Design

## 背景

Codex Notch macOS App 当前已经能只读读取本机 Codex 状态，并在 macOS 刘海入口、本地通知和完成弹窗中展示会话状态。本设计扩展一个 iOS App，让同一局域网内的 iPhone 可以实时查看 macOS 上的 Codex 任务状态，并在任务运行时显示 App 内刘海屏和系统 Dynamic Island / 锁屏 Live Activity。

## 已确认决策

- 第一版采用 macOS 本地 WebSocket 状态服务 + 二维码 token 配对 + iOS 前台实时订阅。
- iOS 形态同时包含 App 内刘海屏和 ActivityKit Live Activity / Dynamic Island。
- 第一版只保证 iOS App 打开或前台时实时同步；后台、锁屏、App 被杀后的可靠提醒不在 MVP 范围内。
- 首次连接使用二维码配对，二维码包含 Mac 地址、端口、token 和协议版本；手动输入地址作为兜底。
- 局域网安全边界采用随机 token 鉴权，macOS 设置页支持重置 token。

## 非目标

- 不接入 APNs，不建设服务端，不做账号体系。
- 不做 Bonjour 自动发现。
- 不支持公网访问或跨网络访问。
- 不做系统级 iOS 悬浮窗；iOS 系统级展示只使用 Live Activity / Dynamic Island 能力。
- 不同步完整用户正文、助手正文、完整 cwd、jsonl 原始事件或工具输出。
- 本设计阶段不写测试代码、不自动编译、不实现产品代码。

## 整体架构

macOS App 是唯一状态源，继续复用现有 `CodexStoreReader -> StatusMapper -> NotchState` 链路。新增局域网只读状态服务后，`AppDelegate.refreshStatus()` 每次生成最新 `NotchState` 时同步发布给已鉴权的 WebSocket 客户端。

iOS App 扫描 macOS 设置页二维码后保存连接信息。前台时，iOS 通过 WebSocket 订阅状态快照，驱动 App 内刘海屏、会话列表和 Live Activity 内容更新。Live Activity 只跟随 iOS App 已收到的状态变化，不承诺在 App 被系统挂起或杀掉后继续可靠更新。

## macOS 端设计

新增 `LANStatusServer`，职责是监听本机端口、处理 `/stream` WebSocket 连接、校验 token、维护客户端列表、广播状态快照。它不读取 `~/.codex`，只接收上层传入的展示快照。

新增 `PairingStore`，职责是生成和持久化随机 token，提供 token 重置能力，并生成二维码 payload。token 存在 macOS App 自身配置域，不写入 `~/.codex`。

扩展设置页，新增局域网连接区域：显示服务开关、连接地址、二维码、token 重置按钮、手动输入所需 host/port/token，以及“仅同局域网前台实时”的说明。

macOS 状态服务发送的是安全展示模型，不直接暴露 `CodexSession` 全字段。第一版字段包括 `id`、`displayTitle`、`cwdHint`、`status`、`attention`、`activityText`、`updatedAt`。默认不发送 `latestMessage`。

## iOS 端设计

iOS App 新增扫码配对页，扫描 `codexnotch://pair?host=...&port=...&token=...&v=1`，保存连接信息；扫码失败或 Mac IP 变化时允许手动输入。

主页顶部是 App 内刘海屏：展示聚合状态、当前优先会话、完成数和连接状态。下方列表展示最近会话、项目名、状态、注意力原因和活动时间。连接异常时，主页明确显示未配对、连接中、离线、鉴权失败、协议版本不兼容或 Mac 服务关闭。

Live Activity 由 iOS App 在前台收到运行中任务状态后启动或更新。Dynamic Island compact/minimal 展示状态点和短标题，expanded 展示当前任务、项目名、状态和完成数，锁屏展示更完整的会话摘要。任务全部变绿或连接断开达到结束条件时，iOS 结束或降级 Live Activity。

## 通信协议

二维码 payload 使用自定义 URL：`codexnotch://pair?host=<host>&port=<port>&token=<token>&v=1`。

WebSocket 入口为 `ws://<host>:<port>/stream?token=<token>&v=1`。macOS 校验 token 和协议版本。校验失败时关闭连接，iOS 显示重新配对提示。

连接成功后，macOS 立即发送完整 snapshot。之后当展示快照变化时继续推送 snapshot。snapshot 顶层字段为 `version`、`sentAt`、`aggregateStatus`、`lastUpdatedAt`、`sessions`、`errorMessage`。协议保留 `version`，后续新增字段必须向后兼容。

iOS 断线后进入离线态并使用指数退避重连。鉴权失败和协议不兼容不自动无限重试，要求用户重新扫码或检查 Mac 端设置。

## 隐私与权限

macOS 端继续保持对 `~/.codex` 的只读边界。局域网服务只暴露展示模型，不发送完整 cwd、用户正文、助手正文、工具输出或原始 jsonl。

iOS 访问局域网会触发本地网络隐私权限，需要在 `Info.plist` 中提供清晰用途说明。第一版不使用 Bonjour 自动发现，因此不需要为服务发现增加额外范围。

## 错误处理

macOS 端口被占用时，设置页显示服务启动失败和建议操作，不影响原 macOS 刘海功能。

token 重置后，旧连接应在下一次请求或推送前失效。iOS 收到鉴权失败后清理当前连接状态，但保留手动重新配对入口。

Mac 地址变化、iPhone 不在同一 Wi-Fi、系统本地网络权限被拒绝时，iOS 显示明确离线原因和重新连接入口。

## 验收方式

- Mac 启动局域网状态服务后，设置页能显示二维码和手动连接信息。
- iPhone 扫码后能保存连接并进入主页。
- iOS App 前台时，macOS Codex 状态变化能在 App 内刘海屏和会话列表中实时更新。
- 有运行中任务时，iOS 能启动或更新 Live Activity，并在 Dynamic Island / 锁屏展示当前状态。
- 关闭 Mac 服务、断开网络或切换 Wi-Fi 后，iOS 显示离线态并自动退避重连。
- macOS 重置 token 后，旧 iOS 连接失效，重新扫码后恢复。
- 传输数据不包含完整用户正文、助手正文、完整 cwd 或 jsonl 原始事件。

## 后续阶段

第二阶段可以评估 APNs / ActivityKit push token / 服务端链路，用于后台、锁屏和 App 被杀后的可靠完成提醒。

第三阶段可以评估 Bonjour 自动发现、多个 Mac 管理、状态历史记录和可选摘要同步开关。

## 参考

- Apple ActivityKit: https://developer.apple.com/documentation/ActivityKit/
- Apple Displaying live data with Live Activities: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- Apple URLSessionWebSocketTask: https://developer.apple.com/documentation/foundation/urlsessionwebsockettask
- Apple TN3179 Understanding local network privacy: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
