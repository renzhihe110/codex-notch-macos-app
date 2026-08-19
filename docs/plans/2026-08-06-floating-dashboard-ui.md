# Floating Dashboard UI Implementation Plan

> **执行方式：** 使用 `$gr-execute` 按此 Plan 实施并更新状态。

## 目标
将 macOS App 的悬浮模式入口改为精确复用 DockCat 默认猫咪素材的透明可拖动入口：绿色状态展示休息猫、黄色状态以 3fps 播放四帧走路动画、红色状态展示站立提醒猫；移除现有圆形底、光环和状态点。点击猫咪在当前屏幕居中打开或收起原单列 Dashboard，悬停不触发窗口。

## 架构
保留现有 `NotchView` 与 `NotchWindowController` 的刘海居中路径，在 `isPresentedFromCapsule` 为真时继续显示悬浮模式专用 Dashboard。`CodexStoreReader` 继续从只读 Codex 状态库增量汇总今日 Token，同时按线程最后活动时间降序读取可见任务；`CodexSession` 继续区分创建时间与最后活动时间，后者决定悬浮任务顺序和活动时间文案，前者仅保留为原始元数据。会话尾部状态摘要忽略不改变任务生命周期的中性元数据事件，保留最近有效的开始、执行或终止事件。`StatusBarItemController` 只根据 `NotchState.aggregateStatus` 选择本地 DockCat 素材并管理黄色四帧动画，不复制 DockCat 的渲染器或动画实现。点击猫咪通过 `AppMain` 切换一个正常尺寸、当前屏幕居中的 Dashboard；悬浮路径不再保留侧向锚定、连接段、悬停展开或移出收起状态。SwiftPM 资源包承载 PNG 与完整第三方许可证，打包脚本将资源包一并放入 `.app`。

## 全局约束
- 保护工作区已有 staged、unstaged 与 untracked 改动；只修改本 Plan 列出的直接相关文件，不覆盖用户现有实现。
- 不写测试代码，不自动编译、构建、打包、提交或推送。
- 新增实现段落添加职责注释；保持现有 Swift/AppKit/SwiftUI 代码风格，不做无关重构或抽象。
- Codex 状态库与 rollout 始终只读；不读取或展示对话正文以外的新敏感内容，不输出 rollout 路径。
- Token 统计按系统本地日历的 00:00 至当前时间计算；原始 `inputTokens` 包含缓存输入，底部摘要的“输入”展示 `inputTokens`、“其中缓存”展示 `cachedInputTokens`、“输出”展示 `outputTokens`、“总”展示 `totalTokens`；排他的 `nonCachedInputTokens = inputTokens - cachedInputTokens` 继续保留在数据契约中但不单独展示。
- 单个 rollout 缺失、损坏、字段异常或累计计数回退时，整条线程不计入汇总并返回聚合错误提示，禁止保留该线程的部分统计。
- Token 游标缓存仅驻留内存；本地日期变化、文件缩短或 rollout 路径变化时丢弃对应缓存并从头建立新基线。
- Dashboard 继续使用系统字体和 SF Symbols；悬浮入口只增加用户已确认的 DockCat 位图，不引入其他视觉依赖。
- DockCat 唯一上游仓库为 `https://github.com/Auwuua/DockCat`，图片固定取自 commit `9dd4c4b678c68d7f5eb987ae9f284093e9d0d58d`；仅原样复制 `loaf.png`、`stand.png` 与 `walk_01.png` 至 `walk_04.png`，不修改图片像素，文件 SHA-256 必须与本 Plan 的资源验证清单一致。本项目只在运行时做等比缩放、贴底对齐、状态映射和逐帧播放，这些使用方式必须写入归属说明。
- 由于上游使用 PolyForm Noncommercial 1.0.0，本 App 引入这些素材后限定为非商业用途；仓库与分发 `.app` 必须保留完整许可证、上游链接、来源版本、复制文件和本项目使用方式说明。

## 范围
- 悬浮入口继续支持三档尺寸、拖动、点击、右键菜单和 tooltip；外观改为透明背景的 DockCat 猫咪，不保留圆形底、光环或独立状态点。
- 绿色聚合状态展示 `loaf.png` 休息猫，黄色聚合状态循环播放 `walk_01...04.png` 四帧走路动画（3fps），红色聚合状态展示 `stand.png` 站立提醒猫；状态变化时立即切图并正确启停动画计时器。
- 点击猫咪切换当前屏幕居中的正常尺寸 Dashboard；悬停只保留系统命中与 tooltip，不打开窗口，拖动猫咪不带动已展开的居中窗口。
- 悬浮模式展开窗口继续使用深蓝玻璃质感单列布局，包含标题栏、全宽任务行和底部 Token 摘要；移除侧向连接视觉和左右停靠几何。
- 标题栏图钉控制常驻/自动收起，齿轮打开现有设置页，关闭按钮立即收起面板。
- 底部 Token 摘要使用真实累计值，按“输入 X，其中缓存 Y；输出 Z；总 T”单行展示；`输入` 使用包含缓存的 `inputTokens`，数值使用最多两位小数的 M/K 紧凑单位，统计不完整时追加不含路径的短警告。
- 主区按最后活动时间降序固定展示最近活跃的 5 条真实任务，不显示“任务队列”标题、计数角标、分组背景或展开按钮；任务行高保持 54pt，标题保持 19.5pt medium，副标题和状态保持 15pt regular，副标题单行组合最新消息、项目名和最后活动相对时间，点击继续使用现有跳转路由。
- 更新设置页与 README 中面向用户的“胶囊”文案和悬浮模式说明。
- 增加 SwiftPM 本地图片资源、完整 DockCat 第三方许可证、来源/修改说明，并让现有打包脚本携带资源包。

## 非目标
- 不调整刘海居中模式的收起态、展开态、热键大窗口和键盘导航布局。
- 不调整任务完成提醒弹窗或系统通知。
- 不新增历史日/周/月统计、费用估算、模型排行、筛选、搜索、分页或独立详情窗口。
- 不保留 Token 环、三项统计卡、使用详情切换、任务列表标题/分组或 5/8 展开交互。
- 不持久化面板常驻状态、展开详情状态、任务展开状态或用户拖动位置。
- 不新增 DockCat 六张确认图片以外的第三方图标、字体、图片或视觉依赖。
- 不复制 DockCat 的 Swift 渲染、动画或偏好设置代码，不新增网络下载、换肤、用户导入猫咪、帧率设置或新的持久化键。
- 不改变现有三档入口尺寸、窗口尺寸、Token 摘要、任务行高、字号、字重或状态标签。
- 不把非商用素材用于商业分发；若后续需要商业用途，必须先替换素材或另行取得授权。

