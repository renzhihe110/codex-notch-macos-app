import Combine
import Foundation

// 保存完整面板和精简小窗各自的尺寸，窗口重开后沿用最近选择的模式。
final class FloatingDashboardSettings: ObservableObject {
    static let shared = FloatingDashboardSettings()
    static let defaultSize = CGSize(width: 460, height: 396)
    static let minimumSize = CGSize(width: 360, height: 260)
    static let maximumSize = CGSize(width: 960, height: 720)
    // 放大文字后同步提高小窗下限，旧尺寸恢复时也能容纳四条清晰的双行任务。
    static let compactDefaultSize = CGSize(width: 320, height: 230)
    private static let widthDefaultsKey = "CodexNotch.floatingDashboard.width"
    private static let heightDefaultsKey = "CodexNotch.floatingDashboard.height"
    private static let compactWidthDefaultsKey = "CodexNotch.floatingDashboard.compactWidth"
    private static let compactHeightDefaultsKey = "CodexNotch.floatingDashboard.compactHeight"
    private static let compactModeDefaultsKey = "CodexNotch.floatingDashboard.isCompact"
    // 小窗坐标独立持久化，大窗尺寸或位置变化不会覆盖它。
    private static let compactXDefaultsKey = "CodexNotch.floatingDashboard.compactX"
    private static let compactYDefaultsKey = "CodexNotch.floatingDashboard.compactY"
    @Published private(set) var size: CGSize
    @Published private(set) var isCompact: Bool
    // 快捷键专用窗口固定使用完整模式，不修改原窗口的小窗偏好。
    let allowsCompactMode: Bool
    private let defaults: UserDefaults

    // 原有尺寸键继续供完整面板使用，未选择小窗的用户保持现有布局。
    init(defaults: UserDefaults = .standard, allowsCompactMode: Bool = true) {
        self.defaults = defaults
        self.allowsCompactMode = allowsCompactMode
        let isCompact = allowsCompactMode && defaults.bool(forKey: Self.compactModeDefaultsKey)
        self.isCompact = isCompact
        self.size = Self.loadSize(from: defaults, isCompact: isCompact)
    }

    // 小窗允许缩到设计尺寸，完整面板保持原有的最小窗口限制。
    var currentMinimumSize: CGSize {
        isCompact ? Self.compactDefaultSize : Self.minimumSize
    }

    // 缺失或无效坐标沿用默认定位，零和负坐标仍支持屏幕边缘及多屏排列。
    var compactOrigin: CGPoint? {
        guard let x = defaults.object(forKey: Self.compactXDefaultsKey) as? NSNumber, let y = defaults.object(forKey: Self.compactYDefaultsKey) as? NSNumber else {
            return nil
        }
        let origin = CGPoint(x: x.doubleValue, y: y.doubleValue)
        guard origin.x.isFinite, origin.y.isFinite else {
            return nil
        }
        return origin
    }

    // 仅小窗模式保存位置，快捷键详细窗口不得写入小窗坐标。
    func updateCompactOrigin(_ origin: CGPoint) {
        guard allowsCompactMode, isCompact, origin.x.isFinite, origin.y.isFinite else {
            return
        }
        defaults.set(origin.x, forKey: Self.compactXDefaultsKey)
        defaults.set(origin.y, forKey: Self.compactYDefaultsKey)
    }

    // 窗口缩放结束后保存限制范围内的尺寸，并通知 SwiftUI 同步布局。
    func update(size: CGSize) {
        let clampedSize = Self.clampedSize(size, isCompact: isCompact)
        guard self.size != clampedSize else {
            return
        }
        self.size = clampedSize
        defaults.set(clampedSize.width, forKey: isCompact ? Self.compactWidthDefaultsKey : Self.widthDefaultsKey)
        defaults.set(clampedSize.height, forKey: isCompact ? Self.compactHeightDefaultsKey : Self.heightDefaultsKey)
    }

    // 切换时加载另一种模式的尺寸，不覆盖用户已经保存的完整面板大小。
    func toggleCompactMode() {
        guard allowsCompactMode else {
            return
        }
        isCompact.toggle()
        defaults.set(isCompact, forKey: Self.compactModeDefaultsKey)
        size = Self.loadSize(from: defaults, isCompact: isCompact)
    }

    // 独立详细窗口再次打开时读取最新完整尺寸，不改变另一窗口的布局或当前尺寸。
    func reloadSize() {
        size = Self.loadSize(from: defaults, isCompact: isCompact)
    }

    // 恢复尺寸时拒绝缺失或无效数值，避免异常偏好把窗口缩到不可用大小。
    private static func loadSize(from defaults: UserDefaults, isCompact: Bool) -> CGSize {
        let widthKey = isCompact ? compactWidthDefaultsKey : widthDefaultsKey
        let heightKey = isCompact ? compactHeightDefaultsKey : heightDefaultsKey
        guard defaults.object(forKey: widthKey) != nil, defaults.object(forKey: heightKey) != nil else {
            return isCompact ? compactDefaultSize : defaultSize
        }
        return clampedSize(CGSize(width: defaults.double(forKey: widthKey), height: defaults.double(forKey: heightKey)), isCompact: isCompact)
    }

    // 两种模式共用原生缩放上限，小窗至少容纳标题栏和约四条紧凑任务。
    private static func clampedSize(_ size: CGSize, isCompact: Bool) -> CGSize {
        let minimum = isCompact ? compactDefaultSize : minimumSize
        return CGSize(width: min(max(size.width, minimum.width), maximumSize.width), height: min(max(size.height, minimum.height), maximumSize.height))
    }
}
