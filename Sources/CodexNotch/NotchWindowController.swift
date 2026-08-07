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
    static func expandedSize(for state: NotchState, collapsedHeight: CGFloat, hasJumpError: Bool, scale: CGFloat = 1) -> CGSize {
        CGSize(width: expandedWidth * scale, height: expandedHeight(for: state, collapsedHeight: collapsedHeight, hasJumpError: hasJumpError) * scale)
    }

    // ScrollView 高度和窗口高度使用同一套公式，避免内容少时底部出现多余黑底。
    static func expandedScrollHeight(for state: NotchState, collapsedHeight: CGFloat, hasJumpError: Bool, scale: CGFloat = 1) -> CGFloat {
        let chromeHeight = expandedHeaderHeight(collapsedHeight: collapsedHeight, scale: scale) + expandedBottomInset * scale + expandedDividerHeight + expandedListSpacing * scale + expandedErrorStackHeight(for: state, hasJumpError: hasJumpError) * scale
        return max(0, expandedHeight(for: state, collapsedHeight: collapsedHeight, hasJumpError: hasJumpError) * scale - chromeHeight)
    }

    // 头部高度保持入口行高度加分割线前留白，供 AppKit 和 SwiftUI 共用。
    static func expandedHeaderHeight(collapsedHeight: CGFloat, scale: CGFloat = 1) -> CGFloat {
        (collapsedHeight + expandedHeaderBottomInset) * scale
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

    // 展开面板从入口下方弹出，横向夹在可见屏幕范围内。
    static func panelOrigin(for size: CGSize, on screen: NSScreen?, anchorFrame: CGRect?, includeAnchorArea: Bool = false, anchorGap: CGFloat = 0) -> CGPoint {
        guard let screen else { return .zero }
        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 8
        let proposedX = anchorFrame.map { $0.midX - size.width / 2 } ?? visibleFrame.maxX - size.width - margin
        let minX = visibleFrame.minX + margin
        let maxX = visibleFrame.maxX - size.width - margin
        let proposedTopY = includeAnchorArea ? (anchorFrame?.maxY ?? visibleFrame.maxY) : (anchorFrame?.minY ?? visibleFrame.maxY)
        let topLimit = includeAnchorArea ? screen.frame.maxY : visibleFrame.maxY
        let y = max(visibleFrame.minY + margin, min(proposedTopY - size.height - anchorGap, topLimit - size.height))
        return CGPoint(x: min(max(proposedX, minX), maxX), y: y)
    }

    // 全局快捷键展开时居中显示在可见区域，避开菜单栏和 Dock。
    static func centeredPanelOrigin(for size: CGSize, on screen: NSScreen?) -> CGPoint {
        guard let screen else { return .zero }
        let visibleFrame = screen.visibleFrame
        return CGPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2)
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

}

