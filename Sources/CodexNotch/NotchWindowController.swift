import AppKit
import Carbon
import SwiftUI

// 集中管理刘海窗口的固定尺寸，避免视图和窗口定位出现魔法数字。
enum NotchWindowMetrics {
    static let collapsedWidth: CGFloat = 320
    static let defaultCollapsedHeight: CGFloat = 30
    static let expandedSize = CGSize(width: 390, height: 320)

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
    static func panelOrigin(for size: CGSize, on screen: NSScreen?, anchorFrame: CGRect?) -> CGPoint {
        guard let screen else { return .zero }
        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 8
        let proposedX = anchorFrame.map { $0.midX - size.width / 2 } ?? visibleFrame.maxX - size.width - margin
        let minX = visibleFrame.minX + margin
        let maxX = visibleFrame.maxX - size.width - margin
        let proposedTopY = anchorFrame?.minY ?? visibleFrame.maxY
        let y = max(visibleFrame.minY + margin, min(proposedTopY - size.height, visibleFrame.maxY - size.height))
        return CGPoint(x: min(max(proposedX, minX), maxX), y: y)
    }
}

// 无边框窗口默认不能成为 key，显式允许后失焦回调才能可靠收起。
private final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// 创建并定位桌面顶部中间的透明无边框刘海窗口。
final class NotchWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: NotchViewModel
    private let hotKeySettings: HotKeySettings
    private let onSelectSession: (CodexSession) -> Void
    private var collapseWorkItem: DispatchWorkItem?
    private var localKeyEventMonitor: Any?
    private var hotKeySettingsObserver: NSObjectProtocol?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var registeredHotKey: HotKey?
    private let collapseDelay: TimeInterval = 0.20

    init(initialState: NotchState, hotKeySettings: HotKeySettings, onSelectSession: @escaping (CodexSession) -> Void, onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        let collapsedSize = NotchWindowMetrics.collapsedSize(for: NSScreen.main)
        self.viewModel = NotchViewModel(state: initialState, collapsedHeight: collapsedSize.height)
        self.hotKeySettings = hotKeySettings
        self.onSelectSession = onSelectSession
        let window = KeyableBorderlessWindow(contentRect: CGRect(origin: .zero, size: collapsedSize), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: NotchView(model: viewModel, onSelectSession: onSelectSession, onOpenSettings: onOpenSettings, onQuit: onQuit, onHoverChanged: { [weak self] isHovered in self?.handleHoverChanged(isHovered) }))
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    // 外部轮询刷新只替换展示状态，不改变当前展开/收起状态。
    func update(state: NotchState) {
        viewModel.state = state
        normalizeSelectedSessionIndex()
    }

    // 展示跳转失败信息，保留用户当前展开状态。
    func showJumpError(_ message: String) {
        viewModel.jumpError = message
    }

    // 清理上一条跳转错误，避免成功后继续误导用户。
    func clearJumpError() {
        viewModel.jumpError = nil
    }

    // 窗口失焦时收起，外部点击的完整全局监听留给后续任务。
    func windowDidResignKey(_ notification: Notification) {
        collapseWorkItem?.cancel()
        setExpanded(false)
    }

    // 全局快捷键调用这个入口时，主动激活应用并展开面板，方便继续用方向键操作。
    func revealForKeyboard() {
        reveal(anchorFrame: nil)
    }

    // 状态栏项点击后，从对应按钮下方展开面板。
    func revealFromStatusItem(anchorFrame: CGRect?) {
        reveal(anchorFrame: anchorFrame)
    }

    // 统一展开入口，确保状态栏点击和热键行为一致。
    private func reveal(anchorFrame: CGRect?) {
        collapseWorkItem?.cancel()
        normalizeSelectedSessionIndex()
        NSApp.activate(ignoringOtherApps: true)
        positionWindow(isExpanded: true, anchorFrame: anchorFrame)
        viewModel.isExpanded = true
        window?.makeKeyAndOrderFront(nil)
    }

    private func handleHoverChanged(_ isHovered: Bool) {
        collapseWorkItem?.cancel()
        if isHovered {
            setExpanded(true)
            return
        }
        // 展开动画会短暂触发 hover false，延迟后再确认鼠标是否真的离开窗口。
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isMouseInsideWindow() else { return }
            self.setExpanded(false)
        }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: workItem)
    }

    private func isMouseInsideWindow() -> Bool {
        guard let window else { return false }
        // 使用全局鼠标坐标和窗口 frame 对比，避免 SwiftUI 重绘期间的命中测试抖动。
        return window.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func setExpanded(_ isExpanded: Bool) {
        guard viewModel.isExpanded != isExpanded else { return }
        // 展开先放大窗口再显示内容；收起先隐藏内容再缩小窗口，避免内容尺寸和窗口约束互相追赶。
        if isExpanded {
            positionWindow(isExpanded: true)
            viewModel.isExpanded = true
        } else {
            viewModel.isExpanded = false
            window?.orderOut(nil)
        }
    }

    private func positionWindow(isExpanded: Bool, anchorFrame: CGRect? = nil) {
        guard let window else { return }
        let screen = window.screen ?? NSScreen.main
        let collapsedSize = NotchWindowMetrics.collapsedSize(for: screen)
        let size = isExpanded ? NotchWindowMetrics.expandedSize : collapsedSize
        if viewModel.collapsedHeight != collapsedSize.height {
            viewModel.collapsedHeight = collapsedSize.height
        }
        // 展开时跟随系统状态栏项，收起兜底位置仅供内部尺寸计算使用。
        let origin = isExpanded ? NotchWindowMetrics.panelOrigin(for: size, on: screen, anchorFrame: anchorFrame) : NotchWindowMetrics.origin(for: size, on: screen)
        let frame = CGRect(origin: origin, size: size)
        window.setFrame(frame, display: true)
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
        min(viewModel.state.sessions.count, 8)
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