## 验收标准
- [ ] 悬浮模式入口为透明背景的可拖动 DockCat 猫咪，三档尺寸均继续生效；圆形底、蓝紫光环和状态点均不存在，点击/拖动/右键/tooltip 保持可用。
- [ ] 绿色状态静态显示休息猫，黄色状态以 3fps 循环四帧走路猫，红色状态静态显示站立提醒猫；执行中的中性元数据事件不会把黄色误判为绿色，只有明确完成或中止才退出运行态；离开黄色状态后动画计时器停止且不残留旧帧。
- [ ] 单击猫咪在猫咪所在屏幕居中打开正常尺寸 Dashboard，再次单击收起；悬停和移出都不改变窗口显隐，拖动猫咪不改变已展开窗口的居中位置。
- [ ] 居中 Dashboard 完整夹在当前屏幕可见区域内，不显示侧向连接段，不保留左右停靠方向或入口锚点定位状态。
- [ ] 悬浮面板保留标题栏和深色圆角背景，外壳参考用户图二使用完整黑色填充与内收中性细边线，不绘制会超出窗口并被裁切的外阴影或蓝紫渐变描边；主区为无分组容器的全宽任务行，底部为单行 Token 摘要，刘海居中模式仍走原布局。
- [x] 今日 Token 总量及非缓存输入、缓存输入、输出均来自本机真实累计计数增量，按本地 00:00 重置，四项关系与占比一致且无重复计数。
- [x] Token 读取遇到缺失、损坏、字段异常或累计回退时不会显示部分线程结果，并以不含路径或正文的短错误反馈统计不完整。
- [x] 底部摘要按“输入 X，其中缓存 Y；输出 Z；总 T”展示真实值，主区按最后活动时间降序只显示最近活跃的 5 条 54pt 任务行，标题 19.5pt，副标题/状态 15pt，副标题组合最新消息、项目名和最后活动相对时间，任务行点击仍打开对应 Codex 任务。
- [ ] 图钉开启时窗口失焦或外部点击不会自动收起，再次点击恢复原自动收起；设置与关闭按钮分别打开设置页和收起面板，悬停移出在固定与非固定状态下都不控制显隐。
- [x] 设置页和 README 使用“悬浮球/悬浮模式”说明，不影响完成弹窗、iOS 与局域网功能接口。
- [x] 最终 scoped diff 只包含本 Plan 与列明文件，无无关重构、测试、构建产物或用户改动覆盖。
- [ ] DockCat 六张图片与 `https://github.com/Auwuua/DockCat` 指定 commit/SHA-256 一致且像素未修改；仓库和用户实际打包后的 `.app` 均包含完整 PolyForm Noncommercial 1.0.0 许可证及清晰归属/使用说明，README 明确非商业限制。

## Evidence Mode
- final-only

## 文件职责
- Create: `docs/plans/2026-08-06-floating-dashboard-ui.md` — 本次完整通道的计划、审批、Evidence 与 Review 交接物。
- Modify: `Sources/CodexNotch/Models.swift` — 定义今日 Token 汇总模型，让 `NotchState` 持有该数据，并让 `CodexSession` 区分创建时间与最后活动时间。
- Modify: `Sources/CodexNotch/CodexStoreReader.swift` — 让 `CodexStoreSnapshot` 持有汇总，只读发现今日活跃 rollout、增量流式解析累计 Token 事件并形成可靠统计，同时按线程最后活动时间降序读取可见会话。
- Modify: `Sources/CodexNotch/StatusMapper.swift` — 把读取快照中的 Token 汇总映射到 `NotchState`，并在状态映射时原样保留会话创建时间。
- Modify: `Sources/CodexNotch/AppMain.swift` — 将猫咪单击接到居中 Dashboard toggle，并移除悬停移出收起回调链。
- Modify: `Sources/CodexNotch/NotchView.swift` — 维护单列 Dashboard，并删除悬浮路径的连接段、方向和偏移状态。
- Modify: `Sources/CodexNotch/NotchWindowController.swift` — 管理悬浮面板正常尺寸居中 toggle、常驻与外部点击收起，删除侧向停靠和猫咪锚点跟随。
- Modify: `Sources/CodexNotch/StatusBarItemController.swift` — 加载 DockCat 本地资源，根据聚合状态切换静态猫或 3fps 动画，并保留拖动、点击、右键和 tooltip。
- Modify: `Sources/CodexNotch/CapsuleSettings.swift` — 将现有三档入口尺寸改为正方形悬浮球尺寸，不迁移持久化键。
- Modify: `Sources/CodexNotch/SettingsView.swift` — 将入口配置的可见文案改为悬浮球语义。
- Modify: `README.md` — 同步悬浮模式外观、内容与交互说明。
- Modify: `design-qa.md` — 更新修订布局的运行截图对照和最终 QA 状态。
- Modify: `Package.swift` — 声明 `Sources/CodexNotch/Resources` 为 SwiftPM 资源。
- Create: `Sources/CodexNotch/Resources/DockCat/loaf.png` — DockCat 默认绿色休息态素材。
- Create: `Sources/CodexNotch/Resources/DockCat/stand.png` — DockCat 默认红色站立提醒素材。
- Create: `Sources/CodexNotch/Resources/DockCat/walk_01.png` 至 `walk_04.png` — DockCat 默认黄色走路动画四帧素材。
- Create: `Sources/CodexNotch/Resources/DockCat/LICENSE.txt` — 随运行资源分发的完整 PolyForm Noncommercial 1.0.0 许可证。
- Create: `THIRD_PARTY_NOTICES.md` — 记录 DockCat 唯一上游链接、来源 commit、许可证、原样复制文件，以及仅在运行时缩放/贴底/状态映射/逐帧播放的使用说明。
- Modify: `scripts/package_app.sh` — 将 SwiftPM 生成的 CodexNotch 资源 bundle 复制进 `.app/Contents/Resources`。

## Tasks

### Task 1: 可靠的今日 Token 展示数据
**Status:** completed

**Files:**
- Modify: `Sources/CodexNotch/Models.swift`
- Modify: `Sources/CodexNotch/CodexStoreReader.swift`
- Modify: `Sources/CodexNotch/StatusMapper.swift`
- Modify: `Sources/CodexNotch/AppMain.swift`

**Interfaces:**
- Consumes: Codex `threads` 状态库中的 `id`、`rollout_path`、`created_at`、`updated_at` 字段，以及 rollout 的 `event_msg.payload.type == token_count`、`info.total_token_usage` 累计字段。
- Produces: 仅桌面 UI 使用的 `TodayTokenUsage` 汇总和安全错误状态；现有 `CodexSession`、LAN payload 与 iOS 模型不变。

- [x] **Step 1: 定义排他的今日 Token 汇总模型**
  - Action: 在 `Models.swift` 新增带总输入、缓存输入、输出、总量、完整性和短错误信息的值类型，提供非缓存输入与占比的安全计算并加入 `NotchState`；在 `CodexStoreReader.swift` 把同一汇总加入其现有 `CodexStoreSnapshot`。
  - Expected: UI 不自行解释原始字典，零总量时占比不会除零，缓存输入不会与输入重复展示。
- [x] **Step 2: 从状态库发现今天可能贡献 Token 的线程**
  - Action: 在 `CodexStoreReader` 复用当前选中的只读状态库，按实际字段组合使用 `updated_at_ms`/`updated_at` 和 `created_at_ms`/`created_at`，以对应的毫秒或秒本地日界筛选今天有更新且当前时间前创建的全部线程；解析绝对或相对 `rollout_path`，路径缺失只计聚合错误数。
  - Expected: 今日已归档或超过任务列表 8 条限制的线程仍进入 Token 统计，旧日且今天无更新的线程不会被扫描。
- [x] **Step 3: 流式计算每个 rollout 的累计 Token 增量**
  - Action: 以固定大小数据块逐行处理只含 `token_count` 标记的事件，验证时间戳、非负整数、`input + output == total`、`cached <= input` 和累计单调性；以同一线程上一条累计值为基线，仅汇总今日事件增量，先缓存单线程结果后再并入总量，并容忍仍在写入的最后半行。
  - Expected: 跨日长任务只统计今日发生的增量，重复累计快照不会重复计数，异常线程不会留下部分贡献，日志正文不会整体载入内存。
- [x] **Step 4: 缓存每个 rollout 的增量解析游标**
  - Action: 按线程和 rollout 路径保存当前本地日期、已消费字节偏移、残留半行、最近累计计数、今日贡献和有效性；文件增长时只处理新增字节，日期变化、文件缩短或路径变化时安全重建，已经损坏的线程只在文件状态变化后重试。
  - Expected: 一秒状态刷新不会重复扫描完整 rollout，Token 展示仍能在新增事件写入后更新。
- [x] **Step 5: 接入现有一秒刷新链路**
  - Action: `loadSnapshot()` 同时返回任务与今日 Token 汇总，缓存回退时保留最后成功 Token 值但标记不完整；`StatusMapper` 和 App 初始状态把数据交给桌面 UI，不修改 LAN 映射。
  - Expected: 悬浮面板随现有轮询更新真实 Token，其他消费者保持接口和行为兼容。

