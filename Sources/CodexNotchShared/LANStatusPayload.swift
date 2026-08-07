import Foundation

// Defines the stable LAN protocol constants shared by the macOS publisher and iOS client.
public enum LANStatusProtocol {
    public static let version = 1
    public static let pairingScheme = "codexnotch"
    public static let pairingHost = "pair"
    public static let streamPath = "/stream"
}

// Mirrors the red/yellow/green status model without exposing Codex raw event fields.
public enum LANSessionStatus: String, Codable, Equatable, Sendable {
    case red
    case yellow
    case green
}

// Mirrors the user-attention reason used by the macOS UI and local notifications.
public enum LANSessionAttention: String, Codable, Equatable, Sendable {
    case waitingInput
    case stalled
}

// Carries the display-safe fields for one Codex session over the local network.
public struct LANSessionPayload: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayTitle: String
    public let cwdHint: String
    public let status: LANSessionStatus
    public let attention: LANSessionAttention?
    public let activityText: String
    public let updatedAt: Date

    public init(id: String, displayTitle: String, cwdHint: String, status: LANSessionStatus, attention: LANSessionAttention?, activityText: String, updatedAt: Date) {
        self.id = id
        self.displayTitle = displayTitle
        self.cwdHint = cwdHint
        self.status = status
        self.attention = attention
        self.activityText = activityText
        self.updatedAt = updatedAt
    }
}

// Represents a full point-in-time display snapshot pushed to every authenticated iOS client.
public struct LANStatusSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let sentAt: Date
    public let aggregateStatus: LANSessionStatus
    public let lastUpdatedAt: Date
    public let sessions: [LANSessionPayload]
    public let errorMessage: String?

    public init(version: Int = LANStatusProtocol.version, sentAt: Date, aggregateStatus: LANSessionStatus, lastUpdatedAt: Date, sessions: [LANSessionPayload], errorMessage: String?) {
        self.version = version
        self.sentAt = sentAt
        self.aggregateStatus = aggregateStatus
        self.lastUpdatedAt = lastUpdatedAt
        self.sessions = sessions
        self.errorMessage = errorMessage
    }
}

// Encodes the first-pairing connection information shown as a QR code on macOS.
public struct LANPairingPayload: Codable, Equatable, Sendable {
    public let host: String
    public let port: Int
    public let token: String
    public let version: Int

    public init(host: String, port: Int, token: String, version: Int = LANStatusProtocol.version) {
        self.host = host
        self.port = port
        self.token = token
        self.version = version
    }

    // Builds the custom URL consumed by QR scanning and manual deep-link pairing.
    public var url: URL? {
        var components = URLComponents()
        components.scheme = LANStatusProtocol.pairingScheme
        components.host = LANStatusProtocol.pairingHost
        components.queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "v", value: String(version))
        ]
        return components.url
    }

    // Parses a pairing URL while rejecting unsupported protocol versions and malformed ports.
    public init?(url: URL) {
        guard url.scheme == LANStatusProtocol.pairingScheme, url.host == LANStatusProtocol.pairingHost, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = (components.queryItems ?? []).reduce(into: [String: String]()) { result, item in
            guard let value = item.value else { return }
            result[item.name] = value
        }
        guard let host = items["host"], let portValue = items["port"], let port = Int(portValue), let token = items["token"], let versionValue = items["v"], let version = Int(versionValue), !host.isEmpty, !token.isEmpty, port > 0, port <= 65_535, version == LANStatusProtocol.version else { return nil }
        self.init(host: host, port: port, token: token, version: version)
    }
}
