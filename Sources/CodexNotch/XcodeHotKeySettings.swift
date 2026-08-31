import AppKit
import Carbon
import Combine
import Foundation

// 独立保存 Xcode Dashboard 的全局快捷键，避免和 Codex 面板的快捷键状态及错误提示互相覆盖。
final class XcodeHotKeySettings: ObservableObject {
    static let shared = XcodeHotKeySettings()
    static let changedNotification = Notification.Name("CodexNotchXcodeHotKeySettingsChanged")
    private static let keyCodeDefaultsKey = "CodexNotch.xcodeHotKey.keyCode"
    private static let modifierDefaultsKey = "CodexNotch.xcodeHotKey.modifiers"
    private static let keyLabelDefaultsKey = "CodexNotch.xcodeHotKey.label"

    @Published private(set) var hotKey: HotKey
    @Published private(set) var validationMessage: String?
    private let defaults: UserDefaults

    // 首次使用默认 Cmd+F2，并从独立的 UserDefaults 键恢复用户配置。
    init(defaults: UserDefaults = .standard) { self.defaults = defaults; self.hotKey = Self.loadHotKey(from: defaults) }

    // Xcode 快捷键沿用 Codex 已验证的录制规则，但独立保存和通知全局注册器。
    func update(from event: NSEvent) -> Bool {
        guard let updatedHotKey = HotKeySettings.recordedHotKey(from: event) else { validationMessage = "请至少包含 Command、Option 或 Control"; return false }
        save(updatedHotKey)
        validationMessage = nil
        return true
    }

    // 恢复 Xcode Dashboard 的默认 Cmd+F2 快捷键。
    func resetToDefault() { save(Self.defaultHotKey); validationMessage = nil }

    // 设置页取消编辑时恢复打开页面前的 Xcode 快捷键。
    func restore(hotKey restoredHotKey: HotKey) { guard hotKey != restoredHotKey else { return }; save(restoredHotKey); validationMessage = nil }

    // 注册失败时恢复上一条已生效配置，保证设置页与真实全局快捷键一致。
    func restoreAfterRegistrationFailure(_ restoredHotKey: HotKey) { hotKey = restoredHotKey; persist(restoredHotKey); validationMessage = "Xcode 快捷键可能被系统或其他应用占用，已保留上一个快捷键" }

    // 首次注册失败时保留配置并给设置页展示明确提示。
    func reportRegistrationFailure() { validationMessage = "Xcode 快捷键可能被系统或其他应用占用，未能注册全局快捷键" }

    // 注册恢复后清除历史错误，避免设置页继续显示过期状态。
    func clearRegistrationFailure() { validationMessage = nil }

    // 本地按键监听与 Carbon 全局热键使用同一组合键判断。
    func matches(_ event: NSEvent) -> Bool { UInt32(event.keyCode) == hotKey.keyCode && HotKeySettings.carbonModifiers(from: event.modifierFlags) == hotKey.carbonModifiers }

    // 保存后只通知 Xcode Dashboard 的注册器，不触发 Codex 面板重新注册。
    private func save(_ updatedHotKey: HotKey) { hotKey = updatedHotKey; persist(updatedHotKey); NotificationCenter.default.post(name: Self.changedNotification, object: self) }

    // 三个持久化字段与 Codex 快捷键使用不同命名空间。
    private func persist(_ updatedHotKey: HotKey) { defaults.set(Int(updatedHotKey.keyCode), forKey: Self.keyCodeDefaultsKey); defaults.set(Int(updatedHotKey.carbonModifiers), forKey: Self.modifierDefaultsKey); defaults.set(updatedHotKey.keyLabel, forKey: Self.keyLabelDefaultsKey) }

    // 缺少已保存字段时使用 Cmd+F2，旧版本用户无需迁移配置。
    private static func loadHotKey(from defaults: UserDefaults) -> HotKey { guard defaults.object(forKey: keyCodeDefaultsKey) != nil, defaults.object(forKey: modifierDefaultsKey) != nil else { return defaultHotKey }; let keyCode = UInt32(defaults.integer(forKey: keyCodeDefaultsKey)); let modifiers = UInt32(defaults.integer(forKey: modifierDefaultsKey)); let label = defaults.string(forKey: keyLabelDefaultsKey) ?? HotKeySettings.fallbackKeyLabel(for: keyCode); return HotKey(keyCode: keyCode, carbonModifiers: modifiers, keyLabel: label) }

    // 默认快捷键与 Codex 的 Cmd+F1 相邻但不冲突。
    private static var defaultHotKey: HotKey { HotKey(keyCode: UInt32(kVK_F2), carbonModifiers: UInt32(cmdKey), keyLabel: "F2") }
}
