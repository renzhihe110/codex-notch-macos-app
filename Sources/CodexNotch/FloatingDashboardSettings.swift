import Combine
import Foundation

// 保存悬浮 Dashboard 的用户尺寸，确保窗口重开后沿用最近一次缩放结果。
final class FloatingDashboardSettings: ObservableObject {
    static let shared = FloatingDashboardSettings()
    static let defaultSize = CGSize(width: 460, height: 396)
    static let minimumSize = CGSize(width: 360, height: 260)
    static let maximumSize = CGSize(width: 960, height: 720)
    private static let widthDefaultsKey = "CodexNotch.floatingDashboard.width"
    private static let heightDefaultsKey = "CodexNotch.floatingDashboard.height"
    @Published private(set) var size: CGSize
    private let defaults: UserDefaults

    // 初始化时恢复有效的已保存尺寸，未保存时使用原有卡片尺寸。
    init(defaults: UserDefaults = .standard) { self.defaults = defaults; self.size = Self.loadSize(from: defaults) }

    // 窗口缩放结束后保存限制范围内的尺寸，并通知 SwiftUI 同步布局。
    func update(size: CGSize) { let clampedSize = Self.clampedSize(size); guard self.size != clampedSize else { return }; self.size = clampedSize; defaults.set(clampedSize.width, forKey: Self.widthDefaultsKey); defaults.set(clampedSize.height, forKey: Self.heightDefaultsKey) }

    // 恢复尺寸时拒绝缺失或无效数值，避免异常偏好把窗口缩到不可用大小。
    private static func loadSize(from defaults: UserDefaults) -> CGSize { guard defaults.object(forKey: widthDefaultsKey) != nil, defaults.object(forKey: heightDefaultsKey) != nil else { return defaultSize }; return clampedSize(CGSize(width: defaults.double(forKey: widthDefaultsKey), height: defaults.double(forKey: heightDefaultsKey))) }

    // 尺寸限制保持标题栏、任务行和底部 Token 摘要在缩放后仍可用。
    private static func clampedSize(_ size: CGSize) -> CGSize { CGSize(width: min(max(size.width, minimumSize.width), maximumSize.width), height: min(max(size.height, minimumSize.height), maximumSize.height)) }
}
