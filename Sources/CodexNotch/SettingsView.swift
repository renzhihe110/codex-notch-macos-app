import AppKit
import Carbon
import SwiftUI

// 集中定义 UI 稿中的深色表面、描边和青绿色强调色，避免各分区出现不一致的透明度。
private enum SettingsPalette {
    static let backgroundTop = Color(red: 0.062, green: 0.091, blue: 0.116)
    static let backgroundBottom = Color(red: 0.031, green: 0.052, blue: 0.068)
    static let panel = Color.white.opacity(0.024)
    static let control = Color.white.opacity(0.045)
    static let border = Color.white.opacity(0.12)
    static let divider = Color.white.opacity(0.075)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.62)
    static let accent = Color(red: 0.08, green: 0.84, blue: 0.65)
    static let closeButton = Color(red: 1.00, green: 0.35, blue: 0.36)
    static let minimizeButton = Color(red: 1.00, green: 0.75, blue: 0.24)
    static let zoomButton = Color(red: 0.20, green: 0.74, blue: 0.34)
}

// 按照深色单卡片 UI 稿组织设置项，并保留现有设置的即时预览能力。
struct SettingsView: View {
    @ObservedObject var settings: HotKeySettings
    @ObservedObject var capsuleSettings: CapsuleSettings
    @ObservedObject var completionPopupSettings: CompletionPopupSettings
    @ObservedObject var petCatalog: CodexPetCatalog
    // 监听共享字体偏好，确保设置页与应用内其他文字同步刷新。
    @ObservedObject private var fontSettings = FontSettings.shared
    // 监听项目目录颜色偏好，并通过明确的按钮入口打开系统取色器。
    @ObservedObject private var directoryColorSettings = DirectoryColorSettings.shared
    // 更新检查器仅在设置页存活，未签名版本仍只跳转 GitHub 下载页。
    @StateObject private var updateChecker = GitHubUpdateChecker()
    // 颜色面板控制器负责可靠显示 AppKit 调色板并连续回传用户选色。
    @StateObject private var directoryColorPanelController = DirectoryColorPanelController()
    @State private var isRecording = false
    @State private var eventMonitor: Any?
    // 保存窗口打开时的设置快照，让底部“取消”可以真实回滚即时预览。
    @State private var originalFontName: String?
    @State private var originalDirectoryColor: Color?
    @State private var originalHotKey: HotKey?
    @State private var originalCapsuleSize: CapsuleSize?
    @State private var originalPetOptionID: String?
    @State private var originalDismissDelaySeconds: Int?

