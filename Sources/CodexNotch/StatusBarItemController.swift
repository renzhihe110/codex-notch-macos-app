import AppKit

// 管理可拖动悬浮球入口；它不使用 NSStatusItem，也不保存用户拖动位置。
final class StatusBarItemController: NSObject {
    private let window: NSWindow
    private let pillView: StatusPillView
    private let onActivate: (CGRect) -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void
    private let onToggleMode: () -> Void
    private let capsuleSettings: CapsuleSettings
    private let pet: CodexPet
    private let petThemeSettings = CodexPetThemeSettings.shared
    private var state: NotchState
    private var animationTimer: Timer?
    private var carouselTimer: Timer?
    private var capsuleSettingsObserver: NSObjectProtocol?
    private var displayedPose: CodexPetPose?
    private var interactionPose: CodexPetPose?
    private var dragPose: CodexPetPose = .runningRight
    private var lookDirection: Int?
    private var animationFrameIndex = 0
    private var carouselIndex = 0
    private var isEntryVisible = false
    private var isHovered = false
    private var hasPositionedForCurrentShow = false
    private var dragStartMouseLocation: CGPoint?
    private var dragStartWindowOrigin: CGPoint?
    private var didDrag = false
    private let dragThreshold: CGFloat = 3
    private var pillSize: CGSize

    init(initialState: NotchState, capsuleSettings: CapsuleSettings, onActivate: @escaping (CGRect) -> Void, onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void, onToggleMode: @escaping () -> Void) {
        let initialPillSize = capsuleSettings.size.dimensions
        self.state = initialState
        self.onActivate = onActivate
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.onToggleMode = onToggleMode
        self.capsuleSettings = capsuleSettings
        self.pet = CodexPet.loadBundled()
        self.pillSize = initialPillSize
        self.pillView = StatusPillView(frame: CGRect(origin: .zero, size: initialPillSize))
        self.window = NSWindow(contentRect: CGRect(origin: .zero, size: initialPillSize), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        configureWindow()
        configurePillView()
        configureCapsuleSettingsObserver()
        configureCarouselTimer()
        update(state: initialState)
    }

    // Dashboard 控制器只用这个窗口排除宠物自身点击，不读取其位置做面板定位。
    var entryWindow: NSWindow { window }

    deinit {
        animationTimer?.invalidate()
        carouselTimer?.invalidate()
        if let capsuleSettingsObserver {
            NotificationCenter.default.removeObserver(capsuleSettingsObserver)
        }
    }

    // 刷新宠物后台状态；交互动作完成后会自然恢复到这里的最新状态。
    func update(state: NotchState) {
        self.state = state
        normalizeCarouselIndex()
        refreshPetAnimation()
        guard isEntryVisible else { return }
        window.displayIfNeeded()
    }

    // 显示悬浮球入口；进入悬浮模式时强制回到默认位置。
    func showEntry(resetPosition: Bool = false) {
        isEntryVisible = true
        if resetPosition || !hasPositionedForCurrentShow {
            positionWindowAtDefault()
            hasPositionedForCurrentShow = true
        }
        refreshPetAnimation()
        window.orderFrontRegardless()
    }

    // 隐藏悬浮球入口，同时清理未完成的拖动状态。
    func hideEntry() {
        isEntryVisible = false
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
        didDrag = false
        isHovered = false
        lookDirection = nil
        interactionPose = nil
        displayedPose = nil
        stopPetAnimation()
        pillView.isHighlighted = false
        pillView.needsDisplay = true
        window.orderOut(nil)
    }

    // 宠物入口窗口保持透明背景，不额外绘制底色、光环或系统阴影。
    private func configureWindow() {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = pillView
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
    }

    // 悬浮球区分点击、拖动和右键菜单；只有普通点击才展开面板。
    private func configurePillView() {
        pillView.onMouseDown = { [weak self] event in self?.beginDrag(with: event) }
        pillView.onMouseDragged = { [weak self] event in self?.continueDrag(with: event) }
        pillView.onMouseUp = { [weak self] event in self?.endDrag(with: event) }
        pillView.onRightClick = { [weak self] event in self?.showContextMenu(with: event) }
        pillView.onMouseEntered = { [weak self] event in self?.mouseEntered(with: event) }
        pillView.onMouseMoved = { [weak self] event in self?.mouseMoved(with: event) }
        pillView.onMouseExited = { [weak self] event in self?.mouseExited(with: event) }
        pillView.onScrollWheel = { [weak self] event in self?.resizePet(with: event) }
    }

    // 监听设置页尺寸变更，保持悬浮球窗口和展开面板锚点同步更新。
    private func configureCapsuleSettingsObserver() {
        capsuleSettingsObserver = NotificationCenter.default.addObserver(forName: CapsuleSettings.changedNotification, object: capsuleSettings, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.applyCapsuleSize(self.capsuleSettings.size)
        }
    }

    // 多个红黄灯会话时轮播 tooltip 目标，胶囊文字保持短小不挤占视觉空间。
    private func configureCarouselTimer() {
        carouselTimer?.invalidate()
        carouselTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.carouselSessions.count > 1 else { return }
            self.carouselIndex = (self.carouselIndex + 1) % self.carouselSessions.count
            self.pillView.toolTip = self.tooltipText
        }
    }

