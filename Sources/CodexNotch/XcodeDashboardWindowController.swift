import AppKit
import Carbon
import SwiftUI

// 无边框 Xcode Dashboard 需要成为 key window，才能可靠处理 Escape、失焦收起和列表点击。
private final class XcodeDashboardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// 独立管理 Xcode Dashboard 的窗口、刷新计时器和 Carbon 全局快捷键。
final class XcodeDashboardWindowController: NSWindowController, NSWindowDelegate {
    private let manager = XcodeWindowManager()
    private let presentationState = XcodeDashboardPresentationState()
    private let hotKeySettings: XcodeHotKeySettings
    private let onWillReveal: () -> Void
    private let onOpenSettings: () -> Void
    private var refreshTimer: Timer?
    private var localKeyEventMonitor: Any?
    private var localMouseEventMonitor: Any?
    private var hotKeySettingsObserver: NSObjectProtocol?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var registeredHotKey: HotKey?
    private static let hotKeySignature = OSType(0x58434458)
    private static let hotKeyIdentifier: UInt32 = 2

    // 初始化时直接注册独立 Xcode 快捷键，窗口保持隐藏直到用户触发。
    init(hotKeySettings: XcodeHotKeySettings, onWillReveal: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.hotKeySettings = hotKeySettings
        self.onWillReveal = onWillReveal
        self.onOpenSettings = onOpenSettings
        let window = XcodeDashboardWindow(contentRect: CGRect(origin: .zero, size: XcodeDashboardMetrics.size), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        configure(window)
        let hostingView = NSHostingView(rootView: XcodeDashboardView(manager: manager, presentationState: presentationState, onSelectWindow: { [weak self] item in self?.activate(item) }, onTogglePin: { [weak self] in self?.togglePin() }, onOpenSettings: { [weak self] in self?.openSettings() }, onClose: { [weak self] in self?.closeDashboard() }, onOpenAccessibilitySettings: { [weak self] in self?.openAccessibilitySettings() }))
        // Xcode Dashboard 尺寸由 NSWindow 原生缩放控制，避免 SwiftUI 把窗口锁回初始尺寸。
        hostingView.sizingOptions = []
        window.contentView = hostingView
        syncContentSizeFromWindow()
        installKeyboardHandling()
        installWindowDragging()
    }

    // 释放控制器时注销全部 Carbon 与 AppKit 监听，避免应用退出阶段残留回调。
    deinit {
        stopRefreshing()
        if let localKeyEventMonitor { NSEvent.removeMonitor(localKeyEventMonitor) }
        if let localMouseEventMonitor { NSEvent.removeMonitor(localMouseEventMonitor) }
        if let hotKeySettingsObserver { NotificationCenter.default.removeObserver(hotKeySettingsObserver) }
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let hotKeyHandlerRef { RemoveEventHandler(hotKeyHandlerRef) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // 快捷键采用显式 toggle，打开前先收起 Codex Dashboard 并刷新 Xcode 窗口列表。
    func toggleForKeyboard() {
        guard window?.isVisible != true else { closeDashboard(); return }
        onWillReveal()
        manager.refresh(requestPermission: true)
        positionOnPointerScreen()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        startRefreshing()
    }

    // 互斥协调、快捷键关闭和关闭按钮都通过同一入口隐藏窗口，并清除当前图钉状态。
    func hide() { presentationState.isPinned = false; stopRefreshing(); window?.orderOut(nil) }

    // 点击面板外或切到其他应用时自动收起，确保 Xcode 与 Codex 面板不同时停留。
    func windowDidResignKey(_ notification: Notification) { guard !presentationState.isPinned else { return }; hide() }

    // 无边框窗口的原生缩放需要 delegate 兜底，防止拖到内容不可用的小尺寸。
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize { clampedDashboardSize(frameSize) }

    // 每次拖拽缩放后同步 SwiftUI 根视图尺寸，避免内容保持旧宽高被裁切。
    func windowDidResize(_ notification: Notification) { syncContentSizeFromWindow() }

    // 窗口居中到鼠标所在屏幕，并保留用户本次运行中拖拽缩放后的尺寸。
    private func positionOnPointerScreen() {
        guard let window else { return }
        let pointerLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointerLocation) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let size = clampedDashboardSize(window.frame.size)
        presentationState.size = size
        let origin = CGPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2)
        window.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    // 无边框浮层使用透明窗口承载 UI 稿中的 22pt 圆角石墨外壳。
    private func configure(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        // 与 Codex 悬浮面板一致关闭原生窗口阴影，避免圆角外侧出现额外黑边。
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.minSize = XcodeDashboardMetrics.minimumSize
        window.maxSize = XcodeDashboardMetrics.maximumSize
        window.contentMinSize = XcodeDashboardMetrics.minimumSize
        window.contentMaxSize = XcodeDashboardMetrics.maximumSize
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
    }

    // SwiftUI 内容尺寸只跟随 Xcode Dashboard 窗口，不参与 Codex 面板尺寸计算。
    private func syncContentSizeFromWindow() { guard let window else { return }; presentationState.size = clampedDashboardSize(window.frame.size) }

    // 把用户拖拽尺寸限制在可读范围内，避免标题栏、按钮和空态内容被裁切。
    private func clampedDashboardSize(_ size: CGSize) -> CGSize { CGSize(width: min(max(size.width, XcodeDashboardMetrics.minimumSize.width), XcodeDashboardMetrics.maximumSize.width), height: min(max(size.height, XcodeDashboardMetrics.minimumSize.height), XcodeDashboardMetrics.maximumSize.height)) }

    // Dashboard 可见时每秒同步 Xcode 窗口打开、关闭和当前焦点变化。
    private func startRefreshing() { stopRefreshing(); refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.manager.refresh() } }

    // 窗口隐藏后立即停止轮询，避免后台持续访问 Accessibility API。
    private func stopRefreshing() { refreshTimer?.invalidate(); refreshTimer = nil }

    // SwiftUI 内容会覆盖整个无边框窗口，因此显式把顶部非控件区域转发为原生窗口拖拽。
    private func installWindowDragging() { localMouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in guard let self, let window = self.window, event.window === window, self.isWindowDragArea(event.locationInWindow, window: window) else { return event }; window.performDrag(with: event); return nil } }

