import ActivityKit
import SwiftUI
import WidgetKit

// Renders the Codex task status on the lock screen and Dynamic Island.
struct CodexTaskLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CodexTaskActivityAttributes.self) { context in
            LockScreenCodexTaskView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WidgetStatusDot(status: context.state.aggregateStatus)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.attentionLabel ?? statusText(context.state.aggregateStatus))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.completedCount)/\(context.state.totalCount)")
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.projectHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                WidgetStatusDot(status: context.state.aggregateStatus)
            } compactTrailing: {
                Text("\(context.state.completedCount)/\(context.state.totalCount)")
                    .font(.caption2.monospacedDigit())
            } minimal: {
                WidgetStatusDot(status: context.state.aggregateStatus, size: 8)
            }
        }
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "red":
            return "需要处理"
        case "yellow":
            return "运行中"
        default:
            return "已完成"
        }
    }
}

// Provides the larger lock-screen Live Activity presentation.
private struct LockScreenCodexTaskView: View {
    let state: CodexTaskActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            WidgetStatusDot(status: state.aggregateStatus, size: 12)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(state.projectHint) · \(state.attentionLabel ?? statusText(state.aggregateStatus))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(state.completedCount)/\(state.totalCount)")
                .font(.caption.monospacedDigit())
        }
        .padding()
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "red":
            return "需要处理"
        case "yellow":
            return "运行中"
        default:
            return "已完成"
        }
    }
}

// Draws a compact status dot inside WidgetKit surfaces.
private struct WidgetStatusDot: View {
    let status: String
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }

    private var color: Color {
        switch status {
        case "red":
            return Color(red: 1.0, green: 0.24, blue: 0.22)
        case "yellow":
            return Color(red: 1.0, green: 0.74, blue: 0.18)
        default:
            return Color(red: 0.20, green: 0.82, blue: 0.42)
        }
    }
}