### Task 2: 圆形悬浮入口与侧向停靠窗口
**Status:** completed

**Files:**
- Modify: `Sources/CodexNotch/CapsuleSettings.swift`
- Modify: `Sources/CodexNotch/SettingsView.swift`
- Modify: `Sources/CodexNotch/StatusBarItemController.swift`
- Modify: `Sources/CodexNotch/NotchWindowController.swift`

**Interfaces:**
- Consumes: 现有 `NotchState.aggregateStatus`、三档入口设置、入口锚点 frame 和自动收起事件。
- Produces: 正方形悬浮球 frame、左右连接方向、常驻状态及悬浮 Dashboard 的稳定屏幕定位。

- [x] **Step 1: 把三档胶囊尺寸改为圆形悬浮球尺寸**
  - Action: 保留 `CapsuleSettings` 的持久化键和枚举 rawValue，只把三档 dimensions 改为正方形并更新设置页可见标题，避免用户设置迁移。
  - Expected: 已保存的 compact/regular/large 继续生效，入口不再包含胶囊短文案。
- [x] **Step 2: 重绘原生 Codex 圆形入口**
  - Action: 在 `StatusBarItemController` 的现有 NSControl 中绘制参考图同风格的深色圆形底、蓝紫光环、原生 Codex/SF Symbol 图标和当前状态反馈；保留拖动阈值、悬停、点击、右键和 tooltip 回调。
  - Expected: 入口外观变为圆形但原控制器事件路径不变，不引入位图或第三方依赖。
- [x] **Step 3: 增加悬浮面板左右停靠几何**
  - Action: 在 `NotchWindowMetrics` 定义参考图比例的固定 Dashboard 卡片、透明连接区和安全边距；胶囊模式优先把面板放在入口右侧，空间不足时放在左侧并更新视图连接方向，最终夹在入口所在屏幕可见区域内。
  - Expected: 默认位置和拖动后展开都不会越过菜单栏、Dock 或屏幕边缘，连接段始终朝向圆形入口。
- [x] **Step 4: 接入常驻与显式关闭状态**
  - Action: 给 `NotchViewModel`/控制器增加运行期常驻状态；常驻时跳过失焦、外部点击和鼠标移出收起，显式关闭、切换显示模式和应用退出仍正常生效。
  - Expected: 图钉可逆切换，不持久化且不破坏原悬停状态机。

### Task 3: 参考图双栏悬浮 Dashboard
**Status:** completed

**Files:**
- Modify: `Sources/CodexNotch/NotchView.swift`
- Modify: `Sources/CodexNotch/NotchWindowController.swift`
- Modify: `Sources/CodexNotch/AppMain.swift`

**Interfaces:**
- Consumes: `NotchState.todayTokenUsage`、最多 8 个 `CodexSession`、左右连接方向、常驻状态和现有打开任务/设置回调。
- Produces: 仅 `isPresentedFromCapsule == true` 时显示的可交互双栏 Dashboard；刘海与热键布局不变。

- [x] **Step 1: 隔离悬浮模式专用根布局**
  - Action: 在 `NotchView` 根视图按展示来源分支；悬浮模式使用带透明连接区的固定 Dashboard，刘海居中与热键展开继续使用现有 header/list/scale 路径。
  - Expected: 悬浮设计不改变刘海现有尺寸计算、键盘选择和列表滚动。
- [x] **Step 2: 实现标题栏和真实按钮状态**
  - Action: 使用 SF Symbols 与现有回调实现 Codex 标识、标题、图钉选中态、设置和关闭按钮，补齐 hover/help/命中区域。
  - Expected: 三个按钮行为与验收标准一致，图钉状态可见且键鼠可点击。
- [x] **Step 3: 实现今日 Token 左栏**
  - Action: 按参考图实现标题、重置说明、环形总量、输入/输出/缓存卡片、占比和详情切换；零数据与不完整数据使用明确但紧凑的原生空态/错误态。
  - Expected: 所有数值来自 `TodayTokenUsage`，格式化和占比在极端数值下不溢出布局。
- [x] **Step 4: 实现任务队列右栏**
  - Action: 默认取前 5 条会话，点击“查看全部任务”后取前 8 条并在固定区域内滚动；任务卡片展示现有标题、活动时间和由 status/attention 映射的真实状态标签，整行点击复用 `onSelectSession`。
  - Expected: 状态颜色、标签、选中反馈和跳转行为一致，不伪造排队状态或任务内容。
- [x] **Step 5: 完成视觉层级与边界状态**
  - Action: 使用深蓝半透明背景、蓝紫描边、内层卡片、阴影和参考图间距统一悬浮 Dashboard；验证无任务、零 Token、统计不完整、长标题、8 条任务和左右连接方向的静态布局分支。
  - Expected: 面板信息密度和层级接近参考图，文本截断、滚动和空态不会破坏固定尺寸。

### Task 4: 用户说明与最终范围核对
**Status:** completed

**Files:**
- Modify: `README.md`
- Modify: `docs/plans/2026-08-06-floating-dashboard-ui.md`

**Interfaces:**
- Consumes: 最终悬浮入口、Dashboard 内容和交互行为。
- Produces: 与实现一致的用户说明、最终 Evidence 和 Review 输入。

- [x] **Step 1: 更新悬浮模式说明**
  - Action: 将 README 中胶囊外观与旧展开面板说明更新为圆形悬浮球、真实 Token 双栏 Dashboard、常驻按钮和任务展开行为；保留运行、打包和其他功能说明。
  - Expected: 文档不再描述已移除的胶囊短状态文案。
- [x] **Step 2: 做范围内静态 Review 并回填最终 Evidence**
  - Action: 核对需求匹配、Token 统计正确性、状态机兼容性、错误处理、安全、脏工作区保护和范围蔓延；仅返修范围内明确问题，再执行最终验证并更新 Plan。
  - Expected: Review 输入只包含本 Plan 的 scoped diff，Evidence 晚于最后相关改动。

### Task 5: 单列任务与底部 Token 摘要修订
**Status:** completed

**Files:**
- Modify: `Sources/CodexNotch/NotchView.swift`
- Modify: `README.md`
- Modify: `design-qa.md`
- Modify: `docs/plans/2026-08-06-floating-dashboard-ui.md`

**Interfaces:**
- Consumes: `NotchState.todayTokenUsage`、`NotchState.sessions.prefix(5)` 和现有 `onSelectSession` 跳转回调。
- Produces: 固定 5 条的全宽任务列表与单行真实 Token 摘要；不改数据模型、读取器或窗口控制器接口。

- [x] **Step 1: 移除双栏与任务分组状态**
  - Action: 在 `NotchView` 的悬浮根布局中删除 Token 左栏、使用详情状态、任务标题/角标、分组背景、“查看全部”按钮和 5/8 展开状态，保留标题栏及外壳。
  - Expected: 悬浮面板不再存在 Token 卡片或任务队列 group，内容变为单列结构。
- [x] **Step 2: 放大并固定最近 5 条任务行**
  - Action: 主区直接遍历 `sessions.prefix(5)`，任务行高固定为 54pt，标题 13pt，副标题与状态标签 10pt，保留任务类型图标、真实时间/状态、单行截断和整行跳转。
  - Expected: 五条数据充足时无裁切地填充主区，数据不足时展示紧凑空态，超过五条不提供展开入口。
- [x] **Step 3: 新增底部单行 Token 摘要**
  - Action: 在面板底部使用 `inputTokens`、`cachedInputTokens`、`outputTokens` 和 `totalTokens` 生成“输入 X，其中缓存 Y；输出 Z；总 T”，使用最多两位小数的 M/K 紧凑格式和等宽数字；统计不完整时追加短警告并保留最后成功值。
  - Expected: 摘要始终单行且数值关系与 `TodayTokenUsage` 一致，不显示占比、圆环、统计卡或详情按钮。
