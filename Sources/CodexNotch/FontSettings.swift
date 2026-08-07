import AppKit
import SwiftUI

// 保存全局字体选择，并只向设置页提供常用中文字体。
final class FontSettings: ObservableObject {
    static let shared = FontSettings()
    static let systemFontName = "CodexNotch.system-font"
    private static let fontNameDefaultsKey = "CodexNotch.font.name"
    // 使用常规字重的 PostScript 名称，避免菜单重复展示同一字体的粗体和斜体字形。
    private static let commonChineseFontNames = ["PingFangSC-Regular", "STHeitiSC-Medium", "STSongti-SC-Regular", "STKaitiSC-Regular", "STFangsong", "STXihei", "STSong", "STKaiti", "HiraginoSansGB-W3"]

    @Published private(set) var selectedFontName: String
    let availableFontNames: [String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let installedFontNames = Set(NSFontManager.shared.availableFonts)
        self.availableFontNames = Self.commonChineseFontNames.filter { installedFontNames.contains($0) }
        self.selectedFontName = Self.loadFontName(from: defaults)
    }

    // 设置页仅写入系统默认或当前已安装的字体，防止卸载字体后保存无效配置。
    func select(fontName updatedFontName: String) {
        guard updatedFontName == Self.systemFontName || availableFontNames.contains(updatedFontName), selectedFontName != updatedFontName else { return }
        selectedFontName = updatedFontName
        defaults.set(updatedFontName, forKey: Self.fontNameDefaultsKey)
    }

    // 统一保留原有字号和字重，只替换显示所用的字体字形。
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard selectedFontName != Self.systemFontName else { return .system(size: size, weight: weight) }
        return .custom(selectedFontName, size: size).weight(weight)
    }

    // 设置页显示易读的中文名称，实际持久化仍使用准确的 PostScript 字体名。
    func displayName(for fontName: String) -> String {
        switch fontName {
        case "PingFangSC-Regular": return "苹方"
        case "STHeitiSC-Medium": return "黑体"
        case "STSongti-SC-Regular": return "宋体"
        case "STKaitiSC-Regular": return "楷体"
        case "STFangsong": return "仿宋"
        case "STXihei": return "华文细黑"
        case "STSong": return "华文宋体"
        case "STKaiti": return "华文楷体"
        case "HiraginoSansGB-W3": return "冬青黑体简体中文"
        default: return fontName
        }
    }

    private static func loadFontName(from defaults: UserDefaults) -> String {
        guard let fontName = defaults.string(forKey: fontNameDefaultsKey), commonChineseFontNames.contains(fontName), NSFontManager.shared.availableFonts.contains(fontName) else { return systemFontName }
        return fontName
    }
}
