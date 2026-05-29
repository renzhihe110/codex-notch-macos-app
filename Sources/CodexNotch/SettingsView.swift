import AppKit
import Carbon
import SwiftUI

// 提供应用设置页，目前只暴露展开刘海面板的快捷键配置。
struct SettingsView: View {
    @ObservedObject var settings: HotKeySettings
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置")
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                Text("快捷键")
                    .font(.headline)
                HStack(spacing: 12) {
                    Text("展开面板")
                    Spacer(minLength: 16)
                    Text(settings.hotKey.displayText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
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
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if isRecording {
                    Text("按 Esc 取消")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(width: 420, alignment: .leading)
        .onDisappear {
            stopRecording()
        }
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
