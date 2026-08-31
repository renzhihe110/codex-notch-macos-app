import AppKit
import SwiftUI

// Xcode Dashboard 使用默认窗口比例启动，同时允许用户拖拽边缘缩放。
enum XcodeDashboardMetrics {
    static let size = CGSize(width: 800, height: 462)
    static let minimumSize = CGSize(width: 560, height: 320)
    static let maximumSize = CGSize(width: 1200, height: 900)
    static let headerHeight: CGFloat = 58
    static let footerHeight: CGFloat = 38
    static let rowHeight: CGFloat = 62
    static let resizeHandleInset: CGFloat = 6
}

// 只记录当前 Xcode Dashboard 展示状态，不持久化也不影响 Codex 面板。
final class XcodeDashboardPresentationState: ObservableObject {
    @Published var isPinned = false
    @Published var size = XcodeDashboardMetrics.size
}

// 以紧凑统一列表展示 Xcode 窗口，当前窗口仅使用蓝色左侧指示条和文字强调。
struct XcodeDashboardView: View {
    @ObservedObject var manager: XcodeWindowManager
    @ObservedObject var presentationState: XcodeDashboardPresentationState
    let onSelectWindow: (XcodeWindowItem) -> Void
    let onTogglePin: () -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void
    let onOpenAccessibilitySettings: () -> Void
    @ObservedObject private var fontSettings = FontSettings.shared
    @State private var hoveredWindowID: String?

    // 独立窗口只包含标题、项目列表和操作提示，不复用 Codex 任务状态或 Token 信息。
    var body: some View {
        VStack(spacing: 0) {
            dashboardHeader.frame(height: XcodeDashboardMetrics.headerHeight)
            dashboardContent.frame(maxWidth: .infinity, maxHeight: .infinity)
            dashboardFooter.frame(height: XcodeDashboardMetrics.footerHeight)
        }
        .frame(width: presentationState.size.width, height: presentationState.size.height, alignment: .top)
        .clipped()
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(red: 0.055, green: 0.063, blue: 0.071)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(red: 0.165, green: 0.188, blue: 0.216), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(.white)
        .font(fontSettings.font(size: 13))
        .preferredColorScheme(.dark)
    }