    var body: some View {
        VStack(spacing: 0) {
            windowHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("设置")
                        .font(fontSettings.font(size: 29, weight: .bold))
                        .foregroundStyle(SettingsPalette.primaryText)
                        .padding(.leading, 4)
                        .padding(.top, 15)
                    settingsCard
                    actionBar
                        .padding(.bottom, 16)
                }
                .padding(.leading, 16)
                .padding(.trailing, 18)
            }
            .scrollIndicators(.hidden)
        }
        .frame(minWidth: 450, minHeight: 640)
        .background(backgroundGradient.ignoresSafeArea())
        .background(SettingsWindowConfigurator())
        .font(fontSettings.font(size: 13))
        .foregroundStyle(SettingsPalette.primaryText)
        .preferredColorScheme(.dark)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { captureOriginalValues() }
        .onDisappear { stopRecording() }
        .onExitCommand { cancelChanges() }
    }

    // 自定义标题栏完整还原稿子中的三色窗口按钮和左对齐标题，空白区域仍可拖动窗口。
    private var windowHeader: some View {
        HStack(spacing: 0) {
            HStack(spacing: 9) {
                windowControl(color: SettingsPalette.closeButton, label: "关闭") { NSApp.keyWindow?.performClose(nil) }
                windowControl(color: SettingsPalette.minimizeButton, label: "最小化") { NSApp.keyWindow?.miniaturize(nil) }
                windowControl(color: SettingsPalette.zoomButton, label: "缩放") { NSApp.keyWindow?.zoom(nil) }
            }
            Text("Codex Notch 设置")
                .font(fontSettings.font(size: 15, weight: .semibold))
                .foregroundStyle(SettingsPalette.primaryText.opacity(0.9))
                .padding(.leading, 20)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Color.black.opacity(0.08))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.025)).frame(height: 1) }
    }

    // 每个自定义交通灯直接调用当前设置窗口的原生动作，并保留辅助功能标签。
    private func windowControl(color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Circle().fill(color).frame(width: 13, height: 13) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    // 背景仅使用轻微明暗过渡，保持 UI 稿中的黑蓝材质而不抢占设置内容层级。
    private var backgroundGradient: LinearGradient {
        LinearGradient(colors: [SettingsPalette.backgroundTop, SettingsPalette.backgroundBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // 所有设置分区共享一个描边容器，分隔线贯穿卡片宽度。
    private var settingsCard: some View {
        VStack(spacing: 0) {
            fontSection
            sectionDivider
            hotKeySection
            sectionDivider
            capsuleSection
            sectionDivider
            petSection
            sectionDivider
            updateSection
            sectionDivider
            completionSection
        }
        .background(SettingsPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(SettingsPalette.border, lineWidth: 1) }
    }

    // 字体分区保留字体选择、预览和目录颜色取色三项能力。
    private var fontSection: some View {
        settingsSection(icon: "a.circle", title: "字体", spacing: 13, verticalPadding: 13.5) {
            HStack(spacing: 10) {
                Text("应用字体")
                Spacer(minLength: 12)
                Text("应用字体")
                Menu {
                    Button("系统默认") { fontSettings.select(fontName: FontSettings.systemFontName) }
                    ForEach(fontSettings.availableFontNames, id: \.self) { fontName in
                        Button(fontSettings.displayName(for: fontName)) { fontSettings.select(fontName: fontName) }
                    }
                } label: {
                    menuTitle(currentFontDisplayName, hasLeadingIcon: false)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 148, height: 30)
                .background(controlSurface)
                .overlay(alignment: .trailing) { menuChevron }
            }
            Text("预览：  Codex Notch 字体显示")
                .font(fontSettings.font(size: 13, weight: .medium))
                .foregroundStyle(SettingsPalette.secondaryText)
            HStack(spacing: 14) {
                Text("项目目录颜色")
                Spacer(minLength: 12)
                directoryColorWell
            }
        }
    }

    // 快捷键分区将当前按键、录制和局部恢复动作放在同一行。
    private var hotKeySection: some View {
        settingsSection(icon: "keyboard", title: "快捷键", spacing: 14, verticalPadding: 16) {
            HStack(spacing: 9) {
                Text("展开面板")
                Spacer(minLength: 8)
                Text(settings.hotKey.displayText)
                    .font(fontSettings.font(size: 13, weight: .medium))
                    .frame(minWidth: 62, minHeight: 32)
                    .background(controlSurface)
                Button(isRecording ? "按键中…" : "录制") { toggleRecording() }
                    .buttonStyle(SettingsSecondaryButtonStyle(minWidth: 58))
                Button("恢复默认") {
                    stopRecording()
                    settings.resetToDefault()
                }
                .buttonStyle(SettingsSecondaryButtonStyle(minWidth: 76))
            }
            if let validationMessage = settings.validationMessage {
                Text(validationMessage)
                    .font(fontSettings.font(size: 11))
                    .foregroundStyle(Color.red.opacity(0.88))
            } else if isRecording {
                Text("请按下新快捷键，按 Esc 取消录制")
                    .font(fontSettings.font(size: 11))
                    .foregroundStyle(SettingsPalette.secondaryText)
            }
        }
    }

    // 悬浮球分区使用稿子中的三段式胶囊选择器。
    private var capsuleSection: some View {
        settingsSection(icon: "arrow.up.and.down.circle", title: "悬浮球", spacing: 13, verticalPadding: 12.5) {
            HStack(spacing: 14) {
                Text("大小")
                Spacer(minLength: 12)
                HStack(spacing: 0) {
                    ForEach(CapsuleSize.allCases) { size in
                        Button(size.displayName) { capsuleSettings.select(size: size) }
                            .buttonStyle(SettingsSegmentButtonStyle(isSelected: capsuleSettings.size == size))
                    }
                }
                .padding(2)
                .frame(width: 166, height: 32)
                .background(controlSurface)
            }
        }
    }

    // 宠物分区保留选择、扫描统计和无效包原因展示。
    private var petSection: some View {
        settingsSection(icon: "pawprint", title: "宠物", spacing: 13, verticalPadding: 12) {
            HStack(spacing: 14) {
                Text("当前宠物")
                Spacer(minLength: 12)
                Menu {
                    ForEach(petCatalog.options) { option in
                        Button(option.displayName) { petCatalog.select(optionID: option.id) }
                    }
                } label: {
                    menuTitle(currentPetDisplayName, hasLeadingIcon: true)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 172, height: 30)
                .background(controlSurface)
                .overlay(alignment: .leading) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SettingsPalette.accent)
                        .padding(.leading, 10)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .trailing) { menuChevron }
            }
            HStack(spacing: 12) {
                Button("扫描宠物") { petCatalog.rescan() }
                    .buttonStyle(SettingsSecondaryButtonStyle(minWidth: 76))
                Spacer(minLength: 8)
                scanSummaryText
            }
            ForEach(petCatalog.scanSummary.issues) { issue in
                Text("\(issue.directoryName)：\(issue.reason)")
                    .font(fontSettings.font(size: 11))
                    .foregroundStyle(Color.red.opacity(0.86))
            }
        }
    }

    // 软件更新分区突出当前版本和检查动作，状态说明保持低对比度。
    private var updateSection: some View {
        settingsSection(icon: "arrow.triangle.2.circlepath", title: "软件更新", spacing: 10, verticalPadding: 12.5) {
            HStack(spacing: 14) {
                Text("当前版本 \(updateChecker.currentVersion)")
                Spacer(minLength: 12)
                Button(updateChecker.isChecking ? "检查中…" : "检查更新") { updateChecker.checkForUpdates() }
                    .buttonStyle(SettingsSecondaryButtonStyle(minWidth: 76))
                    .disabled(updateChecker.isChecking)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(updateChecker.statusMessage)
                    .font(fontSettings.font(size: 11))
                    .foregroundStyle(SettingsPalette.secondaryText)
                Spacer(minLength: 0)
                if let releaseURL = updateChecker.latestReleaseURL {
                    Button("打开下载页") { NSWorkspace.shared.open(releaseURL) }
                        .buttonStyle(.link)
                        .foregroundStyle(SettingsPalette.accent)
                }
            }
        }
    }

    // 完成弹窗分区将关闭时间压缩成稿子中的单行步进器。
    private var completionSection: some View {
        settingsSection(icon: "bell", title: "完成弹窗", spacing: 10, verticalPadding: 12.5) {
            HStack(spacing: 14) {
                Text("关闭时间")
                Spacer(minLength: 12)
                Stepper(value: completionDismissDelayBinding, in: CompletionPopupSettings.minimumDismissDelaySeconds...CompletionPopupSettings.maximumDismissDelaySeconds) {
                    Text("\(completionPopupSettings.dismissDelaySeconds) 秒")
                        .font(fontSettings.font(size: 13, weight: .medium))
                        .frame(width: 42, alignment: .leading)
                }
                .padding(.horizontal, 6)
                .frame(width: 76, height: 30)
                .background(controlSurface)
            }
        }
    }

    // 底部操作栏提供全局恢复、取消回滚和保存关闭三个真实动作。
    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("恢复默认") { restoreAllDefaults() }
                .buttonStyle(SettingsSecondaryButtonStyle(minWidth: 90))
            Spacer(minLength: 16)
            Button("取消") { cancelChanges() }
                .buttonStyle(SettingsSecondaryButtonStyle(minWidth: 70))
            Button("保存") { saveChanges() }
                .buttonStyle(SettingsPrimaryButtonStyle(minWidth: 70))
        }
        .padding(.trailing, 5)
        .padding(.top, 14)
    }

    // 分区构造器统一标题、图标和内容间距，使六个模块保持相同视觉节奏。
    private func settingsSection<Content: View>(icon: String, title: String, spacing: CGFloat = 13, verticalPadding: CGFloat = 15, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(SettingsPalette.accent)
                    .frame(width: 18)
                Text(title)
                    .font(fontSettings.font(size: 16, weight: .semibold))
            }
            content()
        }
        .padding(.leading, 13)
        .padding(.trailing, 14)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 分隔线使用极低对比度，避免暗色卡片被切割得过于零碎。
    private var sectionDivider: some View { Rectangle().fill(SettingsPalette.divider).frame(height: 1) }

    // 菜单标题只交给 Menu 文本内容，图标和箭头在控件外层覆盖，避免系统重新排列它们。
    private func menuTitle(_ title: String, hasLeadingIcon: Bool) -> some View {
        Text(title)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.leading, hasLeadingIcon ? 30 : 11)
            .padding(.trailing, 24)
        .foregroundStyle(SettingsPalette.primaryText)
        .contentShape(Rectangle())
    }

    // 菜单箭头固定在控件右侧，不参与 Menu 标签的系统布局。
    private var menuChevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(SettingsPalette.secondaryText)
            .padding(.trailing, 10)
            .allowsHitTesting(false)
    }

    // 颜色入口使用明确的文字按钮和当前色圆点，避免再呈现为具有开关语义的胶囊。
    private var directoryColorWell: some View {
        Button {
            directoryColorPanelController.show(color: directoryColorSettings.color) { directoryColorSettings.update(color: $0) }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(directoryColorSettings.color)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().stroke(SettingsPalette.primaryText.opacity(0.28), lineWidth: 1) }
                Text("选择颜色")
            }
        }
            .buttonStyle(SettingsSecondaryButtonStyle(minWidth: 90))
            .accessibilityLabel("项目目录颜色")
            .help("选择项目目录颜色")
    }

    // 通用控件表面对应稿子中的半透明深灰输入框。
    private var controlSurface: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(SettingsPalette.control)
            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(SettingsPalette.border, lineWidth: 1) }
    }

    // 当前字体名称只转换展示文本，持久化仍使用准确的 PostScript 名称。
    private var currentFontDisplayName: String {
        fontSettings.selectedFontName == FontSettings.systemFontName ? "系统默认" : fontSettings.displayName(for: fontSettings.selectedFontName)
    }

    // 当前宠物名称从统一目录模型读取，选项失效时显示安全回退文案。
    private var currentPetDisplayName: String {
        petCatalog.options.first(where: { $0.id == petCatalog.selectedOptionID })?.displayName ?? "Trump · 西装游泳"
    }

    // 扫描数字使用强调色，保持和稿子中的发现/跳过统计一致。
    private var scanSummaryText: Text {
        Text("发现 ").foregroundColor(SettingsPalette.secondaryText) + Text("\(petCatalog.scanSummary.availableCount)").foregroundColor(SettingsPalette.accent) + Text(" 个，跳过 ").foregroundColor(SettingsPalette.secondaryText) + Text("\(petCatalog.scanSummary.skippedCount)").foregroundColor(SettingsPalette.accent) + Text(" 个").foregroundColor(SettingsPalette.secondaryText)
    }

    // Stepper 继续通过设置对象限制合法秒数并即时持久化。
    private var completionDismissDelayBinding: Binding<Int> {
        Binding(get: { completionPopupSettings.dismissDelaySeconds }, set: { completionPopupSettings.updateDismissDelaySeconds($0) })
    }

    // 每次窗口显示都刷新回滚基线，避免复用窗口时取消到更早一次的设置。
    private func captureOriginalValues() {
        originalFontName = fontSettings.selectedFontName
        originalDirectoryColor = directoryColorSettings.color
        originalHotKey = settings.hotKey
        originalCapsuleSize = capsuleSettings.size
        originalPetOptionID = petCatalog.selectedOptionID
        originalDismissDelaySeconds = completionPopupSettings.dismissDelaySeconds
    }

    // 保存沿用即时持久化模型，只更新回滚基线并关闭设置窗口。
    private func saveChanges() {
        stopRecording()
        captureOriginalValues()
        closeWindow()
    }

    // 取消依次恢复窗口打开时的六项设置，再关闭窗口。
    private func cancelChanges() {
        stopRecording()
        if let originalFontName { fontSettings.select(fontName: originalFontName) }
        if let originalDirectoryColor { directoryColorSettings.update(color: originalDirectoryColor) }
        if let originalHotKey { settings.restore(hotKey: originalHotKey) }
        if let originalCapsuleSize { capsuleSettings.select(size: originalCapsuleSize) }
        if let originalPetOptionID { petCatalog.select(optionID: originalPetOptionID) }
        if let originalDismissDelaySeconds { completionPopupSettings.updateDismissDelaySeconds(originalDismissDelaySeconds) }
        closeWindow()
    }

    // 全局恢复默认覆盖稿子内所有可保存设置，用户仍可通过取消回滚。
    private func restoreAllDefaults() {
        stopRecording()
        fontSettings.select(fontName: FontSettings.systemFontName)
        directoryColorSettings.update(color: Color.white.opacity(0.54))
        settings.resetToDefault()
        capsuleSettings.select(size: .regular)
        petCatalog.select(optionID: CodexPetTheme.suitSwimming.selectionID)
        completionPopupSettings.updateDismissDelaySeconds(3)
    }

    // 关闭当前设置窗口，不影响无 Dock 图标的 accessory App 主进程。
    private func closeWindow() { NSApp.keyWindow?.close() }

    // 录制期间只监听设置窗口的 keyDown，合法组合键会立即刷新显示。
    private func toggleRecording() { isRecording ? stopRecording() : startRecording() }

    // 新快捷键必须包含 Command、Option 或 Control，Esc 只退出录制不关闭窗口。
    private func startRecording() {
        stopRecording()
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            if settings.update(from: event) { stopRecording() }
            return nil
        }
    }

    // 停止录制时同步移除 AppKit 事件监听，防止窗口关闭后继续截获按键。
    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }
}

