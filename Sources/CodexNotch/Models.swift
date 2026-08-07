import Foundation

// 表示会话当前需要在 notch 中呈现的最小状态颜色。
enum SessionStatus: String, Equatable {
    case red
    case yellow
    case green
}

// 表示会话里更需要用户注意的原因，供 UI 文案和本地通知复用。
enum SessionAttention: String, Equatable {
    case waitingInput
    case stalled

    var shortLabel: String {
        switch self {
        case .waitingInput:
            return "等待输入"
        case .stalled:
            return "可能停滞"
        }
    }

    var notificationTitle: String {
        switch self {
        case .waitingInput:
            return "Codex 等待你处理"
        case .stalled:
            return "Codex 会话可能停滞"
        }
    }
}

// 承载单个 Codex 会话的轻量展示模型。
struct CodexSession: Identifiable, Equatable {
    let id: String
    let title: String
    let cwd: String
    // 创建时间保留原始元数据，最后活动时间用于可见任务排序、文案和状态判断。
    let createdAt: Date
    let updatedAt: Date
    let lastEvent: String?
    let errorHint: String?
    // 最近一条自然语言对话短句，供收起态和展开态摘要展示。
    let latestMessage: String?
    // 最近 task_complete 事件自己的完成时间，避免把 thread 元数据更新时间误当作新完成。
    let completionEventAt: Date?
    let status: SessionStatus
    let attention: SessionAttention?

    // 提供 UI 可直接使用的标题，避免空标题落到视图层处理。
    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? cwdHint : trimmedTitle
    }

    // 将完整工作目录压缩成最后一级目录名，便于 notch 小空间展示。
    var cwdHint: String {
        URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? cwd : URL(fileURLWithPath: cwd).lastPathComponent
    }

    // 提供最近活动的中文相对时间文案，避免 UI 直接格式化 Date。
    var activityText: String {
        let seconds = max(0, Int(Date().timeIntervalSince(updatedAt)))
        if seconds < 60 { return "刚刚" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        return "\(hours) 小时前"
    }
}

// 承载本地自然日内的真实 Token 汇总，缓存输入作为输入的排他子类单独展示。
struct TodayTokenUsage: Equatable {
    let dayStart: Date
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64
    let includedThreadCount: Int
    let excludedThreadCount: Int
    let updatedAt: Date?
    let errorMessage: String?

    static func empty(dayStart: Date) -> TodayTokenUsage {
        TodayTokenUsage(dayStart: dayStart, inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, includedThreadCount: 0, excludedThreadCount: 0, updatedAt: nil, errorMessage: nil)
    }

    var nonCachedInputTokens: Int64 {
        max(0, inputTokens - cachedInputTokens)
    }

    var totalTokens: Int64 {
        inputTokens + outputTokens
    }

    var isComplete: Bool {
        excludedThreadCount == 0 && errorMessage == nil
    }

    // 占比统一使用总 Token 作分母，零用量时稳定返回 0。
    func share(of value: Int64) -> Double {
        guard totalTokens > 0 else { return 0 }
        return Double(value) / Double(totalTokens)
    }

    // 读取失败时保留同一天最后完整数值，同时明确标记当前统计不完整。
    func markedIncomplete(_ message: String) -> TodayTokenUsage {
        TodayTokenUsage(dayStart: dayStart, inputTokens: inputTokens, cachedInputTokens: cachedInputTokens, outputTokens: outputTokens, includedThreadCount: includedThreadCount, excludedThreadCount: max(1, excludedThreadCount), updatedAt: updatedAt, errorMessage: message)
    }
}

// 汇总 notch 当前需要展示的会话列表和整体状态。
struct NotchState: Equatable {
    let sessions: [CodexSession]
    let aggregateStatus: SessionStatus
    let lastUpdatedAt: Date
    let todayTokenUsage: TodayTokenUsage
    // 保留 reader 的首条错误，供收起态和展开态提示。
    let errorMessage: String?
}
