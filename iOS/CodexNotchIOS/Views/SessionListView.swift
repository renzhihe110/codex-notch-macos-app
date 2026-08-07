import CodexNotchShared
import SwiftUI

// Renders the recent completed session payloads in the selected Island Focus dark style.
struct SessionListView: View {
    let sessions: [LANSessionPayload]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                sectionHeader
                if sessions.isEmpty {
                    emptyState
                } else {
                    ForEach(sessions) { session in
                        sessionRow(session)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Color.clear)
    }

    // Separates completed history from the active-task card above it.
    private var sectionHeader: some View {
        HStack {
            Text("Recent Sessions")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Text("\(sessions.count) done")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.bottom, 4)
    }

    // Keeps the empty state quiet so the connected page still feels stable before the first snapshot arrives.
    private var emptyState: some View {
        Text("暂无完成记录")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.50))
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    // Keeps each row dense and display-only so no raw Codex content appears on iOS.
    private func sessionRow(_ session: LANSessionPayload) -> some View {
        HStack(alignment: .center, spacing: 12) {
            StatusDot(status: session.status, size: 10)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(session.displayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(session.updatedAt, style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.42))
                }
                HStack(spacing: 6) {
                    Text(session.cwdHint)
                    Text("·")
                    Text(statusText(for: session))
                    Text("·")
                    Text(session.activityText)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func statusText(for session: LANSessionPayload) -> String {
        if let attention = session.attention {
            switch attention {
            case .waitingInput:
                return "等待输入"
            case .stalled:
                return "可能停滞"
            }
        }
        switch session.status {
        case .red:
            return "需要处理"
        case .yellow:
            return "运行中"
        case .green:
            return "已完成"
        }
    }
}
