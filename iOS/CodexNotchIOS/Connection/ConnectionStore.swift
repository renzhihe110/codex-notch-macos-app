import Combine
import CodexNotchShared
import Foundation

// Describes the user-visible connection state for the local Mac pairing.
enum ConnectionStatus: Equatable {
    case notPaired
    case connecting
    case connected
    case offline(String?)
    case authenticationFailed
    case incompatibleProtocol
    case serviceUnavailable(String?)

    var displayText: String {
        switch self {
        case .notPaired:
            return "未配对"
        case .connecting:
            return "连接中"
        case .connected:
            return "已连接"
        case .offline(let reason):
            return reason ?? "离线"
        case .authenticationFailed:
            return "鉴权失败，请重新扫码"
        case .incompatibleProtocol:
            return "协议版本不兼容，请更新两端 App"
        case .serviceUnavailable(let reason):
            return reason ?? "Mac 服务不可用"
        }
    }
}

// Persists the paired Mac address and token for foreground LAN connections.
final class ConnectionStore: ObservableObject {
    private static let pairingDefaultsKey = "CodexNotchIOS.pairing"
    private let defaults: UserDefaults

    @Published private(set) var pairing: LANPairingPayload?
    @Published var status: ConnectionStatus

    init(defaults: UserDefaults = .standard) {
        let storedPairing = Self.loadPairing(from: defaults)
        self.defaults = defaults
        self.pairing = storedPairing
        self.status = storedPairing == nil ? .notPaired : .offline("等待连接")
    }

    // Saves a successfully scanned or manually entered pairing payload.
    func savePairing(_ payload: LANPairingPayload) {
        pairing = payload
        status = .offline("等待连接")
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: Self.pairingDefaultsKey)
        }
    }

    // Clears local pairing data without affecting the Mac-side token.
    func clearPairing() {
        pairing = nil
        status = .notPaired
        defaults.removeObject(forKey: Self.pairingDefaultsKey)
    }

    // Updates status from the WebSocket client while keeping persistence logic centralized.
    func updateStatus(_ status: ConnectionStatus) {
        self.status = status
    }

    private static func loadPairing(from defaults: UserDefaults) -> LANPairingPayload? {
        guard let data = defaults.data(forKey: pairingDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(LANPairingPayload.self, from: data)
    }
}
