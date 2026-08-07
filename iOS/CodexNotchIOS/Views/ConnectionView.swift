import CodexNotchShared
import SwiftUI

// Presents QR pairing, manual entry, and reconnect controls for the local Mac.
struct ConnectionView: View {
    @ObservedObject var store: ConnectionStore
    let onReconnect: () -> Void
    @State private var isShowingScanner = false
    @State private var host = ""
    @State private var port = ""
    @State private var token = ""
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("连接 Mac")
                .font(.title2.weight(.semibold))
            Text(store.status.displayText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let pairing = store.pairing {
                pairedSummary(pairing)
            }
            Button("扫码配对") {
                isShowingScanner = true
            }
            .buttonStyle(.borderedProminent)
            manualEntryForm
            if let validationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .sheet(isPresented: $isShowingScanner) {
            QRCodeScannerView { value in
                handleScannedCode(value)
                isShowingScanner = false
            }
        }
    }

    // Shows the currently paired Mac and allows the user to reconnect or clear local credentials.
    private func pairedSummary(_ pairing: LANPairingPayload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已配对：\(pairing.host):\(pairing.port)")
                .font(.system(size: 13, design: .monospaced))
            HStack {
                Button("重新连接", action: onReconnect)
                Button("清除配对") {
                    store.clearPairing()
                }
            }
        }
    }

    // Provides a fallback for cases where camera access or QR scanning is unavailable.
    private var manualEntryForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("手动输入")
                .font(.headline)
            TextField("Mac 地址", text: $host)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("端口", text: $port)
                .keyboardType(.numberPad)
            TextField("Token", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("保存手动配置") {
                saveManualPairing()
            }
            .buttonStyle(.bordered)
        }
    }

    private func handleScannedCode(_ value: String) {
        guard let url = URL(string: value), let payload = LANPairingPayload(url: url) else {
            validationMessage = "二维码格式不正确"
            store.updateStatus(.serviceUnavailable("二维码格式不正确"))
            return
        }
        validationMessage = nil
        store.savePairing(payload)
    }

    private func saveManualPairing() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            validationMessage = "请输入 Mac 地址"
            return
        }
        guard let portValue = Int(port), portValue > 0, portValue <= 65_535 else {
            validationMessage = "请输入有效端口"
            return
        }
        guard !trimmedToken.isEmpty else {
            validationMessage = "请输入 token"
            return
        }
        validationMessage = nil
        store.savePairing(LANPairingPayload(host: trimmedHost, port: portValue, token: trimmedToken))
    }
}