    // 仅允许拖动标题栏左侧与中间空白区，并避开边缘缩放热区和右侧按钮。
    private func isWindowDragArea(_ location: CGPoint, window: NSWindow) -> Bool { let inset = XcodeDashboardMetrics.resizeHandleInset; return location.y >= window.frame.height - XcodeDashboardMetrics.headerHeight && location.y < window.frame.height - inset && location.x > inset && location.x < window.frame.width - 112 }

    // 行点击成功后收起 Dashboard，让目标 Xcode 窗口直接成为视觉焦点。
    private func activate(_ item: XcodeWindowItem) { if manager.activate(item), !presentationState.isPinned { hide() } }

    // 图钉只影响当前 Xcode Dashboard 生命周期，不持久化也不改变 Codex 面板。
    private func togglePin() { presentationState.isPinned.toggle() }

    // 关闭按钮是显式操作，即使已固定也立即收起。
    private func closeDashboard() { hide() }

    // 设置按钮先关闭当前 Dashboard，再打开应用现有的统一设置窗口。
    private func openSettings() { closeDashboard(); onOpenSettings() }

    // 权限按钮打开系统辅助功能设置，系统切换应用时窗口会通过失焦自动收起。
    private func openAccessibilitySettings() { guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }; NSWorkspace.shared.open(url) }

    // 本地 Escape 与全局 Xcode 快捷键共用同一套键盘控制。
    private func installKeyboardHandling() {
        localKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape), self.window?.isKeyWindow == true { self.hide(); return nil }
            if self.hotKeySettings.matches(event) { self.toggleForKeyboard(); return nil }
            return event
        }
        hotKeySettingsObserver = NotificationCenter.default.addObserver(forName: XcodeHotKeySettings.changedNotification, object: hotKeySettings, queue: .main) { [weak self] _ in self?.reloadGlobalHotKey() }
        installGlobalHotKeyHandler()
        reloadGlobalHotKey()
    }

    // Carbon 回调只处理 Xcode 自己的签名，其他热键返回 eventNotHandledErr 继续传给 Codex 注册器。
    private func installGlobalHotKeyHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            var pressedHotKeyID = EventHotKeyID(signature: 0, id: 0)
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &pressedHotKeyID)
            guard status == noErr, pressedHotKeyID.signature == XcodeDashboardWindowController.hotKeySignature, pressedHotKeyID.id == XcodeDashboardWindowController.hotKeyIdentifier else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<XcodeDashboardWindowController>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { controller.toggleForKeyboard() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandlerRef)
        guard installStatus == noErr else { hotKeySettings.reportRegistrationFailure(); return }
    }

    // Xcode 快捷键注册使用独立签名和 ID，不复用 Codex 的 Carbon 标识。
    private func registerConfiguredHotKey(_ hotKey: HotKey) -> EventHotKeyRef? {
        guard hotKeyHandlerRef != nil else { return nil }
        var registeredHotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyIdentifier)
        guard RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &registeredHotKeyRef) == noErr else { return nil }
        return registeredHotKeyRef
    }

    // 修改快捷键失败时恢复上一条已生效配置，避免设置页显示无法触发的组合键。
    private func reloadGlobalHotKey() {
        let requestedHotKey = hotKeySettings.hotKey
        guard registeredHotKey != requestedHotKey else { hotKeySettings.clearRegistrationFailure(); return }
        let previousHotKey = registeredHotKey
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        if let newHotKeyRef = registerConfiguredHotKey(requestedHotKey) { hotKeyRef = newHotKeyRef; registeredHotKey = requestedHotKey; hotKeySettings.clearRegistrationFailure(); return }
        if let previousHotKey, let restoredHotKeyRef = registerConfiguredHotKey(previousHotKey) { hotKeyRef = restoredHotKeyRef; registeredHotKey = previousHotKey; hotKeySettings.restoreAfterRegistrationFailure(previousHotKey); return }
        registeredHotKey = nil
        hotKeySettings.reportRegistrationFailure()
    }
}
