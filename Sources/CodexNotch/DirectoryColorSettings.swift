import AppKit
import Combine
import SwiftUI

// 保存任务行项目目录的用户选色，并将 sRGB RGBA 分量持久化到本机设置。
final class DirectoryColorSettings: ObservableObject {
    static let shared = DirectoryColorSettings()
    private static let colorComponentsDefaultsKey = "CodexNotch.directoryColor.components"
    private static let defaultColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.54)
    @Published private(set) var color: Color
    private let defaults: UserDefaults

    // 初始化时恢复上次选择；未选择过时保持原有弱化白色。
    init(defaults: UserDefaults = .standard) { self.defaults = defaults; self.color = Self.loadColor(from: defaults) }

    // 取色盘每次变更都立即通知任务行刷新，并保存供下次启动恢复。
    func update(color: Color) { let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? Self.defaultColor; self.color = Color(nsColor: nsColor); defaults.set([nsColor.redComponent, nsColor.greenComponent, nsColor.blueComponent, nsColor.alphaComponent], forKey: Self.colorComponentsDefaultsKey) }

    // 将 UserDefaults 中的颜色分量还原为 SwiftUI 可直接使用的颜色。
    private static func loadColor(from defaults: UserDefaults) -> Color { guard let components = defaults.array(forKey: colorComponentsDefaultsKey) as? [NSNumber], components.count == 4 else { return Color(nsColor: defaultColor) }; return Color(nsColor: NSColor(srgbRed: components[0].doubleValue, green: components[1].doubleValue, blue: components[2].doubleValue, alpha: components[3].doubleValue)) }
}
