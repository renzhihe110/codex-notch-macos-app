import AppKit
import Carbon
import Combine
import Foundation

// 保存和展示用户配置的全局快捷键，供设置页和窗口控制器共享。
struct HotKey: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyLabel: String

    var displayText: String {
        "\(HotKeySettings.displayText(for: carbonModifiers))\(keyLabel)"
    }
}

// 负责快捷键的默认值、录制校验和 UserDefaults 持久化。
final class HotKeySettings: ObservableObject {
    static let shared = HotKeySettings()
    static let changedNotification = Notification.Name("CodexNotchHotKeySettingsChanged")
    private static let keyCodeDefaultsKey = "CodexNotch.hotKey.keyCode"
    private static let modifierDefaultsKey = "CodexNotch.hotKey.modifiers"
    private static let keyLabelDefaultsKey = "CodexNotch.hotKey.label"

    @Published private(set) var hotKey: HotKey
    @Published private(set) var validationMessage: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hotKey = Self.loadHotKey(from: defaults)
    }

    private let defaults: UserDefaults

    // 将录制到的按键转换成 Carbon 可注册的快捷键，避免保存无修饰键的普通字符键。
    func update(from event: NSEvent) -> Bool {
        guard let updatedHotKey = Self.recordedHotKey(from: event) else {
            validationMessage = "请至少包含 Command、Option 或 Control"
            return false
        }
        save(updatedHotKey)
        validationMessage = nil
        return true
    }

    // 恢复到项目 README 里记录的默认 Cmd+F1 行为。
    func resetToDefault() {
        save(Self.defaultHotKey)
        validationMessage = nil
    }

    // 设置页取消编辑时恢复打开页面前的快捷键，并重新通知全局注册器应用旧值。
    func restore(hotKey restoredHotKey: HotKey) {
        guard hotKey != restoredHotKey else { return }
        save(restoredHotKey)
        validationMessage = nil
    }

    // 全局注册失败时恢复到上一条已生效配置，避免设置页展示和实际热键不一致。
    func restoreAfterRegistrationFailure(_ restoredHotKey: HotKey) {
        hotKey = restoredHotKey
        persist(restoredHotKey)
        validationMessage = "快捷键可能被系统或其他应用占用，已保留上一个全局快捷键"
    }

    // 首次全局注册失败时保留用户配置，但明确提示全局快捷键不可用。
    func reportRegistrationFailure() {
        validationMessage = "快捷键可能被系统或其他应用占用，未能注册全局快捷键"
    }

    // 全局注册恢复正常后清理旧提示，避免设置页继续显示过期错误。
    func clearRegistrationFailure() {
        validationMessage = nil
    }

    // AppKit 本地键盘监听需要和全局热键使用同一套比较逻辑。
    func matches(_ event: NSEvent) -> Bool {
        UInt32(event.keyCode) == hotKey.keyCode && Self.carbonModifiers(from: event.modifierFlags) == hotKey.carbonModifiers
    }

    private func save(_ updatedHotKey: HotKey) {
        hotKey = updatedHotKey
        persist(updatedHotKey)
        NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }

    private func persist(_ updatedHotKey: HotKey) {
        defaults.set(Int(updatedHotKey.keyCode), forKey: Self.keyCodeDefaultsKey)
        defaults.set(Int(updatedHotKey.carbonModifiers), forKey: Self.modifierDefaultsKey)
        defaults.set(updatedHotKey.keyLabel, forKey: Self.keyLabelDefaultsKey)
    }

    private static func loadHotKey(from defaults: UserDefaults) -> HotKey {
        guard defaults.object(forKey: keyCodeDefaultsKey) != nil, defaults.object(forKey: modifierDefaultsKey) != nil else { return defaultHotKey }
        let keyCode = UInt32(defaults.integer(forKey: keyCodeDefaultsKey))
        let modifiers = UInt32(defaults.integer(forKey: modifierDefaultsKey))
        let label = defaults.string(forKey: keyLabelDefaultsKey) ?? fallbackKeyLabel(for: keyCode)
        return HotKey(keyCode: keyCode, carbonModifiers: modifiers, keyLabel: label)
    }

    private static var defaultHotKey: HotKey {
        HotKey(keyCode: UInt32(kVK_F1), carbonModifiers: UInt32(cmdKey), keyLabel: "F1")
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let normalizedFlags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if normalizedFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if normalizedFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if normalizedFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if normalizedFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    // Codex 与 Xcode 快捷键共享同一录制规则，避免两个设置入口对修饰键和按键名称产生不同解释。
    static func recordedHotKey(from event: NSEvent) -> HotKey? {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard hasRequiredModifier(modifiers) else { return nil }
        return HotKey(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers, keyLabel: keyLabel(for: event))
    }

    static func displayText(for carbonModifiers: UInt32) -> String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined()
    }

    private static func hasRequiredModifier(_ modifiers: UInt32) -> Bool {
        modifiers & UInt32(cmdKey) != 0 || modifiers & UInt32(optionKey) != 0 || modifiers & UInt32(controlKey) != 0
    }

    private static func keyLabel(for event: NSEvent) -> String {
        if let mappedLabel = specialKeyLabels[event.keyCode] {
            return mappedLabel
        }
        if let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines), !characters.isEmpty {
            return characters.uppercased()
        }
        return fallbackKeyLabel(for: UInt32(event.keyCode))
    }

    static func fallbackKeyLabel(for keyCode: UInt32) -> String {
        specialKeyLabels[UInt16(keyCode)] ?? "Key \(keyCode)"
    }

    // 常见非文本按键需要固定名称，避免设置页显示不可见字符。
    private static let specialKeyLabels: [UInt16: String] = [
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12",
        UInt16(kVK_Return): "Return",
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Delete): "Delete",
        UInt16(kVK_ForwardDelete): "Forward Delete",
        UInt16(kVK_Escape): "Esc",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_Home): "Home",
        UInt16(kVK_End): "End",
        UInt16(kVK_PageUp): "Page Up",
        UInt16(kVK_PageDown): "Page Down"
    ]
}
