import SwiftUI

// 只读悬停摘要：每类最多两条标题，未读状态由入口控制器直接读取官方集合。
struct PetTaskSummaryView: View {
    let runningSessions: [CodexSession]
    let unreadSessions: [CodexSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !runningSessions.isEmpty {
                taskSection(title: "运行中", sessions: runningSessions, color: Color(red: 0.941, green: 0.725, blue: 0.365))
            }
            if !runningSessions.isEmpty && !unreadSessions.isEmpty {
                Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1)
            }
            if !unreadSessions.isEmpty {
                taskSection(title: "待查看", sessions: unreadSessions, color: Color(red: 0.275, green: 0.588, blue: 0.961))
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.13, green: 0.14, blue: 0.16).opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.colorScheme, .dark)
    }

    // 任务顺序沿用最近活动排序，单行截断避免长标题改变浮签尺寸。
    private func taskSection(title: String, sessions: [CodexSession], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(title) · \(sessions.count)").font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
            ForEach(Array(sessions.prefix(2))) { session in
                Text(session.displayTitle).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.94)).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            }
            if sessions.count > 2 {
                Text("还有 \(sessions.count - 2) 个\(title)任务").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.54))
            }
        }
    }
}
