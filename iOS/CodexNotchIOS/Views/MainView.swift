import CodexNotchShared
import SwiftUI

// Hosts the iOS foreground dashboard and routes connection state into the visible notch.
struct MainView: View {
    @StateObject private var connectionStore = ConnectionStore()
    @StateObject private var statusClient = LANStatusClient()
    @StateObject private var activityController = CodexTaskActivityController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if connectionStore.pairing == nil {
                ConnectionView(store: connectionStore, onReconnect: {
                    connectIfPossible()
                })
            } else {
                dashboard
            }
        }
        .onAppear {
            connectIfPossible()
        }
        .onChange(of: connectionStore.pairing) { _ in
            connectIfPossible()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                connectIfPossible()
            case .background:
                statusClient.disconnect()
            default:
                break
            }
        }
        .onChange(of: statusClient.snapshot) { snapshot in
            guard let snapshot else { return }
            activityController.apply(snapshot: snapshot)
        }
    }

    // Builds the selected Island Focus dashboard with separate progress and active-task surfaces.
    private var dashboard: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.05, green: 0.06, blue: 0.08)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    header
                    progressSummaryCard
                    InAppNotchView(snapshot: statusClient.snapshot, connectionStatus: connectionStore.status)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 4)
                SessionListView(sessions: historySessions)
                    .frame(maxHeight: .infinity, alignment: .top)
                actionBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // Labels the dark companion surface without competing with the progress card.
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Codex Notch")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                Text("局域网实时进度")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.52))
            }
            Spacer()
            connectionPill
        }
    }

    // Uses a small capsule to keep connection and completion count visible at a glance.
    private var connectionPill: some View {
        let completed = completedHistoryCount
        let total = historySessions.count
        return HStack(spacing: 6) {
            Circle()
                .fill(connectionStore.status == .connected ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(total == 0 ? "0" : "\(completed)/\(total)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(Color.white.opacity(0.10)))
        .foregroundStyle(.white)
    }

    // Separates total progress from the currently active task so the large card stays clean.
    private var progressSummaryCard: some View {
        let completed = completedHistoryCount
        let total = historySessions.count
        let progress = total == 0 ? 0 : Double(completed) / Double(total)
        let summaryStatus: LANSessionStatus = total == 0 ? (statusClient.snapshot?.aggregateStatus ?? .green) : (completed == total ? .green : .yellow)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(total == 0 ? "0/0" : "\(completed)/\(total)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(total == 0 ? "等待任务同步" : "历史任务完成")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.66))
                }
                Spacer()
                StatusDot(status: summaryStatus, size: 18)
            }
            ProgressView(value: progress)
                .tint(Color(red: 0.34, green: 0.91, blue: 0.48))
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
            HStack(spacing: 9) {
                summaryMetric(title: connectionStore.status.displayText, systemImage: connectionStore.status == .connected ? "wifi" : "wifi.slash")
                if let snapshot = statusClient.snapshot {
                    Label {
                        Text(snapshot.lastUpdatedAt, style: .time)
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
                } else {
                    summaryMetric(title: "等待更新", systemImage: "clock")
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(LinearGradient(colors: [Color(red: 0.12, green: 0.17, blue: 0.15), Color(red: 0.07, green: 0.08, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.green.opacity(0.10), radius: 22, y: 12)
    }

    // Reuses the same metric style for connection and empty update states.
    private func summaryMetric(title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.82))
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
    }

    // Groups destructive and reconnect actions into a compact dark bottom toolbar.
    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(action: connectIfPossible) {
                Label("重新连接", systemImage: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.blue))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Button(role: .destructive) {
                statusClient.disconnect(updateStatus: false)
                activityController.endCurrentActivity()
                connectionStore.clearPairing()
            } label: {
                Label("清除配对", systemImage: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.07)))
                    .foregroundStyle(Color(red: 1.0, green: 0.24, blue: 0.22))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.88))
    }

    // Provides the unfiltered snapshot sessions to every dashboard section that needs counts.
    private var allSessions: [LANSessionPayload] {
        statusClient.snapshot?.sessions ?? []
    }

    // Mirrors the active-task priority used by the current task card.
    private var activeSession: LANSessionPayload? {
        allSessions.first(where: { $0.status == .red }) ?? allSessions.first(where: { $0.status == .yellow })
    }

    // Keeps Recent Sessions visible by excluding only the current active task.
    private var historySessions: [LANSessionPayload] {
        guard let activeSession else { return allSessions }
        return allSessions.filter { $0.id != activeSession.id }
    }

    // Counts completed rows inside the history list without hiding non-active history.
    private var completedHistoryCount: Int {
        historySessions.filter { $0.status == .green }.count
    }

    // Connects only while a pairing exists, preserving the MVP's foreground-first boundary.
    private func connectIfPossible() {
        guard let pairing = connectionStore.pairing else { return }
        statusClient.connect(pairing: pairing) { status in
            connectionStore.updateStatus(status)
        }
    }
}
