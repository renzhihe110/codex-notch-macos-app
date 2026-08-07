import Combine
import CodexNotchShared
import Darwin
import Foundation

// Owns LAN pairing credentials for the macOS app without touching Codex state files.
final class PairingStore: ObservableObject {
    static let shared = PairingStore()
    private static let tokenDefaultsKey = "CodexNotch.lan.token"
    private let defaults: UserDefaults
    private let tokenLock = NSLock()

    @Published private(set) var token: String
    let port: Int

    init(defaults: UserDefaults = .standard, port: Int = 48_573) {
        self.defaults = defaults
        self.port = port
        let existingToken = defaults.string(forKey: Self.tokenDefaultsKey)
        let token = existingToken?.isEmpty == false ? existingToken! : Self.generateToken()
        self.token = token
        defaults.set(token, forKey: Self.tokenDefaultsKey)
    }

    // Uses the current preferred LAN address for QR pairing and falls back to loopback for local testing.
    var host: String {
        Self.preferredLANHost() ?? "127.0.0.1"
    }

    // Builds the shared pairing payload used by the QR code and manual entry text.
    var pairingPayload: LANPairingPayload {
        LANPairingPayload(host: host, port: port, token: token)
    }

    // Exposes the custom pairing URL string in a UI-friendly form.
    var pairingURLString: String {
        pairingPayload.url?.absoluteString ?? ""
    }

    // Rotates the local token and invalidates future requests that still use the old token.
    func resetToken() {
        let updatedToken = Self.generateToken()
        tokenLock.lock()
        token = updatedToken
        defaults.set(updatedToken, forKey: Self.tokenDefaultsKey)
        tokenLock.unlock()
    }

    // Keeps token validation local to the pairing store so the WebSocket server does not own credentials.
    func isToken(_ candidate: String) -> Bool {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        return candidate == token
    }

    private static func generateToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    // Selects the first non-loopback IPv4 address, which matches the MVP's manual LAN pairing model.
    private static func preferredLANHost() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(address, socklen_t(address.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }
            let value = String(cString: hostname)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