    // 隐藏入口时停止唯一的宠物逐帧计时器，tooltip 轮播计时器保持原生命周期。
    private func stopPetAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    // 按交互优先级选择动作；后台繁忙状态优先于仅用于空闲时的鼠标观察方向。
    private var effectivePose: CodexPetPose {
        if didDrag { return dragPose }
        if let interactionPose { return interactionPose }
        let statusPose = basePose
        if statusPose != .idle { return statusPose }
        if let lookDirection { return .look(lookDirection) }
        return .idle
    }

    // 将现有红黄绿状态细分为 v2 的失败、等待、运行和空闲四种后台动作。
    private var basePose: CodexPetPose {
        if (state.errorMessage != nil && state.sessions.isEmpty) || state.sessions.contains(where: { $0.status == .red && $0.attention == nil }) { return .failed }
        if state.sessions.contains(where: { $0.attention == .waitingInput || $0.attention == .stalled }) { return .waiting }
        if state.aggregateStatus == .yellow { return .running }
        return .idle
    }

    // 动作改变时从首帧开始；同一动作只更新 tooltip，不制造第二个计时器。
    private func refreshPetAnimation() {
        guard isEntryVisible else {
            stopPetAnimation()
            pillView.toolTip = tooltipText
            return
        }
        let nextPose = effectivePose
        if displayedPose != nextPose {
            displayedPose = nextPose
            animationFrameIndex = 0
            renderPetFrameAndScheduleNext()
            return
        }
        pillView.toolTip = tooltipText
    }

    // 根据每帧时长使用 common mode 单次调度，保证拖动和菜单跟踪期间动画仍可刷新。
    private func renderPetFrameAndScheduleNext() {
        stopPetAnimation()
        guard isEntryVisible, let displayedPose else { return }
        let frames = pet.frames(for: displayedPose, theme: petThemeSettings.theme)
        animationFrameIndex = min(animationFrameIndex, frames.count - 1)
        pillView.image = frames[animationFrameIndex]
        pillView.toolTip = tooltipText
        guard frames.count > 1 else { return }
        let durations = displayedPose.frameDurations
        let duration = durations[min(animationFrameIndex, durations.count - 1)]
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in self?.advancePetFrame() }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // 循环动作回到首帧；挥手和跳跃只播一轮，然后恢复最新有效动作。
    private func advancePetFrame() {
        guard let displayedPose else { return }
        let frames = pet.frames(for: displayedPose, theme: petThemeSettings.theme)
        if animationFrameIndex + 1 < frames.count {
            animationFrameIndex += 1
            renderPetFrameAndScheduleNext()
            return
        }
        if displayedPose.isOneShot, interactionPose == displayedPose {
            interactionPose = nil
            self.displayedPose = nil
            refreshPetAnimation()
            return
        }
        animationFrameIndex = 0
        renderPetFrameAndScheduleNext()
    }

    // 启动一次性交互动作，并覆盖尚未完成的上一次一次性动作。
    private func beginOneShot(_ pose: CodexPetPose) {
        interactionPose = pose
        displayedPose = nil
        refreshPetAnimation()
    }

    // 尺寸切换时围绕当前中心缩放，避免设置页操作让胶囊突然跳到别处。
    private func applyCapsuleSize(_ size: CapsuleSize) {
        let oldFrame = window.frame
        pillSize = size.dimensions
        pillView.frame = CGRect(origin: .zero, size: pillSize)
        let origin = isEntryVisible ? CGPoint(x: oldFrame.midX - pillSize.width / 2, y: oldFrame.midY - pillSize.height / 2) : oldFrame.origin
        window.setFrame(CGRect(origin: origin, size: pillSize), display: true)
        guard isEntryVisible else { return }
        window.orderFrontRegardless()
    }