- [x] **Step 4: 同步说明与 QA 基线**
  - Action: 将 README 的双栏、Token 左栏和 5/8 展开说明改为单列五条任务和底部 Token 摘要；更新 `design-qa.md` 的新布局基线，并将用户重新运行后的截图保留为独立运行验收门禁。
  - Expected: 用户文档不再描述已移除的双栏与展开交互，QA 在缺少新布局运行截图时保持 blocked。

### Task 6: 最近新建任务排序与列表字号修订
**Status:** completed

**Files:**
- Modify: `Sources/CodexNotch/Models.swift`
- Modify: `Sources/CodexNotch/CodexStoreReader.swift`
- Modify: `Sources/CodexNotch/StatusMapper.swift`
- Modify: `Sources/CodexNotch/NotchView.swift`
- Modify: `design-qa.md`
- Modify: `docs/plans/2026-08-06-floating-dashboard-ui.md`

**Interfaces:**
- Consumes: `threads.created_at_ms/created_at`、`threads.updated_at_ms/updated_at`、现有 `CodexSession` 状态字段及五条悬浮任务行。
- Produces: 内部 `CodexSession.createdAt` 字段、按创建时间降序的最近五任务，以及放大 50% 的任务文本；不修改 LAN/iOS payload。

- [x] **Step 1: 区分创建时间与最后活动时间**
  - Action: 为内部 `CodexSession` 增加 `createdAt`；SQLite 同时读取规范化的创建时间和最后活动时间，按创建时间降序并以线程 ID 稳定打破同时间并列；索引回退缺少独立创建字段时复用其单条索引时间，`StatusMapper` 原样传递 `createdAt`。
  - Expected: 昨天创建但今天重新活动的旧任务不会挤掉今天更晚创建的任务，状态停滞判断仍使用 `updatedAt`。
- [x] **Step 2: 放大任务文本并展示创建时间**
  - Action: 将悬浮任务标题从 13pt 增加至 19.5pt，副标题和状态从 10pt 增加至 15pt，状态胶囊高度从 22pt 增加至 28pt；行高继续保持 54pt，副标题时间改用 `createdAt`，保留单行截断和整行点击。
  - Expected: 三类任务文字相对当前截图均精确放大 50%，五条任务仍完整处于 294pt 主区，显示时间与创建时间降序一致。
- [x] **Step 3: 更新失败截图记录**
  - Action: 在 `design-qa.md` 记录当前截图暴露的字号与排序问题，并保留修订后截图为运行验收门禁。
  - Expected: 当前截图不会被当成通过证据，下一次视觉比较明确检查 19.5/15pt 密度和最近新建五任务。

### Task 7: DockCat 三态入口与居中 Dashboard
**Status:** completed

> Task 7 明确替代 Task 2/3 中已完成的圆形绘制、悬停展开、侧向停靠和连接视觉；Task 1、5、6 的数据与单列内容继续沿用。Validation 2/5 是旧版本历史 Evidence，不作为 v4 验收结论。

**Files:**
- Modify: `Package.swift`
- Create: `Sources/CodexNotch/Resources/DockCat/loaf.png`
- Create: `Sources/CodexNotch/Resources/DockCat/stand.png`
- Create: `Sources/CodexNotch/Resources/DockCat/walk_01.png` 至 `walk_04.png`
- Create: `Sources/CodexNotch/Resources/DockCat/LICENSE.txt`
- Create: `THIRD_PARTY_NOTICES.md`
- Modify: `Sources/CodexNotch/StatusBarItemController.swift`
- Modify: `Sources/CodexNotch/AppMain.swift`
- Modify: `Sources/CodexNotch/NotchWindowController.swift`
- Modify: `Sources/CodexNotch/NotchView.swift`
- Modify: `scripts/package_app.sh`
- Modify: `README.md`
- Modify: `design-qa.md`
- Modify: `docs/plans/2026-08-06-floating-dashboard-ui.md`

**Interfaces:**
- Consumes: `NotchState.aggregateStatus`、现有三档悬浮入口尺寸、猫咪拖动/单击/右键事件、当前屏幕可见区域与 DockCat 上游指定 commit 的六张 PNG。
- Produces: 绿色休息、黄色 3fps 四帧走路、红色站立提醒的透明猫咪入口，以及单击切换的当前屏幕居中 Dashboard；不修改任务/Token 数据契约、LAN/iOS 协议或刘海模式。

- [x] **Step 1: 固定上游素材、许可证与资源打包链路**
  - Action: 从唯一上游 `https://github.com/Auwuua/DockCat` 的 commit `9dd4c4b678c68d7f5eb987ae9f284093e9d0d58d` 精确复制 `loaf.png`、`stand.png`、`walk_01...04.png` 和完整 `LICENSE.txt` 到 SwiftPM 资源目录；在 `THIRD_PARTY_NOTICES.md` 与 README 记录上游链接、版本、复制文件、图片像素未修改，以及本项目只在运行时等比缩放/贴底对齐/状态映射/逐帧播放和限定非商业用途；在 `Package.swift` 声明资源，并让 `scripts/package_app.sh` 把 SwiftPM 资源 bundle 与 `THIRD_PARTY_NOTICES.md` 放入 `.app/Contents/Resources`。
  - Expected: 运行与打包均从本地资源读取，无网络依赖；六张图片哈希与上游固定版本一致，仓库和分发物都保留完整许可证与归属信息。
- [x] **Step 2: 用三态猫咪替换圆形悬浮球绘制**
  - Action: 将 `StatusPillView` 改为透明背景、按比例完整显示并贴底对齐的猫咪图片视图；删除圆形底、蓝紫光环、内部 Codex 符号、闪烁逻辑和独立状态点。`StatusBarItemController` 使用 `Bundle.module` 加载资源，绿色选择休息猫，黄色以 `1/3s` 计时循环四帧走路图，红色选择站立猫；状态切换和控制器销毁时停止不需要的计时器。
  - Expected: 猫咪在 compact/regular/large 三档方形窗口内无拉伸或裁切，背景透明；黄色动画稳定 3fps，绿色/红色无无效动画唤醒，状态变化不会残留上一状态的帧或圆形视觉。
- [x] **Step 3: 保留猫咪直接操作并取消悬停展开**
  - Action: 保留现有拖动阈值、按压反馈、右键菜单、tooltip 和三档尺寸；移除入口 tracking area 的悬停打开、延迟 work item 与鼠标移出回调。单击只发出 toggle，拖动只更新猫咪自身位置，不触发点击也不重定位已展开面板。
  - Expected: 悬停或移出猫咪不改变 Dashboard 显隐；单击、拖动、右键互不串扰，且不再绘制状态点作为命中或状态反馈。
- [x] **Step 4: 将悬浮 Dashboard 改为当前屏幕居中 toggle**
  - Action: 在 `AppMain` 将猫咪点击接到新的悬浮 Dashboard toggle；在 `NotchWindowController` 让该入口使用正常 `1x` 悬浮卡片尺寸、猫咪所在屏幕的 `visibleFrame` 居中位置和 `tracksMouseExit = false`，再次点击收起。删除悬浮路径的 anchor frame 跟随、左右停靠选择、连接偏移与连接方向；保留外部点击、Escape、关闭按钮和图钉既有语义，并保持键盘热键的 `2x` 居中路径与刘海模式不变。
  - Expected: 单击猫咪居中打开 460×396 Dashboard，再次单击收起；移动猫咪不移动已展开面板，面板无连接段且不越过菜单栏/Dock；热键大窗口和刘海入口仍走原尺寸与定位。
- [x] **Step 5: 同步文档和运行期 QA 门禁**
  - Action: 更新 README 与 `design-qa.md`，明确三态映射、黄色 3fps 动画、无光环/状态点、点击居中 toggle、非商业许可与需要人工重新运行检查的状态；最终只做静态检查，不自动编译。
  - Expected: 文档与实现无旧圆形球、侧向停靠、连接段或悬停打开描述；在用户提供绿色/黄色/红色与居中窗口证据前，运行期视觉验收保持 pending。

