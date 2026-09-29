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
    // 标题栏拖动监听必须避开内联编辑器 Tab，确保按钮能接收鼠标事件。
    static let editorTabDragExclusionX = CGFloat(150)...CGFloat(430)
}

// 编辑器 Tab 只负责筛选现有窗口，不改变窗口发现与唤醒逻辑。
enum IDEEditorTab {
    case xcode
    case vsCode

    var title: String { switch self { case .xcode: return "Xcode"; case .vsCode: return "VS Code" } }
    var bundleIdentifier: String { switch self { case .xcode: return "com.apple.dt.Xcode"; case .vsCode: return "com.microsoft.VSCode" } }
}

// 只记录当前 Xcode Dashboard 展示状态，不持久化也不影响 Codex 面板。
final class XcodeDashboardPresentationState: ObservableObject {
    @Published var isPinned = false
    @Published var size = XcodeDashboardMetrics.size
    // Tab 选择提升到窗口展示状态，使标题栏点击与窗口级快捷键共享同一状态。
    @Published var selectedEditor: IDEEditorTab?
}

// 以紧凑 Tab 分开展示 Xcode 与 VS Code 窗口，当前窗口使用蓝色左侧指示条和文字强调。
struct XcodeDashboardView: View {
    @ObservedObject var manager: XcodeWindowManager
    @ObservedObject var presentationState: XcodeDashboardPresentationState
    let onSelectWindow: (XcodeWindowItem) -> Void
    let onTogglePin: () -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void
    let onOpenAccessibilitySettings: () -> Void
    @ObservedObject private var fontSettings = FontSettings.shared
    // 分支名称复用设置页的项目目录颜色，用户选色后 Xcode 列表立即同步刷新。
    @ObservedObject private var directoryColorSettings = DirectoryColorSettings.shared
    @State private var hoveredWindowID: String?
    // Xcode 与 VS Code 图标只在进程初始化时读取一次，滚动重绘不再反复解码图标文件。
    private static let xcodeApplicationIcon: NSImage = { let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") ?? URL(fileURLWithPath: "/Applications/Xcode.app"); return NSWorkspace.shared.icon(forFile: applicationURL.path) }()
    private static let vsCodeApplicationIcon: NSImage = { let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") ?? URL(fileURLWithPath: "/Applications/Visual Studio Code.app"); return NSImage(contentsOf: applicationURL.appendingPathComponent("Contents/Resources/Code.icns")) ?? NSWorkspace.shared.icon(forFile: applicationURL.path) }()
    private static let fallbackApplicationIcon = NSWorkspace.shared.icon(for: .applicationBundle)

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

    // 标题栏使用紧凑下划线 Tab 分离 Xcode 与 VS Code，保持列表可用高度不变。
    private var dashboardHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "chevron.left.forwardslash.chevron.right").font(fontSettings.font(size: 20, weight: .semibold)).foregroundStyle(Color(red: 0.44, green: 0.76, blue: 1.0)).frame(width: 24, height: 24)
            Text("IDE 窗口助手").font(fontSettings.font(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.95))
            HStack(spacing: 12) { editorTabButton(.xcode); Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 24); editorTabButton(.vsCode) }.padding(.leading, 8)
            Spacer(minLength: 0)
            headerButton(systemName: presentationState.isPinned ? "pin.fill" : "pin", help: presentationState.isPinned ? "取消常驻" : "常驻面板", isActive: presentationState.isPinned, action: onTogglePin)
            headerButton(systemName: "gearshape", help: "打开设置", action: onOpenSettings)
            headerButton(systemName: "xmark", help: "关闭 IDE 窗口助手", action: onClose)
        }
        .padding(.horizontal, 20)
    }

    // 主区在有数据时展示统一列表，异常状态则给出单一、可执行的说明。
    @ViewBuilder private var dashboardContent: some View {
        if manager.availability == .ready {
            if filteredWindows.isEmpty { editorEmptyView } else { windowList }
        } else {
            availabilityView
        }
    }

    // IDE 窗口卡沿用 Codex 任务卡的间距、圆角与深色分层，更多窗口在内部滚动。
    private var windowList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(filteredWindows) { item in
                    windowRow(item)
                }
            }
            .padding(6)
        }
        .scrollIndicators(.visible)
        .padding(.horizontal, 20)
    }

    // Tab 数字按编辑器窗口实时统计，完整矩形热区覆盖文字周围空白并保持 42pt 点击高度。
    private func editorTabButton(_ editor: IDEEditorTab) -> some View { Button { presentationState.selectedEditor = editor } label: { HStack(spacing: 7) { Text(editor.title); Text("\(windowCount(for: editor))") }.font(fontSettings.font(size: 14, weight: .semibold)).foregroundStyle(activeEditor == editor ? .white.opacity(0.94) : .white.opacity(0.48)).padding(.horizontal, 4).frame(minWidth: 88, minHeight: 42).contentShape(Rectangle()).overlay(alignment: .bottom) { Rectangle().fill(Color(red: 0.18, green: 0.63, blue: 1.0)).frame(height: 3).clipShape(Capsule()).opacity(activeEditor == editor ? 1 : 0) } }.buttonStyle(.plain).accessibilityLabel("显示 \(editor.title) 窗口").accessibilityAddTraits(activeEditor == editor ? .isSelected : []) }

    // 用户尚未选择时优先 Xcode，没有 Xcode 窗口才自动展示 VS Code。
    private var activeEditor: IDEEditorTab { presentationState.selectedEditor ?? (windows(for: .xcode).isEmpty && !windows(for: .vsCode).isEmpty ? .vsCode : .xcode) }

    // 过滤逻辑保持在视图层，避免影响窗口管理器的采集顺序和刷新缓存。
    private var filteredWindows: [XcodeWindowItem] { windows(for: activeEditor) }
    private func windows(for editor: IDEEditorTab) -> [XcodeWindowItem] { manager.windows.filter { $0.bundleIdentifier == editor.bundleIdentifier } }
    private func windowCount(for editor: IDEEditorTab) -> Int { windows(for: editor).count }

    // 整行都是点击目标，悬停只轻微提亮，当前窗口额外显示左侧蓝条和状态文字。
    private func windowRow(_ item: XcodeWindowItem) -> some View {
        Button { onSelectWindow(item) } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color(red: 0.44, green: 0.76, blue: 1.0)).frame(width: 4, height: 42).opacity(item.isCurrent ? 1 : 0)
                Image(nsImage: editorApplicationIcon(for: item)).resizable().scaledToFit().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.projectName).font(fontSettings.font(size: 19.5, weight: .medium)).foregroundStyle(.white.opacity(0.94)).lineLimit(1)
                    // 第二行优先展示分支与本地仓库目录，悬停提示保留原有当前文件信息。
                    HStack(spacing: 5) { Image(systemName: "arrow.triangle.branch").font(fontSettings.font(size: 12, weight: .semibold)).foregroundStyle(Color(red: 0.204, green: 0.827, blue: 0.600)); (Text(item.branchName ?? "非 Git 项目").foregroundColor(directoryColorSettings.color) + Text(" · \(item.localDirectory ?? item.detail)").foregroundColor(.white.opacity(0.54))).font(fontSettings.font(size: 15)).lineLimit(1).truncationMode(.middle) }.help(item.detail)
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
        .accessibilityLabel("切换到 \(item.editorName) 项目 " + item.projectName + "，分支 " + (item.branchName ?? "非 Git 项目") + "，目录 " + (item.localDirectory ?? item.detail))
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

    // 当前编辑器没有项目窗口时保留 Tab，并给出对应编辑器的明确提示。
    private var editorEmptyView: some View { VStack(spacing: 10) { Image(systemName: "macwindow").font(fontSettings.font(size: 28, weight: .medium)).foregroundStyle(Color(red: 0.24, green: 0.61, blue: 1.0)); Text("暂无 \(activeEditor.title) 窗口").font(fontSettings.font(size: 17, weight: .semibold)).foregroundStyle(.white.opacity(0.92)); Text("请在 \(activeEditor.title) 中打开项目或工作区").font(fontSettings.font(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.52)) }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 24) }

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

    // 行渲染只读取缓存图标，避免滚动时访问 LaunchServices 或解码应用资源。
    private func editorApplicationIcon(for item: XcodeWindowItem) -> NSImage { switch item.bundleIdentifier { case "com.apple.dt.Xcode": return Self.xcodeApplicationIcon; case "com.microsoft.VSCode": return Self.vsCodeApplicationIcon; default: return Self.fallbackApplicationIcon } }

    // 空态图标严格对应当前状态，避免把权限问题误报成编辑器未启动。
    private var availabilityIcon: String { switch manager.availability { case .loading: return "arrow.clockwise"; case .permissionRequired: return "hand.raised.fill"; case .noSupportedEditorsRunning: return "chevron.left.forwardslash.chevron.right"; case .noProjectWindows: return "macwindow"; case .ready: return "checkmark.circle" } }

    // 空态标题使用用户可直接理解的短句。
    private var availabilityTitle: String { switch manager.availability { case .loading: return "正在读取 IDE 窗口"; case .permissionRequired: return "需要辅助功能权限"; case .noSupportedEditorsRunning: return "Xcode 或 VS Code 尚未运行"; case .noProjectWindows: return "暂无项目窗口"; case .ready: return "IDE 窗口已就绪" } }

    // 空态说明只给当前问题的下一步，不添加功能宣传。
    private var availabilityMessage: String { switch manager.availability { case .loading: return "正在同步项目、分支与本地目录"; case .permissionRequired: return "请允许 Codex 悬浮助手 读取并唤醒编辑器窗口"; case .noSupportedEditorsRunning: return "打开 Xcode 项目或 VS Code 工作区后，窗口会自动出现在这里"; case .noProjectWindows: return "请在 Xcode 或 VS Code 中打开项目或工作区"; case .ready: return "点击项目即可切换" } }

    // 底部提示说明行点击切换、顶部拖拽与边缘缩放，空态继续只展示当前可执行的下一步。
    private var footerText: String { switch manager.availability { case .loading: return "正在刷新 IDE 窗口"; case .ready: return "点击行切换 · 拖动顶部移动 · 拖动边缘缩放"; case .permissionRequired: return "授权后重新触发面板快捷键刷新窗口"; case .noSupportedEditorsRunning: return "等待 Xcode 或 VS Code 启动"; case .noProjectWindows: return "等待项目窗口打开" } }
}

// 辅助功能设置按钮使用 Xcode 蓝色，保持空态唯一主操作清晰可见。
private struct XcodeDashboardActionButtonStyle: ButtonStyle {
    // 空态按钮显式接收全局字体，确保用户切换 Codex 字体后 Xcode 面板同步更新。
    let font: Font
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(font).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 32).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(red: 0.15, green: 0.48, blue: 0.92).opacity(configuration.isPressed ? 0.75 : 1))) }
}
