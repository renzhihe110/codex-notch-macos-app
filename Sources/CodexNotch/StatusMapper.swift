import Foundation

// 将 Codex 原始会话信号压缩成 notch 只需要的红黄绿状态。
enum StatusMapper {
    // 支持直接从 reader 快照生成 notch 展示状态。
    static func map(snapshot: CodexStoreSnapshot, now: Date = Date()) -> NotchState {
        map(sessions: snapshot.sessions, errorMessage: snapshot.errors.first, now: now)
    }

    // 支持调用方只传可见会话列表，便于后续 UI 自行决定过滤范围。
    static func map(sessions: [CodexSession], now: Date = Date()) -> NotchState {
        map(sessions: sessions, errorMessage: nil, now: now)
    }

    // 保留 reader 错误，避免无会话且读取失败时显示绿色健康态。
    private static func map(sessions: [CodexSession], errorMessage: String?, now: Date) -> NotchState {
        let mappedSessions = sessions.map { mappedSession($0, now: now) }
        return NotchState(sessions: mappedSessions, aggregateStatus: aggregateStatus(for: mappedSessions, errorMessage: errorMessage), lastUpdatedAt: latestActivity(in: mappedSessions, fallback: now), errorMessage: errorMessage)
    }

    // 单会话状态按红色错误优先、黄色等待次之、其余绿色处理。
    static func status(for session: CodexSession) -> SessionStatus {
        if session.status == .red { return .red }
        let signal = [session.lastEvent, session.errorHint].compactMap { $0 }.joined(separator: " ").lowercased()
        if containsAny(redSignals, in: signal) { return .red }
        if session.status == .yellow || containsAny(yellowSignals, in: signal) || containsActiveEvent(in: signal) { return .yellow }
        return .green
    }

    // 错误类信号优先映射为红色，避免被等待类状态覆盖。
    private static let redSignals = ["error", "failed", "failure", "last_error", "last error", "exception", "panic", "fatal", "crash"]

    // 等待、暂停、超时、阻塞、权限类信号映射为黄色。
    private static let yellowSignals = ["waiting", "wait", "paused", "pause", "timeout", "timed_out", "needs_input", "needs input", "blocked", "permission", "denied", "cancelled", "canceled", "interrupt", "approval", "task_started", "user_message", "reasoning"]

    // 需要主动提醒的等待信号，比普通黄灯更窄，避免把所有运行中事件都当成待处理。
    private static let waitingAttentionSignals = ["waiting", "wait", "needs_input", "needs input", "permission", "approval"]

    // 明确阻塞或超时的信号直接进入停滞提醒。
    private static let stalledAttentionSignals = ["blocked", "timeout", "timed_out"]

    // 活跃事件超过阈值没有新记录时，视作可能停滞；默认 10 分钟保持保守。
    private static let stalledActiveInterval: TimeInterval = 10 * 60

    // 保留原会话展示字段，仅替换计算后的状态。
    private static func mappedSession(_ session: CodexSession, now: Date) -> CodexSession {
        let mappedStatus = status(for: session)
        return CodexSession(id: session.id, title: session.title, cwd: session.cwd, updatedAt: session.updatedAt, lastEvent: session.lastEvent, errorHint: session.errorHint, latestMessage: session.latestMessage, status: mappedStatus, attention: attention(for: session, status: mappedStatus, now: now))
    }

    // 在红黄绿之外补一层注意力原因，只服务提醒和文案，不改变原始数据。
    private static func attention(for session: CodexSession, status: SessionStatus, now: Date) -> SessionAttention? {
        guard status == .yellow else { return nil }
        let signal = [session.lastEvent, session.errorHint].compactMap { $0 }.joined(separator: " ").lowercased()
        if containsAny(waitingAttentionSignals, in: signal) { return .waitingInput }
        if containsAny(stalledAttentionSignals, in: signal) { return .stalled }
        if containsActiveEvent(in: signal) && now.timeIntervalSince(session.updatedAt) >= stalledActiveInterval { return .stalled }
        return nil
    }

    // 可见会话聚合遵循任一红、否则任一黄、否则绿。
    private static func aggregateStatus(for sessions: [CodexSession], errorMessage: String?) -> SessionStatus {
        if sessions.isEmpty && errorMessage != nil { return .red }
        if sessions.contains(where: { $0.status == .red }) { return .red }
        if sessions.contains(where: { $0.status == .yellow }) { return .yellow }
        return .green
    }

    // 最近活动取可见会话最大更新时间，无会话时回退到当前时间。
    private static func latestActivity(in sessions: [CodexSession], fallback: Date) -> Date {
        sessions.map(\.updatedAt).max() ?? fallback
    }

    // 使用简单关键词包含匹配，保持规则轻量可读。
    private static func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    // 模型中间消息也表示当前 turn 尚未结束，直到明确的 task_complete 覆盖为完成态。
    private static let activeTurnSignals = ["function_call", "custom_tool_call", "agent_message", "message"]

    // 工具调用、工具输出和模型消息都表示当前 turn 仍在推进。
    private static func containsActiveEvent(in signal: String) -> Bool {
        return activeTurnSignals.contains { signal.contains($0) }
    }
}