### Task 8: 悬浮 Dashboard 外壳边缘修订
**Status:** completed

**Files:**
- Modify: `Sources/CodexNotch/NotchView.swift`
- Modify: `design-qa.md`
- Modify: `docs/plans/2026-08-06-floating-dashboard-ui.md`

**Interfaces:**
- Consumes: 用户运行截图 `codex-clipboard-b8e413cb-9698-48b8-9937-9e8d4b169b13.png` 与参考截图 `codex-clipboard-b754c5fb-46dd-4606-bae4-a842350fd896.png`。
- Produces: 不超出 460×396 `NSWindow` 的黑色圆角外壳和内收细边线；不修改窗口尺寸、任务布局、Token、猫咪或交互状态。

- [x] **Step 1: 移除被窗口裁切的外扩视觉**
  - Action: 删除 `floatingCard` 外壳的两层外阴影、蓝紫渐变描边和第二层内描边，只保留完整黑色圆角填充。
  - Expected: 外壳不再向 `NSWindow` 边界外绘制，四边不会因裁切产生不均匀蓝紫亮线。
- [x] **Step 2: 使用内收边线和同形圆角裁切**
  - Action: 参考图二为相同 `RoundedRectangle` 增加内收的中性 `strokeBorder`，并用同一圆角形状裁切卡片内容。
  - Expected: 四个圆角和四条边线连续、对称，背景外区域透明，任务行和底部摘要位置不变。
- [x] **Step 3: 更新失败截图和静态证据**
  - Action: 在 `design-qa.md` 记录外阴影裁切根因与修订规格，执行 scoped `git diff --check` 和反向搜索，等待用户重新运行截图确认。
  - Expected: 静态实现不存在悬浮外壳 `.shadow` 或渐变描边，运行视觉验收在新截图前保持 pending。

### Task 9: 恢复最近活动任务和正确行内容
**Status:** completed

**Files:**
- Modify: `Sources/CodexNotch/CodexStoreReader.swift`
- Modify: `Sources/CodexNotch/Models.swift`
- Modify: `Sources/CodexNotch/NotchView.swift`
- Modify: `README.md`
- Modify: `design-qa.md`
- Modify: `docs/plans/2026-08-06-floating-dashboard-ui.md`

**Interfaces:**
- Consumes: SQLite `threads.updated_at_ms`/`updated_at`、已有 `CodexSession.latestMessage`、`cwdHint`、`activityText` 和用户提供的正确/错误列表截图。
- Produces: 在读取层按最后活动时间倒序截取的真实会话，以及不改变 54pt 行高的“标题 + 最新消息/项目名/活动时间”悬浮任务行；Token、状态映射、窗口与猫咪接口不变。

- [x] **Step 1: 在读取截断前恢复最后活动时间排序**
  - Action: SQLite 可见会话查询继续读取创建时间，但将 `ORDER BY` 恢复为规范化最后活动时间倒序，并以 ID 作稳定次序后再应用既有 `LIMIT`。
  - Expected: 最近活跃但创建较早的任务不会在进入 UI 前被排除，查询前五项与图一的最近活动语义一致。
- [x] **Step 2: 悬浮副标题复用正确会话字段**
  - Action: 保留标题、状态标签、19.5/15pt 字号和 54pt 行高，将原“创建时刻 · 状态”替换为单行“最新消息 · 项目名 · 最后活动相对时间”；没有最新消息时只显示项目名与活动时间。
  - Expected: 图二不再把创建时刻误当任务内容，已有 `latestMessage`、`cwdHint`、`activityText` 都进入悬浮行且长文本继续单行截断。
- [x] **Step 3: 静态验证排序边界和视图字段**
  - Action: 用只读 SQLite 对比最后活动排序与读取上限，正向核对悬浮副标题字段并反向确认悬浮行不再引用 `createdAt`；执行 scoped `git diff --check`，不编译。
  - Expected: 当前活动排名前五与图一一致，活动排名第 1/创建排名第 9 的任务能够进入八条读取结果，变更只涉及列明文件。

### Task 10: 保留执行期有效状态
**Status:** completed

**Files:**
- Modify: `Sources/CodexNotch/CodexStoreReader.swift`
- Modify: `docs/plans/2026-08-06-floating-dashboard-ui.md`

**Interfaces:**
- Consumes: rollout 中已有 `task_started`、执行事件、`task_complete`、`turn_aborted`，以及实测出现在活动区间内但不改变生命周期的统计、上下文、压缩、工具结束和子 Agent 元数据事件。
- Produces: 不被中性元数据覆盖的 `CodexSession.lastEvent`；`StatusMapper`、聚合优先级、猫咪动画、LAN/iOS 契约均不改。

- [x] **Step 1: 明确忽略中性元数据事件**
  - Action: 在 `eventType(from:)` 统一取得 payload/外层事件类型后，对真实 rollout 中已验证不改变任务生命周期的中性事件返回 nil，让现有 `lastEvent = currentEventType ?? lastEvent` 保留最近有效状态；带 status 的其他有效事件继续原样输出。
  - Expected: `task_started` 或执行事件之后出现中性元数据时仍保持黄色，且不会把中性事件伪装成新的运行事件。
- [x] **Step 2: 保留明确终止语义**
  - Action: 不忽略 `task_complete` 和 `turn_aborted`，继续让它们覆盖此前运行事件；不改变错误/等待的红色优先级。
  - Expected: 完成或中止后仍退出黄色，错误与等待提醒行为无回归。
- [x] **Step 3: 用真实事件序列做静态重放**
  - Action: 对近期 rollout 在 `task_started` 到 `task_complete`/`turn_aborted` 之间重放过滤规则，确认实测持续 1～54 秒的中性事件窗口均保留前一有效事件；执行 scoped `git diff --check`，不编译。
  - Expected: 静态重放不存在活动区间被中性事件切成绿色的情况，修订只触及列明文件。

## 最终验证
- [x] **Validation 1: Token 数据契约与统计口径**
  - Verify: 使用 `rg` 精确检查 `TodayTokenUsage`、累计增量、日界筛选、字段关系校验、线程级失败隔离和 `NotchState` 映射；结合 scoped diff 人工走查首条累计、跨日、零增量、回退与缺字段分支。
  - Expected: 验收标准中的真实统计、按日重置、排他分类、无重复计数和异常线程隔离均有对应实现，LAN/iOS 契约无改动。
  - Evidence:
    - Check: `rg` 核对 `TodayTokenUsage`、秒/毫秒日界筛选、累计 delta、字段关系、线程级游标/失效隔离及 `StatusMapper` 映射，并人工走查同线程首条、跨日、重复累计、回退、缺字段和聚合溢出分支。
    - Actual: 数据契约保留 `input - cached`、`cached`、`output` 三个排他统计值，v2 底部摘要改为展示包含缓存的 `inputTokens` 并注明“其中缓存”；每个 rollout 先完成自身校验再参与总计，损坏或回退线程整条排除；状态只进入桌面 `NotchState`，LAN/iOS 搜索无引用。
    - Exit Code: 0
    - Revision: scoped-diff-sha256:2f90a00ec9759eed1077340e257a9836e335931d69366203a071583ba93f121b
