import CodexNotchShared
import Foundation

// Converts the internal notch state into the display-only LAN snapshot shared with iOS.
enum LANStatusSnapshotMapper {
    static func snapshot(from state: NotchState, sentAt: Date = Date()) -> LANStatusSnapshot {
        LANStatusSnapshot(version: LANStatusProtocol.version, sentAt: sentAt, aggregateStatus: lanStatus(from: state.aggregateStatus), lastUpdatedAt: state.lastUpdatedAt, sessions: state.sessions.map(sessionPayload(from:)), errorMessage: state.errorMessage)
    }

    // Maps only safe display fields and intentionally omits raw events, messages, and full paths.
    private static func sessionPayload(from session: CodexSession) -> LANSessionPayload {
        LANSessionPayload(id: session.id, displayTitle: session.displayTitle, cwdHint: session.cwdHint, status: lanStatus(from: session.status), attention: session.attention.map(lanAttention(from:)), activityText: session.activityText, updatedAt: session.updatedAt)
    }

    private static func lanStatus(from status: SessionStatus) -> LANSessionStatus {
        switch status {
        case .red:
            return .red
        case .yellow:
            return .yellow
        case .green:
            return .green
        }
    }

    private static func lanAttention(from attention: SessionAttention) -> LANSessionAttention {
        switch attention {
        case .waitingInput:
            return .waitingInput
        case .stalled:
            return .stalled
        }
    }
}
