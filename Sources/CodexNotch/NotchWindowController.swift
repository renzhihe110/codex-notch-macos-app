import AppKit
import Carbon
import SwiftUI

// 集中管理刘海窗口的固定尺寸，避免视图和窗口定位出现魔法数字。
enum NotchWindowMetrics {
    static let collapsedWidth: CGFloat = 320
    static let defaultCollapsedHeight: CGFloat = 30
    static let expandedWidth: CGFloat = 390
    // 最大高度控制在四条完整消息行，避免面板底部出现一截空黑底。
    static let expandedMaxHeight: CGFloat = 303
    static let expandedHorizontalInset: CGFloat = 12
    static let expandedRowInnerInset: CGFloat = 8
    static let expandedBottomInset: CGFloat = 8
    static let expandedListSpacing: CGFloat = 6
    static let expandedDividerHeight: CGFloat = 1
    static let expandedHeaderBottomInset: CGFloat = 8
    static let expandedErrorHeight: CGFloat = 30
    static let expandedEmptyListHeight: CGFloat = 46
    static let expandedRowHeightWithMessage: CGFloat = 58
    static let expandedRowHeightWithoutMessage: CGFloat = 46
    static let visibleSessionLimit = 8

    // 展开面板高度按当前内容收缩，内容很多时仍限制在最大高度内滚动。
    static func expandedSize(for state: NotchState, collapsedHeight: CGFloat, hasJumpError: Bool) -> CGSize {
        CGSize(width: expandedWidth, height: expandedHeight(for: state, collapsedHeight: collapsedHeight, hasJumpError: hasJumpError))
    }

    // ScrollView 高度和窗口高度使用同一套公式，避免内容少时底部出现多余黑底。
    static func expandedScrollHeight(for state: NotchState, collapsedHeight: CGFloat, hasJumpError: Bool) -> CGFloat {
        let chromeHeight = expandedHeaderHeight(collapsedHeight: collapsedHeight) + expandedBottomInset + expandedDividerHeight + expandedListSpacing + expandedErrorStackHeight(for: state, hasJumpError: hasJumpError)
        return max(0, expandedHeight(for: state, collapsedHeight: collapsedHeight, hasJumpError: hasJumpError) - chromeHeight)
    }

    // 头部高度保持入口行高度加分割线前留白，供 AppKit 和 SwiftUI 共用。
    static func expandedHeaderHeight(collapsedHeight: CGFloat) -> CGFloat {
        collapsedHeight + expandedHeaderBottomInset
    }

    private static func expandedHeight(for state: NotchState, collapsedHeight: CGFloat, hasJumpError: Bool) -> CGFloat {
        let contentHeight = expandedHeaderHeight(collapsedHeight: collapsedHeight) + expandedDividerHeight + expandedListSpacing + expandedErrorStackHeight(for: state, hasJumpError: hasJumpError) + expandedRowsHeight(for: state) + expandedBottomInset
        return min(expandedMaxHeight, ceil(contentHeight))
    }

    private static func expandedRowsHeight(for state: NotchState) -> CGFloat {
        let sessions = Array(state.sessions.prefix(visibleSessionLimit))
        guard !sessions.isEmpty else { return expandedEmptyListHeight }
        let rowsHeight = sessions.reduce(CGFloat(0)) { partial, session in
            partial + (session.latestMessage == nil ? expandedRowHeightWithoutMessage : expandedRowHeightWithMessage)
        }
        return rowsHeight + CGFloat(max(0, sessions.count - 1)) * expandedListSpacing
    }

    private static func expandedErrorStackHeight(for state: NotchState, hasJumpError: Bool) -> CGFloat {
        let errorCount = (hasJumpError ? 1 : 0) + (state.errorMessage == nil ? 0 : 1)
        guard errorCount > 0 else { return 0 }
        return CGFloat(errorCount) * (expandedErrorHeight + expandedListSpacing)
    }

    // 收起态高度跟随当前屏幕状态栏高度，确保刘海不探出菜单栏区域。
    static func collapsedSize(for screen: NSScreen?) -> CGSize {
        CGSize(width: collapsedWidth, height: collapsedHeight(for: screen))
    }