- [x] **Validation 2: 悬浮入口、窗口状态机与模式隔离**
  - Verify: 使用 `rg` 与 scoped diff 检查圆形尺寸、绘制、拖动/悬停/点击/右键回调、左右停靠、屏幕夹取、连接方向、常驻门禁及显式关闭；确认刘海路径条件和原布局代码仍在。
  - Expected: 圆形入口和面板状态机覆盖全部验收交互，刘海居中模式、完成弹窗与热键路径未被重写。
  - Evidence:
    - Check: `rg` 与 scoped diff 核对正方形三档尺寸、圆形原生图标绘制、拖动/悬停/点击/右键回调、左右停靠、动态连接高度、屏幕夹取、常驻门禁和显式关闭。
    - Actual: `isPresentedFromCapsule` 单独选择 Dashboard；图钉已覆盖失焦、外部点击、悬浮球移出和鼠标轮询四条自动收起路径，显式关闭/Escape/模式切换仍可收起；本次对照返修将默认悬浮球调整为 96×96，面板为 460×396，连接区为 82pt，原刘海布局与 LAN/iOS 文件未纳入修改。
    - Exit Code: 0
    - Revision: scoped-diff-sha256:60652b729c19abe7bc1085683062be6e51a4d35518525965c0809be6c9bd88c9
- [x] **Validation 3: Dashboard 单列内容与底部摘要静态核对**
  - Verify: 使用 `rg` 与 `NotchView` scoped diff 核对悬浮根布局仅包含标题栏、`sessions.prefix(5)` 全宽任务行和底部 Token 摘要；确认 Token 环/卡片/详情状态、任务 group/标题/角标与 5/8 展开状态在悬浮路径中已移除。
  - Expected: 五条任务行的 54/13/10pt 尺寸、真实状态与跳转回调有唯一实现，底部摘要使用包含缓存的输入值与真实总量，无静态示例数据。
  - Evidence:
    - Check: `rg` 核对 `floatingTaskList`、`sessions.prefix(5)`、294pt 主区、54pt 行高、13/10pt 字号、底部摘要四个真实字段与 M/K 两位精度，并反向确认旧 Token/任务分组和展开状态标识不存在。
    - Actual: 悬浮路径只保留标题栏、五条直接任务行和底部摘要；五条任务占用 `5 × 54 + 4 × 6 = 294pt`，输入使用包含缓存的 `inputTokens`，缓存、输出和总量分别使用对应真实字段；任务点击仍调用 `onSelectSession`。
    - Exit Code: 0
    - Revision: implementation-content-sha256:823bb8036a451a808c50f6b7d22bcaa35caf0ee0f00c606aa7fbd2b732732ac1
- [x] **Validation 4: 格式与范围卫生**
  - Verify: 运行 `git diff --check -- Sources/CodexNotch/Models.swift Sources/CodexNotch/CodexStoreReader.swift Sources/CodexNotch/StatusMapper.swift Sources/CodexNotch/AppMain.swift Sources/CodexNotch/NotchView.swift Sources/CodexNotch/NotchWindowController.swift Sources/CodexNotch/StatusBarItemController.swift Sources/CodexNotch/CapsuleSettings.swift Sources/CodexNotch/SettingsView.swift README.md docs/plans/2026-08-06-floating-dashboard-ui.md`，使用 `rg` 确认 README 已描述单列五条任务和底部 Token 摘要且不再描述双栏/5-8 展开，并记录同一文件集的 scoped diff 指纹与状态。
  - Expected: Exit Code 0，无空白错误；最终改动没有测试、构建产物、提交或列明范围外文件。
  - Evidence:
    - Check: 对列明源文件和 README 执行 `git diff --check`，对未跟踪的 Plan/QA 文件检查行尾空白；用 `rg` 确认 README 不含旧双栏/5-8 展开文案，并核对本次四个目标文件状态。
    - Actual: 无空白错误；README 已改为单列五任务和底部真实 Token 摘要；本次修订只触及 `NotchView.swift`、`README.md`、`design-qa.md` 和本 Plan，未新增测试、构建产物、提交或推送。
    - Exit Code: 0
    - Revision: implementation-content-sha256:823bb8036a451a808c50f6b7d22bcaa35caf0ee0f00c606aa7fbd2b732732ac1
- [ ] **Validation 5: 用户运行期视觉与交互验收**
  - Verify: 由于约束禁止自动编译，由用户本机启动 App 后检查默认悬浮球、左右停靠面板、无 group 的五条 54pt 任务行、底部真实 Token 摘要、图钉/设置/关闭和刘海模式回归；如提供运行截图，更新 `design-qa.md` 进行同状态视觉比较。
  - Expected: 运行期布局无裁切或错位，底部摘要始终单行，五条任务行和全部交互符合验收标准；在取得此人工证据前不得声称运行期视觉 QA 已通过。
  - Evidence:
    - Check: 用户提供运行截图 `/var/folders/r8/nfxvrxds17b5p3ncc5_r457h0000gn/T/codex-clipboard-d0b25afd-b8ca-445e-805a-4d034643f74e.png`，人工核对五任务、字号、顺序和底部摘要。
    - Actual: 单列五任务与底部摘要已经运行，但 13/10pt 文字仍明显偏小；列表按最后活动时间排序，导致昨天创建但今天更新的旧任务排在第二并挤掉今天更晚创建的任务，因此运行验收未通过。
    - Exit Code: not applicable
    - Revision: implementation-content-sha256:823bb8036a451a808c50f6b7d22bcaa35caf0ee0f00c606aa7fbd2b732732ac1
- [x] **Validation 6: 创建时间排序与 50% 字号静态核对**
  - Verify: 使用 `rg` 和 scoped diff 核对 `CodexSession.createdAt` 从 SQLite/索引回退贯穿 `StatusMapper` 到悬浮任务行；确认 SQL 使用规范化创建时间降序，`updatedAt` 仍用于状态判断；确认任务标题 19.5pt medium、副标题/状态 15pt regular、状态胶囊 28pt、行高 54pt 和五条 294pt 主区。
  - Expected: 最近五任务的选择与显示时间只使用创建时间，活动状态仍使用最后更新时间；字号、字重与尺寸只有一个实现且无旧 13/10pt 任务字号残留。
  - Evidence:
    - Check: `rg` 核对三个 `CodexSession` 构造点都传入 `createdAt`、SQL 创建时间表达式/降序、`StatusMapper` 的 `updatedAt` 状态路径及 19.5/15/28/54pt 尺寸；对相关源文件执行 `git diff --check`，并用只读 SQLite 查询当前最近新建五线程。
    - Actual: SQLite 与索引回退均提供 `createdAt`，状态映射原样保留；可见 SQL 使用规范化创建时间降序和 ID 稳定排序，当前只读结果依次为 15:55、14:37、12:20、11:41、11:40 创建的五个线程；悬浮行显示 `createdAt`，任务标题为 19.5pt medium，副标题/状态为 15pt regular，胶囊/行高为 28/54pt，状态停滞与聚合仍读取 `updatedAt`。
    - Exit Code: 0
    - Revision: implementation-content-sha256:908d7ca1303dcc0894e3c473fad4e127245571500ab64a7540c2e15fd4646a8c
- [ ] **Validation 7: 修订后运行截图验收**
  - Verify: 由于约束禁止自动编译，由用户本机重新启动 App 后提供同状态截图；对照本机只读数据库按创建时间降序的前五个线程，核对列表标题/时间顺序、19.5/15pt 可读性、五行无裁切和底部摘要单行。
  - Expected: 截图中的五条任务与数据库最近新建五条一致，创建时间自上而下降序，文字明显增大、不裁切且字重不过粗；取得该证据前不得宣称运行期视觉 QA 通过。
  - Evidence:
    - Check: 用户提供运行截图 `/var/folders/r8/nfxvrxds17b5p3ncc5_r457h0000gn/T/codex-clipboard-43f08df0-5a7f-4de1-9aee-8929655e9adc.png`，人工核对任务顺序、字号、裁切和字重。
    - Actual: 最近新建五任务、创建时间顺序和 19.5/15pt 尺寸均已生效且五行未裁切，但标题 semibold 与状态 medium 偏粗；代码已分别降为 medium 和 regular，仍需新截图确认字重。
    - Exit Code: not applicable
    - Revision: implementation-content-sha256:bfd5031e2b32b2352acc8cc727eb0d7d91613633c5d96fd7d52c47d23456a3b2
