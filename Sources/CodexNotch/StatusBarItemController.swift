import AppKit

// 管理可拖动胶囊浮窗入口；它不使用 NSStatusItem，也不保存用户拖动位置。
final class StatusBarItemController: NSObject {
    private let window: NSWindow
    private let pillView: StatusPillView
    private let onActivate: (CGRect?) -> Void
    private let onMove: (CGRect) -> Void
    private let onMouseExit: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void
    private let onToggleMode: () -> Void
    private var state: NotchState
    private var blinkTimer: Timer?
    private var carouselTimer: Timer?
    private var isBlinkingOn = true
    private var carouselIndex = 0
    private var isEntryVisible = false
    private var hasPositionedForCurrentShow = false
    private var dragStartMouseLocation: CGPoint?
    private var dragStartWindowOrigin: CGPoint?
    private var didDrag = false
    private var hoverWorkItem: DispatchWorkItem?
    private let dragThreshold: CGFloat = 3
    private let hoverDelay: TimeInterval = 0.10
    private let pillSize = CGSize(width: 82, height: 28)

    init(initialState: NotchState, onActivate: @escaping (CGRect?) -> Void, onMove: @escaping (CGRect) -> Void, onMouseExit: @escaping () -> Void, onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void, onToggleMode: @escaping () -> Void) {
        self.state = initialState
        self.onActivate = onActivate
        self.onMove = onMove
        self.onMouseExit = onMouseExit
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.onToggleMode = onToggleMode
        self.pillView = StatusPillView(frame: CGRect(origin: .zero, size: pillSize))
        self.window = NSWindow(contentRect: CGRect(origin: .zero, size: pillSize), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        configureWindow()
        configurePillView()
        configureCarouselTimer()
        update(state: initialState)
    }

    deinit {
        blinkTimer?.invalidate()
        carouselTimer?.invalidate()
        hoverWorkItem?.cancel()
    }

    // 刷新胶囊展示，并根据当前颜色启停闪烁计时器；刷新不会改动用户拖动后的位置。
    func update(state: NotchState) {
        self.state = state
        normalizeCarouselIndex()
        configureBlinkTimer()
        updatePillView()
        guard isEntryVisible else { return }
        window.display()
        window.orderFrontRegardless()
    }

    // 显示胶囊入口；进入胶囊模式时强制回到默认位置。
    func showEntry(resetPosition: Bool = false) {
        isEntryVisible = true
        if resetPosition || !hasPositionedForCurrentShow {
            positionWindowAtDefault()
            hasPositionedForCurrentShow = true
        }
        updatePillView()
        window.orderFrontRegardless()
    }

    // 隐藏胶囊入口，同时清理未完成的拖动状态。
    func hideEntry() {
        isEntryVisible = false
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
        didDrag = false
        hoverWorkItem?.cancel()
        pillView.isHighlighted = false
        pillView.needsDisplay = true
        window.orderOut(nil)
    }

    // 胶囊浮窗始终置顶显示，并允许鼠标事件进入自绘控件。
    private func configureWindow() {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = pillView
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
    }

    // 胶囊区分点击、拖动和右键菜单；只有普通点击才展开面板。
    private func configurePillView() {
        pillView.onMouseDown = { [weak self] event in self?.beginDrag(with: event) }
        pillView.onMouseDragged = { [weak self] event in self?.continueDrag(with: event) }
        pillView.onMouseUp = { [weak self] event in self?.endDrag(with: event) }
        pillView.onRightClick = { [weak self] event in self?.showContextMenu(with: event) }
        pillView.onHoverChanged = { [weak self] isHovered in self?.handleHoverChanged(isHovered) }
    }

    // 多个红黄灯会话时轮播 tooltip 目标，胶囊文字保持短小不挤占视觉空间。
    private func configureCarouselTimer() {
        carouselTimer?.invalidate()
        carouselTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.carouselSessions.count > 1 else { return }
            self.carouselIndex = (self.carouselIndex + 1) % self.carouselSessions.count
            self.updatePillView()
        }
    }

