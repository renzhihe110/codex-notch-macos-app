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
    private let restingImage: NSImage
    private let standingImage: NSImage
    private let walkingImages: [NSImage]
    private var state: NotchState
    private var animationTimer: Timer?
    private var carouselTimer: Timer?
    private var capsuleSettingsObserver: NSObjectProtocol?
    private var displayedStatus: SessionStatus?
    private var walkingFrameIndex = 0
    private var carouselIndex = 0
    private var isEntryVisible = false
    private var hasPositionedForCurrentShow = false
    private var dragStartMouseLocation: CGPoint?
    private var dragStartWindowOrigin: CGPoint?
    private var didDrag = false
    private let dragThreshold: CGFloat = 3
    private var pillSize: CGSize

    init(initialState: NotchState, capsuleSettings: CapsuleSettings, onActivate: @escaping (CGRect) -> Void, onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void, onToggleMode: @escaping () -> Void) {
        let initialPillSize = capsuleSettings.size.dimensions
        let dockCatAssets = DockCatAssets.load()
        self.state = initialState
        self.onActivate = onActivate
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.onToggleMode = onToggleMode
        self.capsuleSettings = capsuleSettings
        self.restingImage = dockCatAssets.resting
        self.standingImage = dockCatAssets.standing
        self.walkingImages = dockCatAssets.walking
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

    // Dashboard 控制器只用这个窗口排除猫咪自身点击，不读取其位置做面板定位。
    var entryWindow: NSWindow { window }

    deinit {
        animationTimer?.invalidate()
        carouselTimer?.invalidate()
        if let capsuleSettingsObserver {
            NotificationCenter.default.removeObserver(capsuleSettingsObserver)
        }
    }

    // 刷新猫咪状态并按黄色聚合状态启停逐帧动画；刷新不会改动用户拖动后的位置。
    func update(state: NotchState) {
        self.state = state
        normalizeCarouselIndex()
        updateAnimationState()
        updatePillView()
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
        updateAnimationState()
        updatePillView()
        window.orderFrontRegardless()
    }

    // 隐藏悬浮球入口，同时清理未完成的拖动状态。
    func hideEntry() {
        isEntryVisible = false
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
        didDrag = false
        stopWalkingAnimation()
        pillView.isHighlighted = false
        pillView.needsDisplay = true
        window.orderOut(nil)
    }

    // 猫咪入口窗口保持透明背景，不额外绘制底色、光环或系统阴影。
    private func configureWindow() {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = pillView
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
    }

    // 悬浮球区分点击、拖动和右键菜单；只有普通点击才展开面板。
    private func configurePillView() {
        pillView.onMouseDown = { [weak self] event in self?.beginDrag(with: event) }
        pillView.onMouseDragged = { [weak self] event in self?.continueDrag(with: event) }
        pillView.onMouseUp = { [weak self] event in self?.endDrag(with: event) }
        pillView.onRightClick = { [weak self] event in self?.showContextMenu(with: event) }
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
            self.updatePillView()
        }
    }

    // 黄色状态以 DockCat 默认 3fps 顺序循环四帧，绿色和红色只保留静态图片。
    private func updateAnimationState() {
        let statusChanged = displayedStatus != state.aggregateStatus
        displayedStatus = state.aggregateStatus
        if statusChanged {
            walkingFrameIndex = 0
        }
        guard isEntryVisible, state.aggregateStatus == .yellow else {
            stopWalkingAnimation()
            return
        }
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 3.0, repeats: true) { [weak self] _ in
            guard let self, !self.walkingImages.isEmpty else { return }
            self.walkingFrameIndex = (self.walkingFrameIndex + 1) % self.walkingImages.count
            self.updatePillView()
        }
    }

    // 离开黄色状态或隐藏入口时立即停止动画，避免后台无效唤醒。
    private func stopWalkingAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    // 按聚合状态同步猫咪帧和悬浮提示。
    private func updatePillView() {
        switch displayedStatus ?? state.aggregateStatus {
        case .red:
            pillView.image = standingImage
        case .yellow:
            pillView.image = walkingImages[walkingFrameIndex % walkingImages.count]
        case .green:
            pillView.image = restingImage
        }
        pillView.toolTip = tooltipText
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
        }
        guard didDrag else { return }
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
        guard shouldActivate else { return }
        onActivate(window.frame)
    }

    // 悬浮球右键菜单保留原有设置和退出，并新增切回刘海居中模式。
    private func showContextMenu(with event: NSEvent) {
        pillView.isHighlighted = false
        pillView.needsDisplay = true
        NSMenu.popUpContextMenu(contextMenu, with: event, for: pillView)
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

// 从 SwiftPM 资源包加载固定版本的 DockCat 素材，缺失时立即暴露打包错误。
private struct DockCatAssets {
    let resting: NSImage
    let standing: NSImage
    let walking: [NSImage]

    static func load() -> DockCatAssets {
        DockCatAssets(resting: loadImage(named: "loaf"), standing: loadImage(named: "stand"), walking: (1...4).map { loadImage(named: String(format: "walk_%02d", $0)) })
    }

    private static func loadImage(named name: String) -> NSImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) else {
            preconditionFailure("缺少 DockCat 资源：\(name).png")
        }
        return image
    }
}

// 猫咪入口只绘制透明 PNG，并保留原有点击、拖动和右键事件。
private final class StatusPillView: NSControl {
    var image: NSImage? { didSet { if oldValue !== image { needsDisplay = true } } }
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

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
