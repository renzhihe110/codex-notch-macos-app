import AppKit
import SwiftUI

// 提供 SwiftUI 应用入口，实际窗口由 AppKit delegate 创建。
@main
struct CodexNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            // 系统“设置…”命令复用自建窗口，避免 SwiftUI 额外创建带原生标题栏的第二个设置窗口。
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { appDelegate.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

// 启动时创建刘海窗口，并每 1 秒从 Codex 本地状态刷新一次。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let reader = CodexStoreReader()
    // 所有 Codex 日志读取都在同一后台队列执行，避免首次大文件扫描阻塞宠物首帧或并发访问游标。
    private let refreshQueue = DispatchQueue(label: "local.codex.notch.refresh", qos: .utility)
    private let jumpRouter = JumpRouter()
    private let alertNotifier = SessionAlertNotifier()
    private let hotKeySettings = HotKeySettings.shared
    private let xcodeHotKeySettings = XcodeHotKeySettings.shared
    private let capsuleSettings = CapsuleSettings.shared
    private let completionPopupSettings = CompletionPopupSettings.shared
    private let petCatalog = CodexPetCatalog.shared
    private var notchWindowController: NotchWindowController?
    private var xcodeDashboardWindowController: XcodeDashboardWindowController?
    private var statusBarItemController: StatusBarItemController?
    private lazy var completionPopupController = CompletionPopupController(settings: completionPopupSettings, onOpenSession: { [weak self] session in
        self?.jump(to: session)
    })
    private lazy var settingsWindowController = SettingsWindowController(settings: hotKeySettings, xcodeHotKeySettings: xcodeHotKeySettings, capsuleSettings: capsuleSettings, completionPopupSettings: completionPopupSettings, petCatalog: petCatalog)
    private var refreshTimer: Timer?
    private var isRefreshInFlight = false
    private var hasLoadedInitialSnapshot = false
    private var displayMode: EntryDisplayMode = .capsule

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        alertNotifier.requestAuthorization()
        let initialState = StatusMapper.map(sessions: [], now: Date())
        let controller = NotchWindowController(initialState: initialState, hotKeySettings: hotKeySettings, onSelectSession: { [weak self] session in
            self?.jump(to: session)
        }, onOpenSettings: { [weak self] in
            self?.openSettings()
        }, onQuit: {
            NSApp.terminate(nil)
        }, onToggleMode: { [weak self] in
            self?.toggleDisplayMode()
        }, onWillReveal: { [weak self] in
            self?.xcodeDashboardWindowController?.hide()
        })
        notchWindowController = controller
        // Xcode Dashboard 使用独立窗口和快捷键，打开前只负责收起当前 Codex 展开面板。
        xcodeDashboardWindowController = XcodeDashboardWindowController(hotKeySettings: xcodeHotKeySettings, onWillReveal: { [weak self] in
            self?.notchWindowController?.dismissDashboard()
        }, onOpenSettings: { [weak self] in
            self?.openSettings()
        })
        let statusController = StatusBarItemController(initialState: initialState, capsuleSettings: capsuleSettings, petCatalog: petCatalog, onActivate: { [weak self] entryFrame in
            self?.notchWindowController?.toggleFromStatusItem(entryFrame: entryFrame)
        }, onOpenSettings: { [weak self] in
            self?.openSettings()
        }, onQuit: {
            NSApp.terminate(nil)
        }, onToggleMode: { [weak self] in
            self?.toggleDisplayMode()
        })
        statusBarItemController = statusController
        // 排除宠物自身点击的外部收起事件，确保第二次单击可以稳定关闭 Dashboard。
        notchWindowController?.setExternalEntryWindow(statusController.entryWindow)
        applyDisplayMode()
        refreshStatus()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // 后台读取尚未结束时合并后续刷新，避免每秒定时器堆积相同的大文件扫描。
    private func refreshStatus() {
        guard !isRefreshInFlight else { return }
        isRefreshInFlight = true
        let shouldLoadTitlePreview = !hasLoadedInitialSnapshot
        refreshQueue.async { [weak self] in
            guard let self else { return }
            if shouldLoadTitlePreview {
                let titleSnapshot = self.reader.loadTitleSnapshot()
                DispatchQueue.main.async { [weak self] in self?.applyTitlePreview(snapshot: titleSnapshot) }
            }
            let snapshot = self.reader.loadSnapshot()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRefreshInFlight = false
                self.hasLoadedInitialSnapshot = true
                self.apply(snapshot: snapshot)
            }
        }
    }

    // 标题预览只刷新可见内容，完整状态到达前不发送通知或完成事件。
    private func applyTitlePreview(snapshot: CodexStoreSnapshot) {
        let state = StatusMapper.map(snapshot: snapshot)
        notchWindowController?.update(state: state)
        statusBarItemController?.update(state: state)
    }

    // 状态读取完成后统一回到主线程更新窗口和通知。
    private func apply(snapshot: CodexStoreSnapshot) {
        let state = StatusMapper.map(snapshot: snapshot)
        notchWindowController?.update(state: state)
        statusBarItemController?.update(state: state)
        alertNotifier.notifyIfNeeded(for: state.sessions)
        // 首次读取失败且没有会话时不建立完成基线，避免恢复读取后误弹历史完成任务。
        if !snapshot.sessions.isEmpty || snapshot.errors.isEmpty {
            completionPopupController.showIfNeededFor(sessions: state.sessions)
        }
    }

    // 入口模式只影响桌面入口形态，不触碰会话状态、热键和通知刷新。
    private func switchDisplayMode(to mode: EntryDisplayMode) {
        guard displayMode != mode else { return }
        displayMode = mode
        applyDisplayMode()
    }

    // 两个入口都通过同一切换动作互相跳转，悬浮 Dashboard 的右键菜单也能正确返回刘海模式。
    private func toggleDisplayMode() {
        switch displayMode {
        case .notchCentered:
            switchDisplayMode(to: .capsule)
        case .capsule:
            switchDisplayMode(to: .notchCentered)
        }
    }

    // 两种入口互斥显示；胶囊每次切换进入都回到默认位置。
    private func applyDisplayMode() {
        switch displayMode {
        case .notchCentered:
            statusBarItemController?.hideEntry()
            notchWindowController?.showCollapsed()
        case .capsule:
            notchWindowController?.hideEntry()
            statusBarItemController?.showEntry(resetPosition: true)
        }
    }

    // 从右键菜单直接打开设置窗口，避免 accessory app 没有 Settings responder 时点击无反应。
    func openSettings() {
        notchWindowController?.dismissDashboard()
        xcodeDashboardWindowController?.hide()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController.show()
    }

    // 将会话点击交给跳转路由，并把失败原因反馈到展开面板顶部。
    private func jump(to session: CodexSession) {
        notchWindowController?.clearJumpError()
        jumpRouter.jump(to: session) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.notchWindowController?.clearJumpError()
                case .failure(let error):
                    self?.notchWindowController?.showJumpError(error.localizedDescription)
                }
            }
        }
    }

}

