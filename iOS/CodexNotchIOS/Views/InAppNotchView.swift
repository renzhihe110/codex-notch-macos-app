import CodexNotchShared
import SwiftUI

// Shows the selected Island Focus active-task card separately from the total progress card.
struct InAppNotchView: View {
    let snapshot: LANStatusSnapshot?
    let connectionStatus: ConnectionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("NOW RUNNING")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                Spacer()
                Text(statusBadgeText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(currentSession == nil ? .white.opacity(0.48) : statusColor)
            }
            HStack(spacing: 12) {
                StatusDot(status: currentStatus, size: 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.50))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 13)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 27, style: .continuous).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.36), radius: 22, y: 12)
    }

    private var currentSession: LANSessionPayload? {
        guard let sessions = snapshot?.sessions else { return nil }
        return sessions.first(where: { $0.status == .red }) ?? sessions.first(where: { $0.status == .yellow })
    }

    private var currentStatus: LANSessionStatus {
        currentSession?.status ?? snapshot?.aggregateStatus ?? .green
    }

    private var title: String {
        if let currentSession {
            return currentSession.displayTitle
        }
        return "暂无运行任务"
    }

    private var subtitle: String {
        if let currentSession {
            return "\(currentSession.cwdHint) · \(statusText(for: currentSession)) · \(currentSession.activityText)"
        }
        return connectionStatus == .connected ? "Mac 在线 · 等待新任务" : connectionStatus.displayText
    }

    private var statusBadgeText: String {
        guard let currentSession else { return "空闲" }
        return statusText(for: currentSession)
    }

    private var statusColor: Color {
        switch currentStatus {
        case .red:
            return Color(red: 1.0, green: 0.24, blue: 0.22)
        case .yellow:
            return Color(red: 1.0, green: 0.74, blue: 0.18)
        case .green:
            return Color(red: 0.20, green: 0.82, blue: 0.42)
        }
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