    // 标题栏使用真实 Xcode 图标和蓝灰数量标签，与 Codex 悬浮助手形成明确区分。
    private var dashboardHeader: some View {
        HStack(spacing: 9) {
            Image(nsImage: xcodeApplicationIcon).resizable().scaledToFit().frame(width: 24, height: 24)
            Text("Xcode 窗口助手").font(fontSettings.font(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.95))
            Text("\(manager.windows.count) 个窗口").font(fontSettings.font(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.55)).padding(.horizontal, 8).frame(height: 26).background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.055))).overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
            Spacer(minLength: 0)
            headerButton(systemName: presentationState.isPinned ? "pin.fill" : "pin", help: presentationState.isPinned ? "取消常驻" : "常驻面板", isActive: presentationState.isPinned, action: onTogglePin)
            headerButton(systemName: "gearshape", help: "打开设置", action: onOpenSettings)
            headerButton(systemName: "xmark", help: "关闭 Xcode 窗口助手", action: onClose)
        }
        .padding(.horizontal, 20)
    }

    // 主区在有数据时展示统一列表，异常状态则给出单一、可执行的说明。
    @ViewBuilder private var dashboardContent: some View {
        if manager.availability == .ready {
            windowList
        } else {
            availabilityView
        }
    }

    // Xcode 窗口卡沿用 Codex 任务卡的间距、圆角与深色分层，更多窗口在内部滚动。
    private var windowList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(manager.windows) { item in
                    windowRow(item)
                }
            }
            .padding(6)
        }
        .scrollIndicators(.visible)
        .padding(.horizontal, 20)
    }

    // 整行都是点击目标，悬停只轻微提亮，当前窗口额外显示左侧蓝条和状态文字。
    private func windowRow(_ item: XcodeWindowItem) -> some View {
        Button { onSelectWindow(item) } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color(red: 0.44, green: 0.76, blue: 1.0)).frame(width: 4, height: 42).opacity(item.isCurrent ? 1 : 0)
                Image(nsImage: xcodeApplicationIcon).resizable().scaledToFit().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.projectName).font(fontSettings.font(size: 19.5, weight: .medium)).foregroundStyle(.white.opacity(0.94)).lineLimit(1)
                    // 第二行优先展示分支与本地仓库目录，悬停提示保留原有当前文件信息。
                    HStack(spacing: 5) { Image(systemName: "arrow.triangle.branch").font(fontSettings.font(size: 12, weight: .semibold)).foregroundStyle(Color(red: 0.204, green: 0.827, blue: 0.600)); Text([item.branchName ?? "非 Git 项目", item.localDirectory ?? item.detail].joined(separator: " · ")).font(fontSettings.font(size: 15)).foregroundStyle(.white.opacity(0.54)).lineLimit(1).truncationMode(.middle) }.help(item.detail)
                }
                Spacer(minLength: 14)
                if item.isCurrent { Text("当前窗口").font(fontSettings.font(size: 15, weight: .semibold)).foregroundStyle(Color(red: 0.44, green: 0.76, blue: 1.0)) }
                if !item.screenLabel.isEmpty { Text(item.screenLabel).font(fontSettings.font(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.78)).frame(minWidth: 52, alignment: .trailing) }
            }
            .padding(.horizontal, 10)
            .frame(height: XcodeDashboardMetrics.rowHeight)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hoveredWindowID == item.id ? Color.white.opacity(0.14) : Color(red: 0.090, green: 0.102, blue: 0.118)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color(red: 0.165, green: 0.188, blue: 0.216), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in hoveredWindowID = isHovered ? item.id : (hoveredWindowID == item.id ? nil : hoveredWindowID) }
        .accessibilityLabel("切换到 Xcode 项目 " + item.projectName + "，分支 " + (item.branchName ?? "非 Git 项目") + "，目录 " + (item.localDirectory ?? item.detail))
    }

    // 没有列表时根据实际状态显示权限、进程或项目窗口提示。
    private var availabilityView: some View {
        VStack(spacing: 10) {
            Image(systemName: availabilityIcon).font(fontSettings.font(size: 28, weight: .medium)).foregroundStyle(Color(red: 0.24, green: 0.61, blue: 1.0))
            Text(availabilityTitle).font(fontSettings.font(size: 17, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
            Text(availabilityMessage).font(fontSettings.font(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.52)).multilineTextAlignment(.center)
            if manager.availability == .permissionRequired { Button("打开辅助功能设置", action: onOpenAccessibilitySettings).buttonStyle(XcodeDashboardActionButtonStyle(font: fontSettings.font(size: 13, weight: .semibold))) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // 底部只说明点击切换，唤醒失败时原位替换为短错误提示。
    private var dashboardFooter: some View {
        HStack(spacing: 0) {
            Text(manager.actionErrorMessage ?? footerText).font(fontSettings.font(size: 11, weight: .medium)).foregroundStyle(manager.actionErrorMessage == nil ? .white.opacity(0.45) : Color(red: 1.0, green: 0.48, blue: 0.46)).lineLimit(1)
            Spacer(minLength: 0)
        }
        // Footer 内容必须占满固定高度，才能让分割线贴顶且提示在底栏垂直居中。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, 20) }
    }

    // 标题栏按钮与 Codex 面板统一为 26pt 点击区域、13pt 图标和图钉选中态。
    private func headerButton(systemName: String, help: String, isActive: Bool = false, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: systemName).font(fontSettings.font(size: 13, weight: .semibold)).foregroundStyle(isActive ? Color(red: 0.44, green: 0.76, blue: 1.0) : .white.opacity(0.66)).frame(width: 26, height: 26).background(Circle().fill(isActive ? Color(red: 0.08, green: 0.28, blue: 0.68).opacity(0.70) : Color.clear)).contentShape(Rectangle()) }.buttonStyle(.plain).help(help) }

    // 优先读取当前安装的 Xcode App 图标，标准路径只作为 LaunchServices 无结果时的兜底。
    private var xcodeApplicationIcon: NSImage { let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") ?? URL(fileURLWithPath: "/Applications/Xcode.app"); return NSWorkspace.shared.icon(forFile: applicationURL.path) }

    // 空态图标严格对应当前状态，避免把权限问题误报成 Xcode 未启动。
    private var availabilityIcon: String { switch manager.availability { case .loading: return "arrow.clockwise"; case .permissionRequired: return "hand.raised.fill"; case .xcodeNotRunning: return "hammer"; case .noProjectWindows: return "macwindow"; case .ready: return "checkmark.circle" } }

    // 空态标题使用用户可直接理解的短句。
    private var availabilityTitle: String { switch manager.availability { case .loading: return "正在读取 Xcode 窗口"; case .permissionRequired: return "需要辅助功能权限"; case .xcodeNotRunning: return "Xcode 尚未运行"; case .noProjectWindows: return "暂无项目窗口"; case .ready: return "Xcode 窗口已就绪" } }

    // 空态说明只给当前问题的下一步，不添加功能宣传。
    private var availabilityMessage: String { switch manager.availability { case .loading: return "正在同步项目、分支与本地目录"; case .permissionRequired: return "请允许 Codex Notch 读取并唤醒 Xcode 窗口"; case .xcodeNotRunning: return "打开 Xcode 项目后，窗口会自动出现在这里"; case .noProjectWindows: return "请在 Xcode 中打开一个 Project、Workspace 或 Package"; case .ready: return "点击项目即可切换" } }

    // 底部提示说明行点击切换、顶部拖拽与边缘缩放，空态继续只展示当前可执行的下一步。
    private var footerText: String { switch manager.availability { case .loading: return "正在刷新 Xcode 窗口"; case .ready: return "点击行切换 · 拖动顶部移动 · 拖动边缘缩放"; case .permissionRequired: return "授权后重新触发面板快捷键刷新窗口"; case .xcodeNotRunning: return "等待 Xcode 启动"; case .noProjectWindows: return "等待项目窗口打开" } }
}

// 辅助功能设置按钮使用 Xcode 蓝色，保持空态唯一主操作清晰可见。
private struct XcodeDashboardActionButtonStyle: ButtonStyle {
    // 空态按钮显式接收全局字体，确保用户切换 Codex 字体后 Xcode 面板同步更新。
    let font: Font
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(font).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 32).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(red: 0.15, green: 0.48, blue: 0.92).opacity(configuration.isPressed ? 0.75 : 1))) }
}