// 运行期入口展示模式不持久化，启动始终直接显示当前已保存的悬浮宠物。
private enum EntryDisplayMode {
    case notchCentered
    case capsule
}

// 持有独立设置窗口，确保无 Dock 和菜单栏入口的 accessory app 也能从右键菜单打开设置。
private final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(settings: HotKeySettings, xcodeHotKeySettings: XcodeHotKeySettings, capsuleSettings: CapsuleSettings, completionPopupSettings: CompletionPopupSettings, petCatalog: CodexPetCatalog) {
        // 使用 UI 稿对应的高窄比例和沉浸式标题栏，较小屏幕仍可通过内容滚动访问全部设置。
        let contentSize = CGSize(width: 470, height: 838)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: contentSize), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Codex Notch 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 0.035, green: 0.055, blue: 0.071, alpha: 1)
        window.isMovableByWindowBackground = true
        window.contentMinSize = CGSize(width: 450, height: 640)
        window.contentMaxSize = CGSize(width: 560, height: 900)
        window.isReleasedWhenClosed = false
        // 隐藏原生交通灯，由内容视图中的自定义按钮提供同等窗口操作。
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, xcodeHotKeySettings: xcodeHotKeySettings, capsuleSettings: capsuleSettings, completionPopupSettings: completionPopupSettings, petCatalog: petCatalog))
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    // 每次打开都置顶并聚焦，避免窗口已经存在但藏在其他应用后面。
    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }
}
