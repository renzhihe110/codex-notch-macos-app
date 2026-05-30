import AppKit
import SwiftUI

// 提供 SwiftUI 应用入口，实际窗口由 AppKit delegate 创建。
@main
struct CodexNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: HotKeySettings.shared)
        }
    }
}

// 启动时创建刘海窗口，并每 1 秒从 Codex 本地状态刷新一次。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let reader = CodexStoreReader()
    private let jumpRouter = JumpRouter()
    private let alertNotifier = SessionAlertNotifier()
    private let hotKeySettings = HotKeySettings.shared
    private var notchWindowController: NotchWindowController?
    private var statusBarItemController: StatusBarItemController?
    private lazy var settingsWindowController = SettingsWindowController(settings: hotKeySettings)
    private var refreshTimer: Timer?

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
        })
        notchWindowController = controller
        statusBarItemController = StatusBarItemController(initialState: initialState) { [weak self] anchorFrame in
            self?.notchWindowController?.revealFromStatusItem(anchorFrame: anchorFrame)
        }
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

    private func refreshStatus() {
        let snapshot = reader.loadSnapshot()
        let state = StatusMapper.map(snapshot: snapshot)
        notchWindowController?.update(state: state)
        statusBarItemController?.update(state: state)
        alertNotifier.notifyIfNeeded(for: state.sessions)
    }

    // 从右键菜单直接打开设置窗口，避免 accessory app 没有 Settings responder 时点击无反应。
    private func openSettings() {
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

// 持有独立设置窗口，确保无 Dock 和菜单栏入口的 accessory app 也能从右键菜单打开设置。
private final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(settings: HotKeySettings) {
        let contentSize = CGSize(width: 420, height: 150)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: contentSize), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Codex Notch 设置"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
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
