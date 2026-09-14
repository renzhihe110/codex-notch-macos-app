import Foundation

// 展示层只映射已归约的生命周期，不再用最后一个日志类型猜测完成状态。
enum StatusMapper {
    // 状态与 Token 快照独立加载，由主线程组合后展示。
    static func map(snapshot: CodexStoreSnapshot, todayTokenUsage: TodayTokenUsage, now: Date = Date()) -> NotchState { map(sessions: snapshot.sessions, todayTokenUsage: todayTokenUsage, errorMessage: snapshot.errors.first, now: now) }

    // 无会话时保留启动占位，真实任务未知状态由生命周期显式表示。
    static func map(sessions: [CodexSession], now: Date = Date()) -> NotchState { map(sessions: sessions, todayTokenUsage: .empty(dayStart: Calendar.current.startOfDay(for: now)), errorMessage: nil, now: now) }

    // 保留读取错误，状态更新与 Token 更新共用同一展示映射。
    private static func map(sessions: [CodexSession], todayTokenUsage: TodayTokenUsage, errorMessage: String?, now: Date) -> NotchState { let mappedSessions = sessions.map { mappedSession($0, now: now) }; return NotchState(sessions: mappedSessions, aggregateStatus: aggregateStatus(for: mappedSessions, errorMessage: errorMessage), lastUpdatedAt: mappedSessions.map(\.updatedAt).max() ?? now, todayTokenUsage: todayTokenUsage, errorMessage: errorMessage) }

    // 只有明确完成才使用绿色；未知和停止保留黄色及各自文案。
    static func status(for session: CodexSession) -> SessionStatus { switch session.lifecycle { case .completed: return session.isCompleted ? .green : .yellow; case .failed, .waitingInput: return .red; case .unknown, .running, .stopped: return .yellow } }

    // 复制当前轮次和真实活动时间，供全部视图及通知使用同一状态依据。
    private static func mappedSession(_ session: CodexSession, now: Date) -> CodexSession { CodexSession(id: session.id, name: session.name, title: session.title, cwd: session.cwd, createdAt: session.createdAt, updatedAt: session.updatedAt, lastEvent: session.lastEvent, errorHint: session.errorHint, latestMessage: session.latestMessage, completionEventAt: session.completionEventAt, lifecycle: session.lifecycle, lastActivityAt: session.lastActivityAt, status: status(for: session), attention: attention(for: session, now: now)) }

    // 只有运行中的任务才检查十分钟停滞；未知、完成和停止不会触发误提醒。
    private static func attention(for session: CodexSession, now: Date) -> SessionAttention? { if session.lifecycle == .waitingInput { return .waitingInput }; guard session.lifecycle == .running, let lastActivityAt = session.lastActivityAt, now.timeIntervalSince(lastActivityAt) >= 10 * 60 else { return nil }; return .stalled }

    // 可见会话聚合继续遵循红、黄、绿优先级，无会话且读取失败时显示红色。
    private static func aggregateStatus(for sessions: [CodexSession], errorMessage: String?) -> SessionStatus { if sessions.isEmpty && errorMessage != nil { return .red }; if sessions.contains(where: { $0.status == .red }) { return .red }; if sessions.contains(where: { $0.status == .yellow }) { return .yellow }; return .green }
}