// 直接管理共享 NSColorPanel，绕过自建窗口中无法激活的 SwiftUI ColorPicker/NSColorWell 路径。
private final class DirectoryColorPanelController: NSObject, ObservableObject {
    private var onColorChange: ((Color) -> Void)?

    // 每次打开都同步当前颜色、透明度支持和回调目标，面板拖动时即可实时刷新目录文字。
    func show(color: Color, onColorChange: @escaping (Color) -> Void) {
        self.onColorChange = onColorChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.isContinuous = true
        panel.color = NSColor(color)
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) { onColorChange?(Color(nsColor: sender.color)) }
}

// 配置自建设置窗口的尺寸和沉浸式外观，并隐藏由 SwiftUI 标题栏替代的原生控件。
private struct SettingsWindowConfigurator: NSViewRepresentable {
    // 协调器只配置每个承载窗口一次，避免设置变更时反复覆盖用户手动调整的尺寸。
    final class Coordinator {
        weak var configuredWindow: NSWindow?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureWindow(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { configureWindow(for: nsView, coordinator: context.coordinator) }

    // 等待 SwiftUI 把占位视图挂到窗口后，再应用 UI 稿对应的 470×838 内容尺寸。
    private func configureWindow(for view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let window = view.window, coordinator.configuredWindow !== window else { return }
            coordinator.configuredWindow = window
            window.styleMask.insert(.fullSizeContentView)
            window.styleMask.insert(.miniaturizable)
            window.styleMask.insert(.resizable)
            window.title = "Codex Notch 设置"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(srgbRed: 0.035, green: 0.055, blue: 0.071, alpha: 1)
            window.isOpaque = false
            window.isMovableByWindowBackground = true
            window.contentMinSize = CGSize(width: 450, height: 640)
            window.contentMaxSize = CGSize(width: 560, height: 900)
            window.setContentSize(CGSize(width: 470, height: 838))
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.center()
        }
    }
}

// 次要按钮使用统一的深色填充、细描边和按压反馈。
private struct SettingsSecondaryButtonStyle: ButtonStyle {
    let minWidth: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(SettingsPalette.primaryText)
            .padding(.horizontal, 10)
            .frame(minWidth: minWidth, minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.085 : 0.045)))
            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(SettingsPalette.border, lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// 主按钮使用高饱和青绿色，形成与稿子一致的唯一主行动层级。
private struct SettingsPrimaryButtonStyle: ButtonStyle {
    let minWidth: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(minWidth: minWidth, minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(SettingsPalette.accent.opacity(configuration.isPressed ? 0.76 : 0.94)))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// 三段式按钮只为当前尺寸填充强调色，其余选项保持透明。
private struct SettingsSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? SettingsPalette.accent : SettingsPalette.primaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isSelected ? SettingsPalette.accent.opacity(configuration.isPressed ? 0.16 : 0.12) : Color.clear))
            .contentShape(Rectangle())
    }
}
