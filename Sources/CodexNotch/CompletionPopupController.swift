import AppKit
import SwiftUI

// 管理任务完成时的一次性透明提示窗，避免把完成提醒逻辑塞进刘海窗口控制器。
final class CompletionPopupController {
    private let onOpenSession: (CodexSession) -> Void
    private let settings: CompletionPopupSettings
    private var window: NSWindow?
    private var dismissWorkItem: DispatchWorkItem?
    private var seenCompletionKeys = Set<String>()
    private var hasCapturedInitialSnapshot = false

    init(settings: CompletionPopupSettings = .shared, onOpenSession: @escaping (CodexSession) -> Void) {
        self.settings = settings
        self.onOpenSession = onOpenSession
    }

    // 首次刷新只记录历史完成态；后续刷新遇到新的 task_complete 才弹出提示窗。
    func showIfNeededFor(sessions: [CodexSession]) {
        let completionSessions = sessions.filter(isCompletionSession)
        let completionKeys = Set(completionSessions.map { completionKey(for: $0) })
        guard hasCapturedInitialSnapshot else {
            seenCompletionKeys.formUnion(completionKeys)
            hasCapturedInitialSnapshot = true
            return
        }
        let newSessions = completionSessions.filter { !seenCompletionKeys.contains(completionKey(for: $0)) }
        seenCompletionKeys.formUnion(completionKeys)
        guard let session = newSessions.max(by: { completionSortDate(for: $0) < completionSortDate(for: $1) }) else { return }
        show(session: session)
    }

    // 关闭窗口并取消自动关闭任务，供按钮点击和用户配置的计时共用。
    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        window?.orderOut(nil)
    }

    // 每次展示都重建 SwiftUI root view，让按钮闭包捕获当前完成会话。
    private func show(session: CodexSession) {
        dismiss()
        let popupWindow = window ?? makeWindow()
        popupWindow.contentView = CompletionPopupHostingView(rootView: CompletionPopupView(session: session, onOpen: { [weak self] in
            self?.dismiss()
            self?.onOpenSession(session)
        }))
        window = popupWindow
        position(window: popupWindow)
        popupWindow.orderFrontRegardless()
        scheduleDismiss()
    }

    // 透明无边框窗口保持置顶且不展示系统标题栏。
    private func makeWindow() -> NSWindow {
        let size = CompletionPopupMetrics.windowSize
        let window = CompletionPopupWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        return window
    }

    // 弹窗固定放在主屏可见区域中心，避开菜单栏和 Dock。
    private func position(window: NSWindow) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? .zero
        let size = CompletionPopupMetrics.windowSize
        let origin = CGPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2)
        window.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    // 无操作达到用户设置的秒数后自动收起，新的完成提示会先取消旧计时。
    private func scheduleDismiss() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.dismissDelay, execute: workItem)
    }

    private func isCompletionSession(_ session: CodexSession) -> Bool {
        session.status == .green && session.lastEvent == "task_complete"
    }

    private func completionKey(for session: CodexSession) -> String {
        guard let completionEventAt = session.completionEventAt else { return "\(session.id):task_complete" }
        return "\(session.id):\(Int64((completionEventAt.timeIntervalSince1970 * 1000).rounded()))"
    }

    private func completionSortDate(for session: CodexSession) -> Date {
        session.completionEventAt ?? session.updatedAt
    }
}

// 完成弹窗尺寸集中定义，避免视图和窗口控制器各自散落魔法数字。
private enum CompletionPopupMetrics {
    static let windowSize = CGSize(width: 360, height: 154)
}

// 允许无边框完成提示窗接收按钮点击，同时不参与主窗口生命周期。
private final class CompletionPopupWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// 允许非激活应用里的完成弹窗第一下点击就触发按钮。
private final class CompletionPopupHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    // 透明窗口的 SwiftUI 托管层也必须显式透明，否则外扩阴影区域会露出默认灰底。
    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

// 透明完成提示窗的 SwiftUI 内容，保持信息简短并把跳转入口固定在右下角。
private struct CompletionPopupView: View {
    let session: CodexSession
    let onOpen: () -> Void
    // 监听共享字体偏好，确保已显示的完成提示也会立即切换字体。
    @ObservedObject private var fontSettings = FontSettings.shared

    var body: some View {
        popupCard
            .frame(width: CompletionPopupMetrics.windowSize.width, height: CompletionPopupMetrics.windowSize.height)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black.opacity(0.76)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .background(Color.clear)
            .font(fontSettings.font(size: 13))
    }

    // 卡片主体保持原布局，外层 body 只负责圆角背景和内部描边。
    private var popupCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                completionIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text("任务已完成")
                        .font(fontSettings.font(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))
                    Text(session.displayTitle)
                        .font(fontSettings.font(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 12)
            HStack(alignment: .center, spacing: 8) {
                Text("\(session.cwdHint) · \(session.activityText)")
                    .font(fontSettings.font(size: 12))
                    .foregroundStyle(.white.opacity(0.54))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: onOpen) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(fontSettings.font(size: 12, weight: .semibold))
                        Text("打开")
                            .font(fontSettings.font(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.12))
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.white.opacity(0.94)))
                }
                .buttonStyle(.plain)
                .help("打开对话")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var completionIcon: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.12, green: 0.82, blue: 0.45).opacity(0.18))
            Circle()
                .stroke(Color(red: 0.34, green: 1.0, blue: 0.62).opacity(0.48), lineWidth: 1)
            Image(systemName: "checkmark")
                .font(fontSettings.font(size: 17, weight: .bold))
                .foregroundStyle(Color(red: 0.50, green: 1.0, blue: 0.68))
        }
        .frame(width: 44, height: 44)
    }
}