    // 红灯和黄灯闪烁，绿灯保持常亮。
    private func configureBlinkTimer() {
        guard currentStatus != .green else {
            blinkTimer?.invalidate()
            blinkTimer = nil
            isBlinkingOn = true
            return
        }
        guard blinkTimer == nil else { return }
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.isBlinkingOn.toggle()
            self.updatePillView()
        }
    }

    // 按状态同步胶囊圆点、短标题和悬浮提示。
    private func updatePillView() {
        pillView.status = currentStatus
        pillView.title = displayText
        pillView.isBlinkingOn = isBlinkingOn
        pillView.toolTip = tooltipText
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
        hoverWorkItem?.cancel()
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
        }
        guard didDrag else { return }
        window.setFrameOrigin(CGPoint(x: dragStartWindowOrigin.x + delta.width, y: dragStartWindowOrigin.y + delta.height))
        onMove(window.frame)
    }

    // 松手时根据拖动判定决定是展开面板还是只结束拖动。
    private func endDrag(with event: NSEvent) {
        let shouldActivate = !didDrag
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
        didDrag = false
        pillView.isHighlighted = false
        pillView.needsDisplay = true
        guard shouldActivate else { return }
        onActivate(window.frame)
    }

    // 胶囊右键菜单保留原有设置和退出，并新增切回刘海居中模式。
    private func showContextMenu(with event: NSEvent) {
        hoverWorkItem?.cancel()
        pillView.isHighlighted = false
        pillView.needsDisplay = true
        NSMenu.popUpContextMenu(contextMenu, with: event, for: pillView)
    }

    // 胶囊悬停短暂停留后展开面板，避免扫过或准备拖动时误弹。
    private func handleHoverChanged(_ isHovered: Bool) {
        hoverWorkItem?.cancel()
        guard isHovered else {
            guard isEntryVisible, dragStartMouseLocation == nil else { return }
            onMouseExit()
            return
        }
        guard isEntryVisible, dragStartMouseLocation == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isEntryVisible, self.dragStartMouseLocation == nil else { return }
            self.onActivate(self.window.frame)
        }
        hoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay, execute: workItem)
    }

    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        let switchItem = NSMenuItem(title: "切换到刘海居中模式", action: #selector(handleToggleMode), keyEquivalent: "")
        switchItem.target = self
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(handleOpenSettings), keyEquivalent: "")
        settingsItem.target = self
        let quitItem = NSMenuItem(title: "退出 Codex Notch", action: #selector(handleQuit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(switchItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        return menu
    }()

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

    private var currentStatus: SessionStatus {
        currentSession?.status ?? state.aggregateStatus
    }

    private var progressText: String {
        let total = state.sessions.count
        guard total > 0 else { return "0/0" }
        let completed = state.sessions.filter { $0.status == .green }.count
        return "\(completed)/\(total)"
    }

    private var displayText: String {
        switch currentStatus {
        case .red:
            return currentSession?.attention == .waitingInput ? "待输入" : "异常"
        case .yellow:
            return "运行中"
        case .green:
            return "完成"
        }
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

// 自绘状态胶囊，左侧状态圆点，右侧短文案。
private final class StatusPillView: NSControl {
    var status: SessionStatus = .green { didSet { needsDisplay = true } }
    var title: String = "" { didSet { needsDisplay = true } }
    var isBlinkingOn = true { didSet { needsDisplay = true } }
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    // 胶囊浮窗使用 AppKit tracking area 感知悬停，不影响点击和拖动事件。
    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil)
        hoverTrackingArea = trackingArea
        addTrackingArea(trackingArea)
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
        super.mouseExited(with: event)
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

    // 胶囊绘制成深色圆角形态，宽度收窄后仍能显示状态点和短文案。
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let pillRect = bounds.insetBy(dx: 1.5, dy: 2)
        let background = isHighlighted ? NSColor(calibratedWhite: 0.05, alpha: 0.95) : NSColor(calibratedWhite: 0.07, alpha: 0.90)
        background.setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: pillRect.height / 2, yRadius: pillRect.height / 2).fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        let border = NSBezierPath(roundedRect: pillRect.insetBy(dx: 0.5, dy: 0.5), xRadius: (pillRect.height - 1) / 2, yRadius: (pillRect.height - 1) / 2)
        border.lineWidth = 0.5
        border.stroke()
        drawStatusDot(in: pillRect)
        drawTitle(in: pillRect)
    }

    // 状态圆点只保留单层实心点，红黄状态按计时器闪烁。
    private func drawStatusDot(in pillRect: NSRect) {
        let dotRect = NSRect(x: pillRect.minX + 9, y: pillRect.midY - 5.5, width: 11, height: 11)
        let dotAlpha = status == .green || isBlinkingOn ? 1.0 : 0.30
        statusColor.withAlphaComponent(dotAlpha).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    // 标题按胶囊中线绘制，避免 AppKit 默认基线造成上下偏移。
    private func drawTitle(in pillRect: NSRect) {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.94)]
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        let textArea = NSRect(x: pillRect.minX + 25, y: pillRect.minY, width: pillRect.width - 31, height: pillRect.height)
        let textSize = attributedTitle.size()
        let drawPoint = NSPoint(x: textArea.midX - textSize.width / 2, y: pillRect.midY - textSize.height / 2)
        attributedTitle.draw(at: drawPoint)
    }

    private var statusColor: NSColor {
        switch status {
        case .red:
            return NSColor(red: 1.0, green: 0.25, blue: 0.22, alpha: 1.0)
        case .yellow:
            return NSColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1.0)
        case .green:
            return NSColor(red: 0.25, green: 0.86, blue: 0.42, alpha: 1.0)
        }
    }
}
