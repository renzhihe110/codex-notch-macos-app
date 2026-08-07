import Combine
import CoreGraphics
import Foundation

// 悬浮球入口尺寸使用固定档位，避免自由输入导致图标和光环溢出。
enum CapsuleSize: String, CaseIterable, Identifiable {
    case compact
    case regular
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact:
            return "小"
        case .regular:
            return "默认"
        case .large:
            return "大"
        }
    }

    var dimensions: CGSize {
        switch self {
        case .compact:
            return CGSize(width: 80, height: 80)
        case .regular:
            return CGSize(width: 96, height: 96)
        case .large:
            return CGSize(width: 112, height: 112)
        }
    }
}

// 负责悬浮球入口尺寸的 UserDefaults 持久化，并通知浮窗控制器即时更新。
final class CapsuleSettings: ObservableObject {
    static let shared = CapsuleSettings()
    static let changedNotification = Notification.Name("CodexNotchCapsuleSettingsChanged")
    private static let sizeDefaultsKey = "CodexNotch.capsule.size"

    @Published private(set) var size: CapsuleSize

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.size = Self.loadSize(from: defaults)
    }

    private let defaults: UserDefaults

    // 设置页切换档位后立即保存，并让当前悬浮球窗口同步变更。
    func select(size updatedSize: CapsuleSize) {
        guard size != updatedSize else { return }
        size = updatedSize
        defaults.set(updatedSize.rawValue, forKey: Self.sizeDefaultsKey)
        NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }

    private static func loadSize(from defaults: UserDefaults) -> CapsuleSize {
        guard let rawValue = defaults.string(forKey: sizeDefaultsKey), let size = CapsuleSize(rawValue: rawValue) else { return .regular }
        return size
    }
}
