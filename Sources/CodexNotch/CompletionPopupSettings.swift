import Combine
import Foundation

// 保存任务完成弹窗的自动关闭时长，供设置页和弹窗控制器共享。
final class CompletionPopupSettings: ObservableObject {
    static let shared = CompletionPopupSettings()
    static let minimumDismissDelaySeconds = 1
    static let maximumDismissDelaySeconds = 30
    private static let dismissDelayDefaultsKey = "CodexNotch.completionPopup.dismissDelaySeconds"

    @Published private(set) var dismissDelaySeconds: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.dismissDelaySeconds = Self.loadDismissDelaySeconds(from: defaults)
    }

    private let defaults: UserDefaults

    // 设置页修改后立即持久化，下一次完成弹窗展示时生效。
    func updateDismissDelaySeconds(_ seconds: Int) {
        let clampedSeconds = Self.clamp(seconds)
        guard dismissDelaySeconds != clampedSeconds else { return }
        dismissDelaySeconds = clampedSeconds
        defaults.set(clampedSeconds, forKey: Self.dismissDelayDefaultsKey)
    }

    // 提供 TimeInterval 给 DispatchQueue 定时关闭使用。
    var dismissDelay: TimeInterval {
        TimeInterval(dismissDelaySeconds)
    }

    private static func loadDismissDelaySeconds(from defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: dismissDelayDefaultsKey) != nil else { return 3 }
        return clamp(defaults.integer(forKey: dismissDelayDefaultsKey))
    }

    private static func clamp(_ seconds: Int) -> Int {
        min(max(seconds, minimumDismissDelaySeconds), maximumDismissDelaySeconds)
    }
}
