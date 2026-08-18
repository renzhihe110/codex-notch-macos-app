import Foundation

// 声明应用内可切换的特朗普主题，并区分单行动画与完整图集资源。
enum CodexPetTheme: String, CaseIterable, Hashable {
    case classic
    case suitSwimming
    case duckFloatSwimming

    var displayName: String {
        switch self {
        case .classic: return "经典西装"
        case .suitSwimming: return "西装游泳"
        case .duckFloatSwimming: return "鸭圈泳装"
        }
    }

    var runningResourcePrefix: String? {
        switch self {
        case .classic: return nil
        case .suitSwimming: return "suit-swim"
        case .duckFloatSwimming: return nil
        }
    }

    var spritesheetResourceName: String? {
        switch self {
        case .classic, .suitSwimming: return nil
        case .duckFloatSwimming: return "duck-float-spritesheet"
        }
    }
}

// 只保存当前主题选择，避免为单一菜单选项引入额外设置页和通知链路。
final class CodexPetThemeSettings {
    static let shared = CodexPetThemeSettings()
    private let defaults: UserDefaults
    private let storageKey = "codexPetTheme"
    private(set) var theme: CodexPetTheme

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = defaults.string(forKey: storageKey).flatMap(CodexPetTheme.init(rawValue:)) ?? .suitSwimming
    }

    // 用户从右键菜单选择后立即落盘，下次启动沿用同一主题。
    func select(theme: CodexPetTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        defaults.set(theme.rawValue, forKey: storageKey)
    }
}
