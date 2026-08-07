import AppKit
import SwiftUI

// 提供 SwiftUI 应用入口，实际窗口由 AppKit delegate 创建。
@main
struct CodexNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: HotKeySettings.shared, capsuleSettings: CapsuleSettings.shared, completionPopupSettings: CompletionPopupSettings.shared, pairingStore: PairingStore.shared, lanStatusServer: LANStatusServer.shared)
        }
    }
}

// 启动时创建刘海窗口，并每 1 秒从 Codex 本地状态刷新一次。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let reader = CodexStoreReader()
    private let jumpRouter = JumpRouter()
    private let alertNotifier = SessionAlertNotifier()
    private let hotKeySettings = HotKeySettings.shared
    private let capsuleSettings = CapsuleSettings.shared
    private let completionPopupSettings = CompletionPopupSettings.shared
    private let pairingStore = PairingStore.shared
    private let lanStatusServer = LANStatusServer.shared
    private var notchWindowController: NotchWindowController?
    private var statusBarItemController: StatusBarItemController?
    private lazy var completionPopupController = CompletionPopupController(settings: completionPopupSettings, onOpenSession: { [weak self] session in
        self?.jump(to: session)
    })
    private lazy var settingsWindowController = SettingsWindowController(settings: hotKeySettings, capsuleSettings: capsuleSettings, completionPopupSettings: completionPopupSettings, pairingStore: pairingStore, lanStatusServer: lanStatusServer)
    private var refreshTimer: Timer?
    private var displayMode: EntryDisplayMode = .notchCentered

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        alertNotifier.requestAuthorization()
        lanStatusServer.start(pairingStore: pairingStore)
        let initialState = StatusMapper.map(sessions: [], now: Date())
        let controller = NotchWindowController(initialState: initialState, hotKeySettings: hotKeySettings, onSelectSession: { [weak self] session in
            self?.jump(to: session)
        }, onOpenSettings: { [weak self] in
            self?.openSettings()
        }, onQuit: {
            NSApp.terminate(nil)
        }, onToggleMode: { [weak self] in
            self?.toggleDisplayMode()
        })
        notchWindowController = controller
        let statusController = StatusBarItemController(initialState: initialState, capsuleSettings: capsuleSettings, onActivate: { [weak self] entryFrame in
            self?.notchWindowController?.toggleFromStatusItem(entryFrame: entryFrame)
        }, onOpenSettings: { [weak self] in
            self?.openSettings()
        }, onQuit: {
            NSApp.terminate(nil)
        }, onToggleMode: { [weak self] in
            self?.toggleDisplayMode()
        })
        statusBarItemController = statusController
        // 排除猫咪自身点击的外部收起事件，确保第二次单击可以稳定关闭 Dashboard。
        notchWindowController?.setExternalEntryWindow(statusController.entryWindow)
        applyDisplayMode()
        refreshStatus()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        lanStatusServer.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func refreshStatus() {
        let snapshot = reader.loadSnapshot()
        let state = StatusMapper.map(snapshot: snapshot)
        notchWindowController?.update(state: state)
        statusBarItemController?.update(state: state)
        lanStatusServer.broadcast(snapshot: LANStatusSnapshotMapper.snapshot(from: state))
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

// 运行期入口展示模式不持久化，启动始终回到刘海居中。
private enum EntryDisplayMode {
    case notchCentered
    case capsule
}

// 持有独立设置窗口，确保无 Dock 和菜单栏入口的 accessory app 也能从右键菜单打开设置。
private final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(settings: HotKeySettings, capsuleSettings: CapsuleSettings, completionPopupSettings: CompletionPopupSettings, pairingStore: PairingStore, lanStatusServer: LANStatusServer) {
        // 设置页新增目录颜色取色盘后扩展窗口高度，避免局域网配置被裁切。
        let contentSize = CGSize(width: 520, height: 625)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: contentSize), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Codex Notch 设置"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, capsuleSettings: capsuleSettings, completionPopupSettings: completionPopupSettings, pairingStore: pairingStore, lanStatusServer: lanStatusServer))
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