- [x] **Validation 8: DockCat 资源、许可证与修改说明静态核对**
  - Verify: 对六张资源运行 SHA-256，并逐一核对 `loaf=a5c4af1d5253ac40943ae23aa4cb9c486e2065ccb58f8594f55d91829eaea23c`、`stand=1b1ba120ac910ad747820cbbdd3a9208de242403232c21478298615e103229e7`、`walk_01=45ce21e71b34d0029984c955204976b5d7f3ba1aa6b87361a812b4fa17a7cee1`、`walk_02=206789b1422907928cf1e6524b9bd3e433064346e1bffa1a5a04c07d336fe64e`、`walk_03=2443057a687b9a5457586ea8cc1575150a6afac4582469ed96f9f2a0a9036fc0`、`walk_04=1b1e1ecbe96eb31a64da2cf5de3a6aae442550fc13359eea1d8692ca72d88933`；核对 `LICENSE.txt` 完整文件哈希 `ffcca38841adb694b6f380647e15f17c446a4d1656fed51a1e2041d064c94cc8`；核对 `THIRD_PARTY_NOTICES.md`/README 明确写出唯一上游 URL、commit、图片像素未修改、运行时缩放/贴底/状态映射/逐帧播放和非商业限制，并静态检查 `Package.swift` 与打包脚本资源 bundle 路径。
  - Expected: 图片与许可证均精确来自固定上游版本，修改/使用说明完整，资源声明和打包复制链存在；本项不以静态脚本检查代替最终 `.app` 落包证据。
  - Evidence:
    - Check: 对仓库内 DockCat 六张 PNG 与 `LICENSE.txt` 执行 SHA-256；核对 README/`THIRD_PARTY_NOTICES.md` 的上游 URL、commit、像素未修改、运行时使用方式和非商业限制；执行 `swift package dump-package`、`bash -n scripts/package_app.sh` 和资源/notice 路径 `rg`。
    - Actual: 六张 PNG 与完整许可证逐项匹配 Plan 固定哈希；SwiftPM 资源声明有效，打包脚本语法通过并会同时复制 `CodexNotch_CodexNotch.bundle` 与 `THIRD_PARTY_NOTICES.md`；归属说明包含唯一上游、固定 commit、原样图片、运行时缩放/贴底/状态映射/3fps 播放和非商业限制。
    - Exit Code: 0
    - Revision: implementation-content-sha256:b91aa79769201f9178a16a0310d4c139405952713a7b2565646cdf54cfad04bd
- [x] **Validation 9: 三态渲染和居中交互静态核对**
  - Verify: 使用 `rg` 与 scoped diff 核对 aggregate status 到 loaf/walk/stand 的唯一映射、四帧顺序、`1/3s` 计时器启停、透明图片绘制，以及圆形/光环/状态点/闪烁/hover work item 的移除；核对猫咪点击 toggle、正常 `1x` 居中、再次点击收起、拖动不重定位和 connector/attachment/offset/侧向 placement 删除，同时确认键盘 `2x` 与刘海路径未改。
  - Expected: 用户指定的三态和点击行为均有唯一实现，黄色以 3fps 播放，绿色/红色静止；不存在旧视觉或旧悬停/侧挂状态，窗口仍能通过外部点击、Escape、关闭按钮与图钉按既有语义工作。
  - Evidence:
    - Check: 使用 `rg` 与 scoped diff 核对 `aggregateStatus` 到 loaf/walk/stand 的唯一映射、四帧 `1/3s` 计时器与停止路径、透明等比贴底绘制；反向搜索并要求旧 orb/光环/状态点/闪烁/hover/connector/attachment/侧向 placement 标识无命中；核对猫咪窗口外部点击排除、点击 toggle、当前屏幕 `visibleFrame` 居中、460×396 卡片与拖动解耦。
    - Actual: 绿色/黄色/红色分别选择休息图/四帧走路/站立图；黄色只在入口可见时启动 3fps Timer，隐藏或离开黄色立即停止；猫咪视图只绘制透明 PNG。猫咪点击使用 entry frame 选择屏幕后以 1x 卡片居中，再次点击关闭；猫咪窗口只参与外部点击排除，拖动不再更新面板位置；旧光环、状态点、悬停展开、连接段和左右停靠实现均已移除，刘海和键盘代码路径仍保留。
    - Exit Code: 0
    - Revision: implementation-content-sha256:b91aa79769201f9178a16a0310d4c139405952713a7b2565646cdf54cfad04bd
- [ ] **Validation 10: 猫咪与居中窗口运行期验收**
  - Verify: 由于约束禁止自动编译，由用户本机运行后分别在绿色、黄色、红色状态观察猫咪；确认黄色动画速度、透明背景、无光环/状态点、三档尺寸、拖动/右键/tooltip，以及单击居中打开、再次单击收起、悬停不打开、拖动不移动面板和 Dashboard 内容无回归；截图和交互结论回填 `design-qa.md`。
  - Expected: 三种状态、黄色动画和点击居中交互均符合验收标准；在取得人工证据前不得声称运行期视觉或动画 QA 已通过。
  - Evidence: pending
- [ ] **Validation 11: 用户实际打包产物的许可落包验收**
  - Verify: 由于约束禁止自动编译/打包，由用户执行现有 `scripts/package_app.sh` 后，对生成的 `dist/Codex Notch.app/Contents/Resources` 做只读检查，确认 CodexNotch SwiftPM 资源 bundle、六张 PNG、完整 `LICENSE.txt` 和 `THIRD_PARTY_NOTICES.md` 存在；对产物内六张图片和许可证重新计算 SHA-256，并与 Validation 8 的固定值一致，核对 notice 含上游 URL、commit、修改/使用方式和非商业限制。
  - Expected: 最终 `.app` 离线可加载全部猫咪素材，并实际携带原样的完整许可证与清晰归属说明；取得该产物证据前不得声称打包分发许可验收通过。
  - Evidence: pending
- [ ] **Validation 12: 悬浮外壳边缘修订验收**
  - Verify: 静态核对 `floatingCard` 只使用黑色圆角填充、同形 `strokeBorder` 和 `clipShape`，反向确认该外壳不含 `.shadow`、渐变描边或第二层描边；用户重新运行后对照图二检查四边与四角连续性。
  - Expected: 静态检查 Exit Code 0；运行截图中不再出现图一箭头所示的不均匀蓝紫边线，且内容尺寸和位置无回归。
  - Evidence:
    - Check: 对用户修订前运行截图与参考图做代码定位；截取 `floatingCard` 实现后正向核对黑色 `fill`、同形 `strokeBorder`、`clipShape`，反向搜索该外壳 `.shadow`、`LinearGradient` 和非内收 `.stroke`，并对三个修订文件执行 `git diff --check`。
    - Actual: 修订前失败证据确认 460×396 卡片与窗口同尺寸，11/14pt 外阴影被窗口裁切；实现已删除两层外阴影、蓝紫渐变描边和第二层描边，改为 `Color.black.opacity(0.94)` 圆角填充、1pt 内收中性边线和同形裁切，窗口尺寸、任务布局与底部摘要未改。静态检查通过，仍需用户重新运行截图确认四边和四角。
    - Exit Code: 0
    - Revision: implementation-content-sha256:047a4f0c239657a53f3b3b1d5e93b982b2e69e77a2901ac47832ad5efaa2df92
