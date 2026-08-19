import AppKit
import Carbon
import SwiftUI

// 提供应用设置页，集中暴露快捷键、悬浮球外观、宠物和局域网配置。
struct SettingsView: View {
    @ObservedObject var settings: HotKeySettings
    @ObservedObject var capsuleSettings: CapsuleSettings
    @ObservedObject var completionPopupSettings: CompletionPopupSettings
    @ObservedObject var petCatalog: CodexPetCatalog
    @ObservedObject var pairingStore: PairingStore
    @ObservedObject var lanStatusServer: LANStatusServer
    // 监听共享字体偏好，确保设置页中的文字和预览能即时刷新。
    @ObservedObject private var fontSettings = FontSettings.shared
    // 监听项目目录颜色偏好，让取色盘与当前选择保持同步。
    @ObservedObject private var directoryColorSettings = DirectoryColorSettings.shared
    // 更新检查器仅在设置页存活，避免未签名版本后台静默下载或替换应用。
    @StateObject private var updateChecker = GitHubUpdateChecker()
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("设置")
                    .font(fontSettings.font(size: 22, weight: .semibold))
            // 字体菜单只列出当前 Mac 已安装的常用中文字体，选择后即时刷新整个应用。
            VStack(alignment: .leading, spacing: 10) {
                Text("字体")
                    .font(fontSettings.font(size: 17, weight: .semibold))
                HStack(spacing: 12) {
                    Text("应用字体")
                    Spacer(minLength: 16)
                    Picker("应用字体", selection: fontBinding) {
                        Text("系统默认").tag(FontSettings.systemFontName)
                        ForEach(fontSettings.availableFontNames, id: \.self) { fontName in
                            Text(fontSettings.displayName(for: fontName)).tag(fontName)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 260)
                }
                Text("预览：Codex Notch 字体显示")
                    .font(fontSettings.font(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                // ColorPicker 使用系统取色盘，用户可直接选择目录文字颜色和透明度。
                HStack(spacing: 12) {
                    Text("项目目录颜色")
                    Spacer(minLength: 16)
                    ColorPicker("项目目录颜色", selection: directoryColorBinding, supportsOpacity: true)
                        .labelsHidden()
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("快捷键")
                    .font(fontSettings.font(size: 17, weight: .semibold))
                HStack(spacing: 12) {
                    Text("展开面板")
                    Spacer(minLength: 16)
                    Text(settings.hotKey.displayText)
                        .font(fontSettings.font(size: 15, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(minWidth: 76, minHeight: 28)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.secondary.opacity(0.12)))
                    Button(isRecording ? "按下快捷键" : "录制") {
                        toggleRecording()
                    }
                    Button("恢复默认") {
                        stopRecording()
                        settings.resetToDefault()
                    }
                }
                if let validationMessage = settings.validationMessage {
                    Text(validationMessage)
                        .font(fontSettings.font(size: 13))
                        .foregroundStyle(.red)
                } else if isRecording {
                    Text("按 Esc 取消")
                        .font(fontSettings.font(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            // 悬浮球尺寸使用三段式选择，避免用户输入造成入口内容溢出。
            VStack(alignment: .leading, spacing: 10) {
                Text("悬浮球")
                    .font(fontSettings.font(size: 17, weight: .semibold))
                HStack(spacing: 12) {
                    Text("大小")
                    Spacer(minLength: 16)
                    Picker("悬浮球大小", selection: capsuleSizeBinding) {
                        ForEach(CapsuleSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            // 宠物区域与右键菜单共享同一目录模型，选择和手动扫描结果会即时双向同步。
            VStack(alignment: .leading, spacing: 10) {
                Text("宠物")
                    .font(fontSettings.font(size: 17, weight: .semibold))
                HStack(spacing: 12) {
                    Text("当前宠物")
                    Spacer(minLength: 16)
                    Picker("当前宠物", selection: petSelectionBinding) {
                        ForEach(petCatalog.options) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 260)
                }
                HStack(spacing: 12) {
                    Button("扫描宠物") {
                        petCatalog.rescan()
                    }
                    .buttonStyle(.bordered)
                    Spacer(minLength: 16)
                    Text("发现 \(petCatalog.scanSummary.availableCount) 个，跳过 \(petCatalog.scanSummary.skippedCount) 个")
                        .foregroundStyle(.secondary)
                }
                ForEach(petCatalog.scanSummary.issues) { issue in
                    Text("\(issue.directoryName)：\(issue.reason)")
                        .font(fontSettings.font(size: 12))
                        .foregroundStyle(.red)
                }
            }
            // 未签名版本只检查 GitHub Release，并把安装动作明确交还给用户。
            VStack(alignment: .leading, spacing: 10) {
                Text("软件更新")
                    .font(fontSettings.font(size: 17, weight: .semibold))
                HStack(spacing: 12) {
                    Text("当前版本 \(updateChecker.currentVersion)")
                    Spacer(minLength: 16)
                    Button(updateChecker.isChecking ? "检查中…" : "检查更新") {
                        updateChecker.checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .disabled(updateChecker.isChecking)
                }
                Text(updateChecker.statusMessage)
                    .font(fontSettings.font(size: 12))
                    .foregroundStyle(.secondary)
                if let releaseURL = updateChecker.latestReleaseURL {
                    Button("打开 GitHub Release 下载页") {
                        NSWorkspace.shared.open(releaseURL)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            // 完成弹窗关闭时间使用步进器，避免输入非法秒数导致提示常驻或闪退。
            VStack(alignment: .leading, spacing: 10) {
                Text("完成弹窗")
                    .font(fontSettings.font(size: 17, weight: .semibold))
                HStack(spacing: 12) {
                    Text("关闭时间")
                    Spacer(minLength: 16)
                    Stepper(value: completionDismissDelayBinding, in: CompletionPopupSettings.minimumDismissDelaySeconds...CompletionPopupSettings.maximumDismissDelaySeconds) {
                        Text("\(completionPopupSettings.dismissDelaySeconds) 秒")
                            .font(fontSettings.font(size: 15, weight: .medium))
                            .frame(width: 54, alignment: .trailing)
                    }
                    .frame(width: 150)
                }
            }
            Divider()
            lanPairingSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520)
        .font(fontSettings.font(size: 13))
        .onDisappear {
            stopRecording()
        }
    }

    // Picker 使用显式 Binding，确保选择变更走设置对象的持久化和通知逻辑。
    private var capsuleSizeBinding: Binding<CapsuleSize> {
        Binding(get: { capsuleSettings.size }, set: { capsuleSettings.select(size: $0) })
    }

    // 设置页选择只提交稳定选项 ID，保持与右键菜单共用同一持久化入口。
    private var petSelectionBinding: Binding<String> {
        Binding(get: { petCatalog.selectedOptionID }, set: { petCatalog.select(optionID: $0) })
    }

    // 字体选择通过设置对象写入 UserDefaults，重启后仍使用上一次的选择。
    private var fontBinding: Binding<String> {
        Binding(get: { fontSettings.selectedFontName }, set: { fontSettings.select(fontName: $0) })
    }

    // 取色盘通过设置对象写入 UserDefaults，重启后仍使用上一次选择。
    private var directoryColorBinding: Binding<Color> { Binding(get: { directoryColorSettings.color }, set: { directoryColorSettings.update(color: $0) }) }

    // Stepper 通过设置对象写入 UserDefaults，让下一次完成弹窗展示时读取新值。
    private var completionDismissDelayBinding: Binding<Int> {
        Binding(get: { completionPopupSettings.dismissDelaySeconds }, set: { completionPopupSettings.updateDismissDelaySeconds($0) })
    }

    // Shows the QR pairing details for the iOS companion without exposing any Codex conversation data.
    private var lanPairingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("局域网 iOS 连接")
                .font(fontSettings.font(size: 17, weight: .semibold))
            HStack(alignment: .top, spacing: 14) {
                QRCodeView(text: pairingStore.pairingURLString, size: 118)
                VStack(alignment: .leading, spacing: 8) {
                    settingsRow(title: "状态", value: lanStatusServer.state.displayText)
                    settingsRow(title: "地址", value: "\(pairingStore.host):\(pairingStore.port)")
                    settingsRow(title: "Token", value: pairingStore.token)
                    Button(isLANServerRunning ? "停止服务" : "启动服务") {
                        if isLANServerRunning {
                            lanStatusServer.stop()
                        } else {
                            lanStatusServer.start(pairingStore: pairingStore)
                        }
                    }
                    .buttonStyle(.bordered)
                    Button("重置 token") {
                        pairingStore.resetToken()
                        lanStatusServer.disconnectClients()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
            }
            Text("仅同一局域网内可用；第一版只保证 iOS App 前台实时同步。")
                .font(fontSettings.font(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // Keeps setting rows compact and selectable so the address/token can be copied for manual pairing.
    private func settingsRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            Text(value.isEmpty ? "不可用" : value)
                .font(fontSettings.font(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    // Treats only the running state as active so failed/stopped states can show the start action.
    private var isLANServerRunning: Bool {
        if case .running = lanStatusServer.state {
            return true
        }
        return false
    }

    // 录制期间只监听当前应用的 keyDown，拿到合法组合键后立即保存并停止录制。
    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            // 无效组合键只展示校验提示并保持录制，方便用户直接重按。
            if settings.update(from: event) {
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }
}