    // 滚轮在现有三档尺寸间切换，并复用设置对象保存用户选择。
    private func resizePet(with event: NSEvent) {
        guard event.scrollingDeltaY != 0, let currentIndex = CapsuleSize.allCases.firstIndex(of: capsuleSettings.size) else { return }
        let step = event.scrollingDeltaY > 0 ? 1 : -1
        let targetIndex = min(max(currentIndex + step, CapsuleSize.allCases.startIndex), CapsuleSize.allCases.index(before: CapsuleSize.allCases.endIndex))
        capsuleSettings.select(size: CapsuleSize.allCases[targetIndex])
    }

    // 默认位置放在主屏顶部可见区域，后续完全交给用户拖动。
    private func positionWindowAtDefault() {
        guard let screen = NSScreen.main else { return }
        pillView.frame = CGRect(origin: .zero, size: pillSize)
        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(x: visibleFrame.midX - pillSize.width / 2, y: visibleFrame.maxY - pillSize.height - 6)
        window.setFrame(CGRect(origin: origin, size: pillSize), display: true)
    }

    // 记录按下时的全局坐标和窗口原点，后续用全局坐标差值移动窗口。
    private func beginDrag(with event: NSEvent) {
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window.frame.origin
        didDrag = false
        pillView.isHighlighted = true
        pillView.needsDisplay = true
    }

    // 鼠标移动超过阈值后才判定为拖动，避免普通点击轻微抖动误触。
    private func continueDrag(with event: NSEvent) {
        guard let dragStartMouseLocation, let dragStartWindowOrigin else { return }
        let currentLocation = NSEvent.mouseLocation
        let delta = CGSize(width: currentLocation.x - dragStartMouseLocation.x, height: currentLocation.y - dragStartMouseLocation.y)
        if !didDrag, hypot(delta.width, delta.height) > dragThreshold {
            didDrag = true
            interactionPose = nil
            displayedPose = nil
        }
        guard didDrag else { return }
        if abs(delta.width) > dragThreshold / 2 { dragPose = delta.width < 0 ? .runningLeft : .runningRight }
        refreshPetAnimation()
        window.setFrameOrigin(CGPoint(x: dragStartWindowOrigin.x + delta.width, y: dragStartWindowOrigin.y + delta.height))
    }

    // 松手时根据拖动判定决定是展开面板还是只结束拖动。
    private func endDrag(with event: NSEvent) {
        let shouldActivate = !didDrag
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
        didDrag = false
        pillView.isHighlighted = false
        pillView.needsDisplay = true
        displayedPose = nil
        if !shouldActivate {
            refreshPetAnimation()
            return
        }
        beginOneShot(.jumping)
        onActivate(window.frame)
    }

    // 右键菜单显示期间循环 review，菜单关闭后恢复最新后台或观察动作。
    private func showContextMenu(with event: NSEvent) {
        pillView.isHighlighted = false
        pillView.needsDisplay = true
        interactionPose = .review
        displayedPose = nil
        refreshPetAnimation()
        updateThemeMenuState()
        NSMenu.popUpContextMenu(contextMenu, with: event, for: pillView)
        if interactionPose == .review { interactionPose = nil }
        displayedPose = nil
        refreshPetAnimation()
    }

