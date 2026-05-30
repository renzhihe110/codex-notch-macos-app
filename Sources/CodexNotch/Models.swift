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
    let updatedAt: Date
    let lastEvent: String?
    let errorHint: String?
    // 最近一条自然语言对话短句，供收起态和展开态摘要展示。
    let latestMessage: String?
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

// 汇总 notch 当前需要展示的会话列表和整体状态。
struct NotchState: Equatable {
    let sessions: [CodexSession]
    let aggregateStatus: SessionStatus
    let lastUpdatedAt: Date
    // 保留 reader 的首条错误，供收起态和展开态提示。
    let errorMessage: String?
}