// 创建并定位桌面顶部中间的透明无边框刘海窗口。
final class NotchWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: NotchViewModel
    private let hotKeySettings: HotKeySettings
    private let onSelectSession: (CodexSession) -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void
    private let onToggleMode: () -> Void
    private var localKeyEventMonitor: Any?
    private var localMouseEventMonitor: Any?
    private var globalMouseEventMonitor: Any?
    private var hotKeySettingsObserver: NSObjectProtocol?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var registeredHotKey: HotKey?
    private var keepsCollapsedEntryVisible = true
    private var activeEntryAnchorFrame: CGRect?
    private weak var externalEntryWindow: NSWindow?
    private var presentationScreen: NSScreen?
    private var centersExpandedPanel = false
    // 悬浮 Dashboard 初始居中后保留当前位置，避免状态刷新覆盖用户拖动。
    private var preservesFloatingDashboardPosition = false
    // 保存悬浮 Dashboard 尺寸，供窗口控制器和 SwiftUI 视图共享。
    private let floatingDashboardSettings = FloatingDashboardSettings.shared

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
        // 默认不允许拖动刘海入口；悬浮 Dashboard 展开后再启用背景拖动。
        window.isMovableByWindowBackground = false
        window.acceptsMouseMovedEvents = true
        let hostingView = NotchHostingView(rootView: NotchView(model: viewModel, onSelectSession: onSelectSession, onOpenSettings: onOpenSettings, onQuit: onQuit, onToggleMode: onToggleMode, onTogglePin: { [weak self] in
            self?.toggleFloatingPanelPin()
        }, onClose: { [weak self] in
            self?.closeFloatingPanel()
        }))
        // 刘海窗口尺寸由控制器手动 setFrame，关闭 SwiftUI 自动反写窗口约束以避免快速进出时形成 display-cycle 布局循环。
        hostingView.sizingOptions = []
        hostingView.onLeftClick = { [weak self] event in self?.handleLeftMouseDown(event) ?? false }
        hostingView.onRightClick = { [weak self] event in self?.showContextMenu(with: event) }
        window.contentView = hostingView
        positionWindow(isExpanded: false)
        installKeyboardHandling()
        installOutsideClickHandling()
    }

    deinit {
        if let localKeyEventMonitor {
            NSEvent.removeMonitor(localKeyEventMonitor)
        }
        if let localMouseEventMonitor {
            NSEvent.removeMonitor(localMouseEventMonitor)
        }
        if let globalMouseEventMonitor {
            NSEvent.removeMonitor(globalMouseEventMonitor)
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
        keepsCollapsedEntryVisible = true
        activeEntryAnchorFrame = nil
        presentationScreen = nil
        centersExpandedPanel = false
        preservesFloatingDashboardPosition = false
        viewModel.isPinned = false
        setFloatingDashboardResizable(false)
        window?.isMovableByWindowBackground = false
        viewModel.isPresentedFromCapsule = false
        viewModel.isExpanded = false
        positionWindow(isExpanded: false)
        window?.orderFrontRegardless()
    }

    // 胶囊模式隐藏刘海入口，并让胶囊打开的面板关闭后直接消失。
    func hideEntry() {
        keepsCollapsedEntryVisible = false
        activeEntryAnchorFrame = nil
        presentationScreen = nil
        centersExpandedPanel = false
        preservesFloatingDashboardPosition = false
        viewModel.isPinned = false
        setFloatingDashboardResizable(false)
        window?.isMovableByWindowBackground = false
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

    // 窗口失焦时收起；外部点击由独立鼠标监听兜底。
    func windowDidResignKey(_ notification: Notification) {
        guard !viewModel.isPinned else { return }
        // 点击猫咪时先保留面板，随后由猫咪的 mouseUp 执行显式 toggle。
        guard !isMouseInsidePanelOrEntry() else { return }
        setExpanded(false)
    }

    // 用户拖拽悬浮 Dashboard 边缘或角落时，立即保存尺寸并同步 SwiftUI 内容布局。
    func windowDidResize(_ notification: Notification) {
        guard viewModel.isExpanded, viewModel.isPresentedFromCapsule, let window else { return }
        floatingDashboardSettings.update(size: window.frame.size)
    }

    // 点击面板之外的本应用窗口或其他应用区域时收起面板，补足 accessory 窗口失焦不稳定的场景。
    private func installOutsideClickHandling() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        localMouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.collapseExpandedPanelAfterOutsideClick(eventWindow: event.window)
            return event
        }
        globalMouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            DispatchQueue.main.async {
                self?.collapseExpandedPanelAfterOutsideClick(eventWindow: nil)
            }
        }
    }

    // 外部点击只在展开态生效；面板自身点击继续交给 SwiftUI 行、按钮和右键菜单处理。
    private func collapseExpandedPanelAfterOutsideClick(eventWindow: NSWindow?) {
        guard viewModel.isExpanded, !viewModel.isPinned else { return }
        guard eventWindow !== window, eventWindow !== externalEntryWindow else { return }
        setExpanded(false)
    }

    // 全局快捷键始终打开正常尺寸的悬浮 Dashboard，关闭后仍回到原入口模式。
    func revealForKeyboard() {
        reveal(anchorFrame: nil, centersInScreen: true, expandedScale: 1, presentsFloatingDashboard: true)
    }

    // 全局快捷键使用显式 toggle：已展开时收起，未展开时再按原逻辑弹出。
    func toggleForKeyboard() {
        guard viewModel.isExpanded else {
            revealForKeyboard()
            return
        }
        setExpanded(false)
    }

    // 记录猫咪窗口，仅用于外部点击排除，不参与 Dashboard 定位。
    func setExternalEntryWindow(_ entryWindow: NSWindow) {
        externalEntryWindow = entryWindow
    }

    // 猫咪单击显式切换正常尺寸 Dashboard，并在猫咪所在屏幕居中显示。
    func toggleFromStatusItem(entryFrame: CGRect) {
        keepsCollapsedEntryVisible = false
        if viewModel.isExpanded, viewModel.isPresentedFromCapsule {
            setExpanded(false)
            return
        }
        presentationScreen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: entryFrame.midX, y: entryFrame.midY)) } ?? NSScreen.main
        reveal(anchorFrame: nil, centersInScreen: true, expandedScale: 1)
    }

    // 刘海入口点击时使用收起态窗口自身作为锚点，避免展开面板飘到右上角兜底位置。
    private func revealFromNotchEntry() {
        reveal(anchorFrame: window?.frame, centersInScreen: false, expandedScale: 1)
    }

    // 统一展开入口，快捷键可额外指定 Dashboard 样式而不改变当前入口模式。
    private func reveal(anchorFrame: CGRect?, centersInScreen: Bool, expandedScale: CGFloat, presentsFloatingDashboard: Bool = false) {
        activeEntryAnchorFrame = anchorFrame
        centersExpandedPanel = centersInScreen
        viewModel.expandedScale = expandedScale
        normalizeSelectedSessionIndex()
        NSApp.activate(ignoringOtherApps: true)
        viewModel.isPresentedFromCapsule = presentsFloatingDashboard || !keepsCollapsedEntryVisible
        setFloatingDashboardResizable(viewModel.isPresentedFromCapsule)
        preservesFloatingDashboardPosition = false
        positionWindow(isExpanded: true, anchorFrame: anchorFrame)
        preservesFloatingDashboardPosition = viewModel.isPresentedFromCapsule
        window?.isMovableByWindowBackground = viewModel.isPresentedFromCapsule
        viewModel.isExpanded = true
        window?.makeKeyAndOrderFront(nil)
    }

    // 图钉仅影响当前悬浮面板生命周期，不持久化也不改变刘海模式。
    private func toggleFloatingPanelPin() {
        guard viewModel.isExpanded, viewModel.isPresentedFromCapsule else { return }
        viewModel.isPinned.toggle()
    }

    // 关闭按钮是显式操作，即使面板已固定也立即收起并清除固定状态。
    private func closeFloatingPanel() {
        viewModel.isPinned = false
        setExpanded(false)
    }

    // 收起态左键点击直接展开；展开后的列表点击继续交给 SwiftUI 处理。
    private func handleLeftMouseDown(_ event: NSEvent) -> Bool {
        guard !viewModel.isExpanded else { return false }
        revealFromNotchEntry()
        return true
    }

    private func isMouseInsidePanelOrEntry() -> Bool {
        guard let window else { return false }
        let mouseLocation = NSEvent.mouseLocation
        if window.frame.insetBy(dx: -2, dy: -2).contains(mouseLocation) {
            return true
        }
        return externalEntryWindow?.frame.insetBy(dx: -2, dy: -2).contains(mouseLocation) == true
    }

    private func setExpanded(_ isExpanded: Bool) {
        guard viewModel.isExpanded != isExpanded else { return }
        // 展开先放大窗口再显示内容；收起先隐藏内容再缩小窗口，避免内容尺寸和窗口约束互相追赶。
        if isExpanded {
            let anchorFrame = keepsCollapsedEntryVisible ? window?.frame : activeEntryAnchorFrame
            activeEntryAnchorFrame = anchorFrame
            viewModel.isPresentedFromCapsule = !keepsCollapsedEntryVisible
            setFloatingDashboardResizable(viewModel.isPresentedFromCapsule)
            preservesFloatingDashboardPosition = false
            positionWindow(isExpanded: true, anchorFrame: anchorFrame)
            preservesFloatingDashboardPosition = viewModel.isPresentedFromCapsule
            window?.isMovableByWindowBackground = viewModel.isPresentedFromCapsule
            viewModel.isExpanded = true
        } else {
            viewModel.isPinned = false
            setFloatingDashboardResizable(false)
            // 面板收起后关闭背景拖拽，避免刘海入口被意外移动。
            window?.isMovableByWindowBackground = false
            viewModel.isExpanded = false
            viewModel.expandedScale = 1
            activeEntryAnchorFrame = nil
            presentationScreen = nil
            centersExpandedPanel = false
            preservesFloatingDashboardPosition = false
            guard keepsCollapsedEntryVisible else {
                window?.orderOut(nil)
                return
            }
            positionWindow(isExpanded: false)
            window?.orderFrontRegardless()
        }
    }

    // 刘海入口右键菜单保留设置和退出，并新增切换到胶囊模式。
    private func showContextMenu(with event: NSEvent) {
        guard let contentView = window?.contentView else { return }
        NSMenu.popUpContextMenu(contextMenu, with: event, for: contentView)
    }

    // 只有悬浮 Dashboard 开启原生边缘缩放，刘海入口与普通展开面板保持固定尺寸。
    private func setFloatingDashboardResizable(_ isResizable: Bool) {
        guard let window else { return }
        if isResizable {
            window.styleMask.insert(.resizable)
            window.minSize = FloatingDashboardSettings.minimumSize
            window.maxSize = FloatingDashboardSettings.maximumSize
        } else {
            window.styleMask.remove(.resizable)
            window.minSize = .zero
        }
    }

    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        let switchItem = NSMenuItem(title: "切换到悬浮模式", action: #selector(handleToggleMode), keyEquivalent: "")
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
        // 悬浮 Dashboard 初始定位后保留用户坐标，不被状态刷新或错误提示重新居中。
        guard !(isExpanded && viewModel.isPresentedFromCapsule && preservesFloatingDashboardPosition) else { return }
        let screen = presentationScreen ?? anchorFrame.flatMap { anchor in NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) } } ?? window.screen ?? NSScreen.main
        let collapsedSize = NotchWindowMetrics.collapsedSize(for: screen)
        if viewModel.collapsedHeight != collapsedSize.height {
            viewModel.collapsedHeight = collapsedSize.height
        }
        let isFloatingDashboard = isExpanded && viewModel.isPresentedFromCapsule
        let size = isFloatingDashboard ? floatingDashboardSettings.size : (isExpanded ? NotchWindowMetrics.expandedSize(for: viewModel.state, collapsedHeight: collapsedSize.height, hasJumpError: viewModel.jumpError != nil, scale: viewModel.expandedScale) : collapsedSize)
        let origin = isExpanded ? expandedOrigin(for: size, on: screen, anchorFrame: anchorFrame) : NotchWindowMetrics.origin(for: size, on: screen)
        let frame = CGRect(origin: origin, size: size)
        guard window.frame != frame else { return }
        window.setFrame(frame, display: true)
    }

    // 猫咪和全局快捷键居中显示；刘海入口继续从顶部锚点向下展开。
    private func expandedOrigin(for size: CGSize, on screen: NSScreen?, anchorFrame: CGRect?) -> CGPoint {
        if centersExpandedPanel {
            return NotchWindowMetrics.centeredPanelOrigin(for: size, on: screen)
        }
        return NotchWindowMetrics.panelOrigin(for: size, on: screen, anchorFrame: anchorFrame, includeAnchorArea: keepsCollapsedEntryVisible)
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
                controller.toggleForKeyboard()
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
            toggleForKeyboard()
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
