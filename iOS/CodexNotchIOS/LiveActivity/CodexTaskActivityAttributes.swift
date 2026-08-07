import ActivityKit
import Foundation

// Defines the display-only state shared between the iOS app and Live Activity widget.
struct CodexTaskActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        let displayTitle: String
        let projectHint: String
        let aggregateStatus: String
        let attentionLabel: String?
        let completedCount: Int
        let totalCount: Int
        let updatedAt: Date
    }

    let taskID: String
}
