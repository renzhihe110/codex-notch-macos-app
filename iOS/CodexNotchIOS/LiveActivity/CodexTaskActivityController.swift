import ActivityKit
import CodexNotchShared
import Foundation

// Starts, updates, and ends the foreground-driven Live Activity for active Codex sessions.
@MainActor
final class CodexTaskActivityController: ObservableObject {
    private var activity: Activity<CodexTaskActivityAttributes>?

    func apply(snapshot: LANStatusSnapshot) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let session = prioritizedActiveSession(in: snapshot) else {
            endCurrentActivity()
            return
        }
        let state = contentState(for: session, snapshot: snapshot)
        if let activity {
            Task {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        } else {
            do {
                activity = try Activity.request(attributes: CodexTaskActivityAttributes(taskID: session.id), content: ActivityContent(state: state, staleDate: nil), pushType: nil)
            } catch {
                activity = nil
            }
        }
    }

    // Ends the current Live Activity when active work is gone or the user clears pairing.
    func endCurrentActivity() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .default)
        }
    }

    private func prioritizedActiveSession(in snapshot: LANStatusSnapshot) -> LANSessionPayload? {
        snapshot.sessions.first(where: { $0.status == .red }) ?? snapshot.sessions.first(where: { $0.status == .yellow })
    }

    private func contentState(for session: LANSessionPayload, snapshot: LANStatusSnapshot) -> CodexTaskActivityAttributes.ContentState {
        CodexTaskActivityAttributes.ContentState(displayTitle: session.displayTitle, projectHint: session.cwdHint, aggregateStatus: session.status.rawValue, attentionLabel: attentionLabel(for: session.attention), completedCount: snapshot.sessions.filter { $0.status == .green }.count, totalCount: snapshot.sessions.count, updatedAt: snapshot.lastUpdatedAt)
    }

    private func attentionLabel(for attention: LANSessionAttention?) -> String? {
        switch attention {
        case .waitingInput:
            return "等待输入"
        case .stalled:
            return "可能停滞"
        case .none:
            return nil
        }
    }
}