    // 菜单栏自动隐藏或外接屏拿不到高度时使用兜底高度，避免窗口消失。
    static func collapsedHeight(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return defaultCollapsedHeight }
        let statusBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        guard statusBarHeight > 0 else { return defaultCollapsedHeight }
        return min(defaultCollapsedHeight, statusBarHeight)
    }

    // 保留收起态窗口兜底定位，正常入口已经由系统状态栏项承载。
    static func origin(for size: CGSize, on screen: NSScreen?) -> CGPoint {
        guard let screen else { return .zero }
        return CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
    }

    // 展开面板从状态栏项下方弹出，横向夹在可见屏幕范围内。
    static func panelOrigin(for size: CGSize, on screen: NSScreen?, anchorFrame: CGRect?, includeAnchorArea: Bool = false) -> CGPoint {
        guard let screen else { return .zero }
        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 8
        let proposedX = anchorFrame.map { $0.midX - size.width / 2 } ?? visibleFrame.maxX - size.width - margin
        let minX = visibleFrame.minX + margin
        let maxX = visibleFrame.maxX - size.width - margin
        let proposedTopY = includeAnchorArea ? (anchorFrame?.maxY ?? visibleFrame.maxY) : (anchorFrame?.minY ?? visibleFrame.maxY)
        let topLimit = includeAnchorArea ? screen.frame.maxY : visibleFrame.maxY
        let y = max(visibleFrame.minY + margin, min(proposedTopY - size.height, topLimit - size.height))
        return CGPoint(x: min(max(proposedX, minX), maxX), y: y)
    }
}

// 无边框窗口默认不能成为 key，显式允许后失焦回调才能可靠收起。
private final class KeyableBorderlessWindow: NSWindow {
    var onLeftMouseDown: ((NSEvent) -> Bool)?
    var onRightMouseDown: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, onLeftMouseDown?(event) == true {
            return
        }
        if event.type == .rightMouseDown, let onRightMouseDown {
            onRightMouseDown(event)
            return
        }
        super.sendEvent(event)
    }
}

// 托管 SwiftUI 刘海视图，同时用 AppKit 兜住右键菜单，避免无边框窗口里 contextMenu 命中不稳。
private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onLeftClick: ((NSEvent) -> Bool)?
    var onRightClick: ((NSEvent) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let options: NSTrackingArea.Options = [.activeAlways, .inVisibleRect, .mouseEnteredAndExited]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        hoverTrackingArea = trackingArea
        addTrackingArea(trackingArea)
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        setHovering(true)
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if onLeftClick?(event) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let onRightClick {
            onRightClick(event)
            return
        }
        super.rightMouseDown(with: event)
    }

    // AppKit mouseMoved 会很频繁，去重后再交给窗口控制器，避免同一轮 display cycle 反复调整窗口。
    private func setHovering(_ isHovering: Bool) {
        guard self.isHovering != isHovering else { return }
        self.isHovering = isHovering
        onHoverChanged?(isHovering)
    }
}