    // 鼠标进入先完整播放一轮挥手，期间仍记录后续观察方向。
    private func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateLookDirection(with: event)
        beginOneShot(.waving)
    }

    // 空闲悬停时将 AppKit 向上的坐标系量化为从正上方开始顺时针的 16 个方向。
    private func mouseMoved(with event: NSEvent) {
        guard isHovered else { return }
        updateLookDirection(with: event)
        refreshPetAnimation()
    }

    // 鼠标移出只清除观察方向；已经开始的一次性动作仍会正常播完。
    private func mouseExited(with event: NSEvent) {
        isHovered = false
        lookDirection = nil
        refreshPetAnimation()
    }

    // 中心死区使用 idle，外围按每 22.5° 就近取一个方向格。
    private func updateLookDirection(with event: NSEvent) {
        let point = pillView.convert(event.locationInWindow, from: nil)
        let dx = point.x - pillView.bounds.midX
        let dy = point.y - pillView.bounds.midY
        let deadZone = min(pillView.bounds.width, pillView.bounds.height) * 0.12
        guard hypot(dx, dy) >= deadZone else {
            lookDirection = nil
            return
        }
        let clockwiseDegrees = atan2(dx, dy) * 180 / .pi
        let normalizedDegrees = clockwiseDegrees < 0 ? clockwiseDegrees + 360 : clockwiseDegrees
        lookDirection = Int((normalizedDegrees / 22.5).rounded()) % 16
    }

    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        let switchItem = NSMenuItem(title: "切换到刘海居中模式", action: #selector(handleToggleMode), keyEquivalent: "")
        switchItem.target = self
        let themeItem = NSMenuItem(title: "宠物主题", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "宠物主题")
        for theme in CodexPetTheme.allCases {
            let item = NSMenuItem(title: theme.displayName, action: #selector(handleSelectTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.rawValue
            themeMenu.addItem(item)
        }
        themeItem.submenu = themeMenu
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(handleOpenSettings), keyEquivalent: "")
        settingsItem.target = self
        let quitItem = NSMenuItem(title: "退出 Codex Notch", action: #selector(handleQuit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(switchItem)
        menu.addItem(.separator())
        menu.addItem(themeItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        return menu
    }()

    // 菜单弹出前同步持久化选择，确保当前主题始终只有一个勾选项。
    private func updateThemeMenuState() {
        guard let themeItems = contextMenu.items.first(where: { $0.title == "宠物主题" })?.submenu?.items else { return }
        for item in themeItems { item.state = item.representedObject as? String == petThemeSettings.theme.rawValue ? .on : .off }
    }

    // 切换主题后立即从运行动作首帧刷新；非运行状态保持当前动作不变。
    @objc private func handleSelectTheme(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let theme = CodexPetTheme(rawValue: rawValue) else { return }
        petThemeSettings.select(theme: theme)
        displayedPose = nil
        refreshPetAnimation()
    }

    @objc private func handleToggleMode() {
        onToggleMode()
    }

    @objc private func handleOpenSettings() {
        onOpenSettings()
    }

    @objc private func handleQuit() {
        onQuit()
    }

    private var carouselSessions: [CodexSession] {
        let activeSessions = state.sessions.filter { $0.status != .green }
        return activeSessions.isEmpty ? Array(state.sessions.prefix(1)) : activeSessions
    }

    private var currentSession: CodexSession? {
        guard !carouselSessions.isEmpty else { return nil }
        return carouselSessions[carouselIndex % carouselSessions.count]
    }

    private var progressText: String {
        let total = state.sessions.count
        guard total > 0 else { return "0/0" }
        let completed = state.sessions.filter { $0.status == .green }.count
        return "\(completed)/\(total)"
    }

    private var tooltipText: String {
        guard let currentSession else { return state.errorMessage == nil ? "Codex：暂无会话" : "Codex：读取错误" }
        return "\(statusText(for: currentSession)) · \(currentSession.displayTitle) · \(currentSession.activityText) · \(progressText)"
    }

    private func normalizeCarouselIndex() {
        let total = carouselSessions.count
        guard total > 0 else {
            carouselIndex = 0
            return
        }
        carouselIndex = carouselIndex % total
    }

    private func statusText(for session: CodexSession) -> String {
        if let attention = session.attention { return attention.shortLabel }
        switch session.status {
        case .red:
            return "失败"
        case .yellow:
            return "运行中"
        case .green:
            return "完成"
        }
    }
}

// 宠物入口绘制透明 v2 帧，并负责发送点击、拖动、右键和悬停事件。
private final class StatusPillView: NSControl {
    var image: NSImage? { didSet { if oldValue !== image { needsDisplay = true } } }
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onMouseEntered: ((NSEvent) -> Void)?
    var onMouseMoved: ((NSEvent) -> Void)?
    var onMouseExited: ((NSEvent) -> Void)?
    var onScrollWheel: ((NSEvent) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    // 跟踪区域随三档尺寸自动更新，并在非活跃窗口中继续接收悬停事件。
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    // 将悬停事件交给控制器决定挥手和观察方向。
    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?(event)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?(event)
    }

    // 将滚轮缩放交给控制器，以便窗口尺寸和持久化设置保持同步。
    override func scrollWheel(with event: NSEvent) {
        onScrollWheel?(event)
    }

    // 左键按下只记录状态，真正点击动作在 mouseUp 中按拖动阈值判断。
    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }

    // 拖动过程交给控制器按全局坐标移动窗口。
    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }

    // 松手后由控制器决定触发展开还是结束拖动。
    override func mouseUp(with event: NSEvent) {
        onMouseUp?(event)
    }

    // 右键只弹菜单，不触发拖动和展开。
    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    // 图片等比缩放并贴底显示，不绘制圆形底、光环或独立状态点。
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let targetBounds = bounds.insetBy(dx: 2, dy: 2)
        let scale = min(targetBounds.width / image.size.width, targetBounds.height / image.size.height)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let targetRect = NSRect(x: targetBounds.midX - targetSize.width / 2, y: targetBounds.minY, width: targetSize.width, height: targetSize.height)
        image.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: isHighlighted ? 0.78 : 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
}