- [ ] **Validation 13: 最近活动任务和行内容修订验收**
  - Verify: 静态核对 SQLite 可见会话查询在 `LIMIT` 前按规范化 `updatedExpr DESC, id DESC` 排序；用本机状态库只读查询最近活动五项并确认活动排名第 1、创建排名第 9 的任务进入结果；核对悬浮副标题使用 `latestMessage`、`cwdHint`、`activityText` 且不再引用 `createdAt`，最后由用户重新运行对照图一。
  - Expected: 静态检查 Exit Code 0；重新运行后悬浮列表展示最近活动五任务，副标题内容来自最新消息、项目名和活动相对时间，窗口尺寸、54pt 行高、19.5/15pt 字号、状态标签和 Token 摘要无回归。
  - Evidence:
    - Check: 只读查询当前 SQLite 的创建/活动双排名，确认错误截图逐项匹配创建排名 1～5，且当前最活跃任务为创建排名第 9；修改后按与实现相同的 `updated_at` 倒序查询前五项；正向搜索活动排序和三个副标题字段，反向确认悬浮任务行无 `createdAt`/`floatingTaskTime`，对六个修订文件执行 `git diff --check`。
    - Actual: 可见会话 SQL 已在既有八条上限前按 `updatedExpr DESC, id DESC` 排序，当前活动排名前五依次为当前任务、low 实验、两条 Automation 和眼神光任务，与图一语义一致；悬浮副标题现在单行组合非空最新消息、项目名和活动相对时间，没有最新消息时回退项目名与活动时间。窗口、行高、字号、状态和 Token 实现未改；运行截图仍待用户确认。
    - Exit Code: 0
    - Revision: implementation-content-sha256:ef1d8dda01fbbd4da3901e5957df6c43907b042ab5c90011c250e9a80f9a475a
- [ ] **Validation 14: 执行期状态保持验收**
  - Verify: 静态核对 `eventType(from:)` 对真实 rollout 中已验证的统计、上下文、压缩、工具结束和子 Agent 元数据事件返回 nil，并依赖现有空值合并保留最近有效 `lastEvent`；反向确认 `task_started`、`task_complete`、`turn_aborted` 未进入忽略集合；对最近活动八个 rollout 重放任务生命周期和状态过滤，最后由用户重新运行观察任务开始、长推理、上下文压缩和完成切换。
  - Expected: 静态重放 Exit Code 0，活动区间没有被中性事件映射成绿色；运行时任务开始后猫咪持续黄色走路，明确完成/中止后恢复绿色，红色提醒和 3fps 实现不变。
  - Evidence:
    - Check: 从最近活动八个真实 rollout 提取事件类型，以 `task_started` 到 `task_complete`/`turn_aborted` 作为活动真值，应用与实现相同的中性集合和现有黄色规则重放；统计中性事件数量和活动区间假绿色次数；正向核对集合及空值合并，反向检查开始/完成/中止未被忽略，并执行 scoped `git diff --check`。
    - Actual: 八个 rollout 的活动区间共出现 1282 条中性事件；修订前已观察到 `session_meta`、上下文压缩、工具结束等事件造成 1～54 秒假绿色，修订后重放的假绿色次数为 0。`task_complete` 与 `turn_aborted` 仍覆盖运行事件，错误/等待聚合、动画计时器、素材、窗口和其他数据契约未改；运行期仍待用户重新启动确认。
    - Exit Code: 0
    - Revision: implementation-content-sha256:65665525244c60de1e9ca2e0ac67356bb12e4c68752e6310181b27cf2fdaee87

## 未决项
- 无

## Plan Review
- Status: Approved
- Reviewer: independent subagent `plan_review` for v4; self for v5 shell-only correction, v6 diagnosed list correction, and v7 diagnosed event-filter correction
- Reason: v4 同时涉及第三方非商业许可证、SwiftPM/`.app` 资源分发、AppKit 动画计时器与窗口状态机，已由独立 Agent 审查；v5 只替换 `floatingCard` 的外壳修饰器；v6 根据已验证根因只恢复既有活动时间排序和已有会话展示字段；v7 仅让实测中性事件复用现有 nil 保留语义，不改变状态优先级或接口，并由八个真实 rollout 重放验证。
- Issues: 首轮指出缺少唯一上游 URL、素材修改说明及最终 `.app` 许可证落包证据；已补充 `https://github.com/Auwuua/DockCat`、图片像素未修改/仅运行时转换说明和 Validation 11，复审通过，无剩余问题。

## User Approval
- Status: Approved
- Plan Revision: v7-preserve-active-turn-state-20260807
- Approved Revision: v7-preserve-active-turn-state-20260807
- Approved By: user explicit “修复一下” after reviewing the diagnosed neutral-event status overwrite on 2026-08-07

## 偏离记录
- 2026-08-06: 用户将原双栏 Token/任务方案改为全宽固定五条任务行与底部 Token 摘要，并通过选项 1 确认 54/13/10pt 密度；该变更实质影响目标、范围、验收标准和实施步骤，因此更新为 Plan v2 并重置 User Approval。
- 2026-08-06: 用户基于首次单列运行截图要求任务文字再增加 50%，并指出列表不是最近新建任务；诊断确认旧实现按最后活动时间排序会让旧线程挤掉更晚创建的线程，因此新增内部创建时间字段、创建时间排序和 19.5/15pt 规格，更新为 Plan v3 并重置 User Approval。
- 2026-08-06: 用户在 Plan v3 运行截图中确认字号和排序后反馈任务字重偏粗；该反馈只在既有 19.5/15pt 规格内将标题 semibold 降为 medium、状态 medium 降为 regular，不改变目标、范围、接口或布局，因此沿用已批准的 Plan v3。
- 2026-08-06: 用户要求精确复用 DockCat 猫咪并选择仅限非商业用途、保留完整许可证和归属；随后确定绿色休息、黄色 3fps 四帧走路、红色站立提醒，移除圆形光环与状态点，并将交互改为单击猫咪居中 toggle、悬停不打开。该变更影响第三方资源与许可、SwiftPM/打包链、入口渲染和窗口状态机，因此更新为 Plan v4 并重置 User Approval。
- 2026-08-06: 用户运行截图暴露悬浮卡片外阴影和渐变描边在与卡片同尺寸的 `NSWindow` 边界被裁切，形成不均匀蓝紫边线；用户明确要求参考图二的完整黑色圆角容器实现，因此更新为 Plan v5，改用无外扩阴影的黑色填充、内收中性边线和同形裁切，不改变内容或交互。
- 2026-08-07: 用户以图一确认正确语义应为最近活动任务和“最新消息、项目名、活动时间”内容；只读数据库证明 v3 的创建时间排序会在 `LIMIT 8` 前排除活动排名第 1、创建排名第 9 的当前任务，因此用户在诊断结论后明确要求修复，更新为 Plan v6，恢复最后活动时间排序并复用已有会话字段，保留窗口、行高、字号、状态、Token 和猫咪不变。Task 6 与 Validation 6/7 的创建时间要求作为历史证据保留，由 Task 9 与 Validation 13 覆盖。
- 2026-08-07: 用户反馈任务开始后猫咪偶发不动，并明确排除多实例作为主因；真实 rollout 证明 `session_meta`、上下文压缩、工具结束和子 Agent 元数据等事件会在活动区间覆盖 `lastEvent`，因未命中黄色白名单造成 1～54 秒假绿色。用户确认诊断后要求修复，更新为 Plan v7，让已验证的中性事件不覆盖最近有效状态，保留红黄绿优先级和动画实现。

## Review
- Status: pending
- Reviewer: independent subagent
- Change Scope: Task 7 列出的 DockCat 资源/许可、SwiftPM/打包脚本、猫咪渲染与居中 Dashboard 交互文件，Task 8 的悬浮外壳修订，Task 9 的最近活动排序和悬浮副标题修订，以及 Task 10 的执行期中性事件过滤；Token 数据实现只做回归核对。
- Critical: 无
- Important: 无
- Minor: 无
- Verification Evidence: Validation 8/9、Validation 12/13 的静态部分及 Validation 14 的真实事件重放已通过，最新 implementation-content-sha256 为 `65665525244c60de1e9ca2e0ac67356bb12e4c68752e6310181b27cf2fdaee87`；Validation 10/11/12/13/14 的运行或实际打包部分等待用户证据。按 `$gr-review` 前置条件，运行验收未完成前不能开始独立代码 Review 或宣称完整通道交付完成。