// 创建并定位桌面顶部中间的透明无边框刘海窗口。
final class NotchWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: NotchViewModel
    private let hotKeySettings: HotKeySettings
    private let onSelectSession: (CodexSession) -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void
    private let onToggleMode: () -> Void
    private var collapseWorkItem: DispatchWorkItem?
    private var localKeyEventMonitor: Any?
    private var hotKeySettingsObserver: NSObjectProtocol?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var registeredHotKey: HotKey?
    private var keepsCollapsedEntryVisible = true
    private var activeEntryAnchorFrame: CGRect?
    private var suppressEntryHoverUntilExit = false
    private var mouseTrackingTimer: Timer?
    private var mouseLeftExpandedRegionAt: Date?
    private var tracksExpandedMouseExit = false
    private let collapseDelay: TimeInterval = 0.20
    private let expandDelay: TimeInterval = 0.06

    init(initialState: NotchState, hotKeySettings: HotKeySettings, onSelectSession: @escaping (CodexSession) -> Void, onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void, onToggleMode: @escaping () -> Void) {
        let collapsedSize = NotchWindowMetrics.collapsedSize(for: NSScreen.main)
        self.viewModel = NotchViewModel(state: initialState, collapsedHeight: collapsedSize.height)
        self.hotKeySettings = hotKeySettings
        self.onSelectSession = onSelectSession
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.onToggleMode = onToggleMode
        let window = KeyableBorderlessWindow(contentRect: CGRect(origin: .zero, size: collapsedSize), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init(window: window)
        window.onLeftMouseDown = { [weak self] event in self?.handleLeftMouseDown(event) ?? false }
        window.onRightMouseDown = { [weak self] event in self?.showContextMenu(with: event) }
        window.delegate = self
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true
        let hostingView = NotchHostingView(rootView: NotchView(model: viewModel, onSelectSession: onSelectSession, onOpenSettings: onOpenSettings, onQuit: onQuit, onToggleMode: onToggleMode))
        // 刘海窗口尺寸由控制器手动 setFrame，关闭 SwiftUI 自动反写窗口约束以避免快速进出时形成 display-cycle 布局循环。
        hostingView.sizingOptions = []
        hostingView.onLeftClick = { [weak self] event in self?.handleLeftMouseDown(event) ?? false }
        hostingView.onRightClick = { [weak self] event in self?.showContextMenu(with: event) }
        hostingView.onHoverChanged = { [weak self] isHovered in self?.handleHoverChanged(isHovered) }
        window.contentView = hostingView
        positionWindow(isExpanded: false)
        installKeyboardHandling()
    }

    deinit {
        if let localKeyEventMonitor {
            NSEvent.removeMonitor(localKeyEventMonitor)
        }
        if let hotKeySettingsObserver {
            NotificationCenter.default.removeObserver(hotKeySettingsObserver)
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        registeredHotKey = nil
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
        }
        mouseTrackingTimer?.invalidate()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    // 外部轮询刷新只替换展示状态，不改变当前展开/收起状态。
    func update(state: NotchState) {
        viewModel.state = state
        normalizeSelectedSessionIndex()
        // 展开时会话数量会影响面板高度，数据刷新后同步调整窗口 frame。
        if viewModel.isExpanded {
            positionWindow(isExpanded: true, anchorFrame: activeEntryAnchorFrame)
        }
    }

    // 刘海居中模式显示收起态入口，并让面板关闭后回到收起态。
    func showCollapsed() {
        collapseWorkItem?.cancel()
        keepsCollapsedEntryVisible = true
        activeEntryAnchorFrame = nil
        suppressEntryHoverUntilExit = false
        stopExpandedMouseTracking()
        viewModel.isExpanded = false
        positionWindow(isExpanded: false)
        window?.orderFrontRegardless()
    }

    // 胶囊模式隐藏刘海入口，并让胶囊打开的面板关闭后直接消失。
    func hideEntry() {
        collapseWorkItem?.cancel()
        keepsCollapsedEntryVisible = false
        activeEntryAnchorFrame = nil
        suppressEntryHoverUntilExit = false
        stopExpandedMouseTracking()
        viewModel.isExpanded = false
        window?.orderOut(nil)
    }

    // 展示跳转失败信息，保留用户当前展开状态。
    func showJumpError(_ message: String) {
        viewModel.jumpError = message
        // 错误提示会占用一行高度，展开态立即重算窗口尺寸。
        if viewModel.isExpanded {
            positionWindow(isExpanded: true, anchorFrame: activeEntryAnchorFrame)
        }
    }

    // 清理上一条跳转错误，避免成功后继续误导用户。
    func clearJumpError() {
        viewModel.jumpError = nil
        // 错误行消失后把面板收回到内容实际高度。
        if viewModel.isExpanded {
            positionWindow(isExpanded: true, anchorFrame: activeEntryAnchorFrame)
        }
    }

    // 窗口失焦时收起，外部点击的完整全局监听留给后续任务。
    func windowDidResignKey(_ notification: Notification) {
        collapseWorkItem?.cancel()
        setExpanded(false)
    }

    // 全局快捷键调用这个入口时，主动激活应用并展开面板，方便继续用方向键操作。
    func revealForKeyboard() {
        reveal(anchorFrame: keepsCollapsedEntryVisible ? window?.frame : nil, tracksMouseExit: false)
    }

    // 胶囊入口点击后，从对应按钮下方展开面板。
    func revealFromStatusItem(anchorFrame: CGRect?) {
        keepsCollapsedEntryVisible = false
        reveal(anchorFrame: anchorFrame, tracksMouseExit: true)
    }

    // 胶囊拖动时同步外部入口位置；只有胶囊打开的面板会跟随移动。
    func updateExternalEntryFrame(_ anchorFrame: CGRect) {
        guard !keepsCollapsedEntryVisible else { return }
        activeEntryAnchorFrame = anchorFrame
        guard viewModel.isExpanded else { return }
        collapseWorkItem?.cancel()
        positionWindow(isExpanded: true, anchorFrame: anchorFrame)
        window?.orderFrontRegardless()
    }

    // 鼠标离开胶囊后延迟确认位置；没进入面板或回到胶囊时才收起。
    func collapseExternalPanelIfNeeded() {
        guard !keepsCollapsedEntryVisible, viewModel.isExpanded else { return }
        collapseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isMouseInsideWindow() else { return }
            self.setExpanded(false)
        }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: workItem)
    }

    // 刘海入口点击时使用收起态窗口自身作为锚点，避免展开面板飘到右上角兜底位置。
    private func revealFromNotchEntry() {
        reveal(anchorFrame: window?.frame, tracksMouseExit: true)
    }

    // 统一展开入口，确保状态栏点击和热键行为一致。
    private func reveal(anchorFrame: CGRect?, tracksMouseExit: Bool) {
        collapseWorkItem?.cancel()
        suppressEntryHoverUntilExit = false
        tracksExpandedMouseExit = tracksMouseExit
        activeEntryAnchorFrame = anchorFrame
        normalizeSelectedSessionIndex()
        NSApp.activate(ignoringOtherApps: true)
        positionWindow(isExpanded: true, anchorFrame: anchorFrame)
        viewModel.isExpanded = true
        window?.makeKeyAndOrderFront(nil)
        updateExpandedMouseTracking()
    }

    private func handleHoverChanged(_ isHovered: Bool) {
        collapseWorkItem?.cancel()
        if isHovered {
            guard !suppressEntryHoverUntilExit else { return }
            guard !viewModel.isExpanded else { return }
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.isMouseInsideWindow() else { return }
                self.setExpanded(true, tracksMouseExit: true)
            }
            collapseWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + expandDelay, execute: workItem)
            return
        }
        suppressEntryHoverUntilExit = false
        // 展开后的收起由鼠标位置轮询负责，避免窗口变形时的 mouseExited 把状态机拉进循环。
    }

    // 收起态左键点击直接展开；展开后的列表点击继续交给 SwiftUI 处理。
    private func handleLeftMouseDown(_ event: NSEvent) -> Bool {
        guard !viewModel.isExpanded else { return false }
        revealFromNotchEntry()
        return true
    }

    private func isMouseInsideWindow() -> Bool {
        guard let window else { return false }
        // 使用全局鼠标坐标和窗口 frame 对比，避免 SwiftUI 重绘期间的命中测试抖动。
        let mouseLocation = NSEvent.mouseLocation
        if window.frame.insetBy(dx: -2, dy: -2).contains(mouseLocation) {
            return true
        }
        return viewModel.isExpanded && activeEntryAnchorFrame?.insetBy(dx: -2, dy: -2).contains(mouseLocation) == true
    }

    private func setExpanded(_ isExpanded: Bool, tracksMouseExit: Bool = true) {
        guard viewModel.isExpanded != isExpanded else { return }
        // 展开先放大窗口再显示内容；收起先隐藏内容再缩小窗口，避免内容尺寸和窗口约束互相追赶。
        if isExpanded {
            suppressEntryHoverUntilExit = false
            tracksExpandedMouseExit = tracksMouseExit
            let anchorFrame = keepsCollapsedEntryVisible ? window?.frame : activeEntryAnchorFrame
            activeEntryAnchorFrame = anchorFrame
            positionWindow(isExpanded: true, anchorFrame: anchorFrame)
            viewModel.isExpanded = true
            updateExpandedMouseTracking()
        } else {
            stopExpandedMouseTracking()
            viewModel.isExpanded = false
            activeEntryAnchorFrame = nil
            guard keepsCollapsedEntryVisible else {
                window?.orderOut(nil)
                return
            }
            positionWindow(isExpanded: false)
            suppressEntryHoverUntilExit = isMouseInsideCollapsedEntry()
            window?.orderFrontRegardless()
        }
    }

    // 刘海入口右键菜单保留设置和退出，并新增切换到胶囊模式。
    private func showContextMenu(with event: NSEvent) {
        collapseWorkItem?.cancel()
        guard let contentView = window?.contentView else { return }
        NSMenu.popUpContextMenu(contextMenu, with: event, for: contentView)
    }

    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        let switchItem = NSMenuItem(title: "切换到胶囊模式", action: #selector(handleToggleMode), keyEquivalent: "")
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

    private func positionWindow(isExpanded: Bool, anchorFrame: CGRect? = nil) {
        guard let window else { return }
        let screen = anchorFrame.flatMap { anchor in NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) } } ?? window.screen ?? NSScreen.main
        let collapsedSize = NotchWindowMetrics.collapsedSize(for: screen)
        if viewModel.collapsedHeight != collapsedSize.height {
            viewModel.collapsedHeight = collapsedSize.height
        }
        let size = isExpanded ? NotchWindowMetrics.expandedSize(for: viewModel.state, collapsedHeight: collapsedSize.height, hasJumpError: viewModel.jumpError != nil) : collapsedSize
        // 展开时跟随当前入口，收起时固定回到状态栏顶部居中。
        let origin = isExpanded ? NotchWindowMetrics.panelOrigin(for: size, on: screen, anchorFrame: anchorFrame, includeAnchorArea: keepsCollapsedEntryVisible) : NotchWindowMetrics.origin(for: size, on: screen)
        let frame = CGRect(origin: origin, size: size)
        guard window.frame != frame else { return }
        window.setFrame(frame, display: true)
    }

    // 展开态只用全局鼠标位置判断是否该收起，不再相信窗口变形过程中产生的 enter/exit 抖动事件。
    private func updateExpandedMouseTracking() {
        guard viewModel.isExpanded, tracksExpandedMouseExit else {
            stopExpandedMouseTracking()
            return
        }
        mouseLeftExpandedRegionAt = nil
        guard mouseTrackingTimer == nil else { return }
        mouseTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.checkExpandedMouseLocation()
        }
    }

    // 鼠标连续离开面板和入口锚点超过收起延迟后，才真正收起面板。
    private func checkExpandedMouseLocation() {
        guard viewModel.isExpanded, tracksExpandedMouseExit else {
            stopExpandedMouseTracking()
            return
        }
        guard !isMouseInsideWindow() else {
            mouseLeftExpandedRegionAt = nil
            return
        }
        let now = Date()
        let leftAt = mouseLeftExpandedRegionAt ?? now
        mouseLeftExpandedRegionAt = leftAt
        guard now.timeIntervalSince(leftAt) >= collapseDelay else { return }
        setExpanded(false)
    }

    // 收起或隐藏时关闭轮询，避免旧 timer 在下一轮展开时带入过期状态。
    private func stopExpandedMouseTracking() {
        mouseTrackingTimer?.invalidate()
        mouseTrackingTimer = nil
        mouseLeftExpandedRegionAt = nil
        tracksExpandedMouseExit = false
    }

    // 收起后如果鼠标仍压在入口上，先等真实离开再允许下一次自动展开，避免无鼠标移动时反复开合。
    private func isMouseInsideCollapsedEntry() -> Bool {
        guard keepsCollapsedEntryVisible, let window else { return false }
        let collapsedSize = NotchWindowMetrics.collapsedSize(for: window.screen ?? NSScreen.main)
        let collapsedFrame = CGRect(origin: NotchWindowMetrics.origin(for: collapsedSize, on: window.screen ?? NSScreen.main), size: collapsedSize)
        return collapsedFrame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    // 同时注册本地按键和系统热键；系统热键失败时，本地快捷键仍可在窗口聚焦时使用。
    private func installKeyboardHandling() {
        localKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
        hotKeySettingsObserver = NotificationCenter.default.addObserver(forName: HotKeySettings.changedNotification, object: hotKeySettings, queue: .main) { [weak self] _ in
            self?.reloadGlobalHotKey()
        }
        installGlobalHotKey()
    }

    // 安装 Carbon 热键回调，再按当前设置注册具体的按键组合。
    private func installGlobalHotKey() {
        if hotKeyHandlerRef == nil {
            installGlobalHotKeyHandler()
        }
        reloadGlobalHotKey()
    }

    private func installGlobalHotKeyHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            var pressedHotKeyID = EventHotKeyID(signature: 0, id: 0)
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &pressedHotKeyID)
            guard status == noErr, pressedHotKeyID.signature == OSType(0x434E4458), pressedHotKeyID.id == 1 else { return noErr }
            let controller = Unmanaged<NotchWindowController>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                controller.revealForKeyboard()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandlerRef)
        guard installStatus == noErr else { return }
    }

    private func registerConfiguredHotKey(_ hotKey: HotKey) -> EventHotKeyRef? {
        guard hotKeyHandlerRef != nil else { return nil }
        var registeredHotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x434E4458), id: 1)
        let registerStatus = RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &registeredHotKeyRef)
        guard registerStatus == noErr else {
            return nil
        }
        return registeredHotKeyRef
    }

    // 重新注册失败时尝试恢复上一条已注册热键，并把失败原因反馈给设置页。
    private func reloadGlobalHotKey() {
        let requestedHotKey = hotKeySettings.hotKey
        guard registeredHotKey != requestedHotKey else {
            hotKeySettings.clearRegistrationFailure()
            return
        }
        let previousHotKey = registeredHotKey
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let newHotKeyRef = registerConfiguredHotKey(requestedHotKey) {
            hotKeyRef = newHotKeyRef
            registeredHotKey = requestedHotKey
            hotKeySettings.clearRegistrationFailure()
            return
        }
        if let previousHotKey, let restoredHotKeyRef = registerConfiguredHotKey(previousHotKey) {
            hotKeyRef = restoredHotKeyRef
            registeredHotKey = previousHotKey
            hotKeySettings.restoreAfterRegistrationFailure(previousHotKey)
            return
        }
        registeredHotKey = nil
        hotKeySettings.reportRegistrationFailure()
    }

    // 展开面板时接管方向键、回车和 Escape，其他按键继续交给系统处理。
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if hotKeySettings.matches(event) {
            revealForKeyboard()
            return true
        }
        guard viewModel.isExpanded, window?.isKeyWindow == true else { return false }
        switch event.keyCode {
        case KeyCode.down:
            moveSelectedSession(by: 1)
            return true
        case KeyCode.up:
            moveSelectedSession(by: -1)
            return true
        case KeyCode.returnKey, KeyCode.keypadEnter:
            openSelectedSession()
            return true
        case KeyCode.escape:
            setExpanded(false)
            return true
        default:
            return false
        }
    }

    // 选中行只在当前可见 8 条会话内移动，避免键盘进入隐藏数据。
    private func moveSelectedSession(by delta: Int) {
        let count = visibleSessionCount
        guard count > 0 else {
            viewModel.selectedSessionIndex = 0
            return
        }
        viewModel.selectedSessionIndex = min(max(viewModel.selectedSessionIndex + delta, 0), count - 1)
    }

    // 回车进入当前选中会话，行为和点击会话标题保持一致。
    private func openSelectedSession() {
        guard viewModel.state.sessions.indices.contains(viewModel.selectedSessionIndex) else { return }
        onSelectSession(viewModel.state.sessions[viewModel.selectedSessionIndex])
    }

    // 会话刷新后夹紧选中下标，避免列表变短后回车访问越界。
    private func normalizeSelectedSessionIndex() {
        let count = visibleSessionCount
        guard count > 0 else {
            viewModel.selectedSessionIndex = 0
            return
        }
        viewModel.selectedSessionIndex = min(max(viewModel.selectedSessionIndex, 0), count - 1)
    }

    private var visibleSessionCount: Int {
        min(viewModel.state.sessions.count, NotchWindowMetrics.visibleSessionLimit)
    }

    // AppKit 键盘事件的固定 keyCode，集中放置避免散落魔法数字。
    private enum KeyCode {
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let escape: UInt16 = 53
    }
}
