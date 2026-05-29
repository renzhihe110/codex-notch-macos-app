import Foundation
import UserNotifications

// 根据会话注意力状态发送本地通知，保持和 Codex 数据读取一样的只读边界。
final class SessionAlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let notificationCenter: UNUserNotificationCenter
    private let repeatInterval: TimeInterval
    private var lastNotifications: [String: Date] = [:]
    private var authorized = false

    init(notificationCenter: UNUserNotificationCenter = .current(), repeatInterval: TimeInterval = 10 * 60) {
        self.notificationCenter = notificationCenter
        self.repeatInterval = repeatInterval
        super.init()
        notificationCenter.delegate = self
    }

    // 启动时请求系统通知权限，用户拒绝时静默跳过后续提醒。
    func requestAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
            }
        }
    }

    // 每次刷新后检查需要提醒的会话，只针对等待输入和可能停滞两类状态。
    func notifyIfNeeded(for sessions: [CodexSession], now: Date = Date()) {
        guard authorized else { return }
        for session in sessions {
            guard let attention = session.attention else { continue }
            let key = "\(session.id):\(attention.rawValue)"
            if let lastDate = lastNotifications[key], now.timeIntervalSince(lastDate) < repeatInterval { continue }
            lastNotifications[key] = now
            scheduleNotification(for: session, attention: attention)
        }
    }

    // 通知正文只使用标题、项目名和相对时间，不包含用户或助手消息正文。
    private func scheduleNotification(for session: CodexSession, attention: SessionAttention) {
        let content = UNMutableNotificationContent()
        content.title = attention.notificationTitle
        content.body = "\(session.displayTitle) · \(session.cwdHint) · \(session.activityText)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "codex-notch-\(session.id)-\(attention.rawValue)", content: content, trigger: nil)
        notificationCenter.add(request)
    }

    // 应用被热键唤起到前台时也展示 banner，避免提醒被前台状态吞掉。
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
