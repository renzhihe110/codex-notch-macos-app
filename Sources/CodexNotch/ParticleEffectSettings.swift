import Combine
import Foundation

// 定义 Dashboard 运行态可切换的五种粒子效果，并提供设置页展示名称。
enum RunningParticleEffect: String, CaseIterable, Identifiable {
    case comet
    case silk
    case aurora
    case orbit
    case edge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .comet:
            return "彗星矩阵"
        case .silk:
            return "金线流光"
        case .aurora:
            return "极光微尘"
        case .orbit:
            return "磁场轨道"
        case .edge:
            return "边缘星火"
        }
    }
}

// 持久化当前粒子效果，并通过 ObservableObject 让设置页和 Dashboard 即时同步。
final class ParticleEffectSettings: ObservableObject {
    static let shared = ParticleEffectSettings()
    static let defaultEffect = RunningParticleEffect.silk
    private static let effectDefaultsKey = "CodexNotch.particleEffect"

    @Published private(set) var effect: RunningParticleEffect
    private let defaults: UserDefaults

    // 无有效保存值时回退金线流光，避免旧版本偏好造成空选项。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.effect = RunningParticleEffect(rawValue: defaults.string(forKey: Self.effectDefaultsKey) ?? "") ?? Self.defaultEffect
    }

    // 用户选择后立即持久化并发布变化，当前可见任务卡无需重开窗口即可刷新。
    func select(effect: RunningParticleEffect) {
        guard self.effect != effect else { return }
        self.effect = effect
        defaults.set(effect.rawValue, forKey: Self.effectDefaultsKey)
    }

    // 全局恢复默认沿用设置页的即时预览语义。
    func resetToDefault() { select(effect: Self.defaultEffect) }
}
