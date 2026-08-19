import Combine
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

    // 内置主题使用稳定选择 ID，与外部宠物 ID 分开持久化。
    var selectionID: String { "bundled:trump:\(rawValue)" }

    // 内置主题在统一宠物菜单中带上角色名，避免与外部宠物混淆。
    var petDisplayName: String { "Trump · \(displayName)" }
}

// 标识一个可选宠物来自内置主题还是本机外部包。
fileprivate enum CodexPetSource: Hashable {
    case bundled(CodexPetTheme)
    case external(String)
}

// 为右键菜单和设置页提供同一份稳定、可持久化的宠物选项。
struct CodexPetOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    fileprivate let source: CodexPetSource
}

// 保存单个被跳过目录的短原因，供设置页展示最近一次扫描详情。
struct CodexPetScanIssue: Identifiable, Hashable {
    let directoryName: String
    let reason: String
    var id: String { "\(directoryName)\u{0}\(reason)" }
}

// 汇总最近一次启动或手动扫描的成功数和失败明细。
struct CodexPetScanSummary: Equatable {
    let availableCount: Int
    let issues: [CodexPetScanIssue]
    var skippedCount: Int { issues.count }
    static let empty = CodexPetScanSummary(availableCount: 0, issues: [])
}

// 将当前选择转换为渲染器需要的图集和可选内置主题。
struct CodexPetRenderingSelection {
    let pet: CodexPet
    let theme: CodexPetTheme?
}

// 启动时扫描本机 v2 宠物包，并统一管理选项、持久化、回退和设置页扫描结果。
final class CodexPetCatalog: ObservableObject {
    static let shared = CodexPetCatalog()
    static let changedNotification = Notification.Name("CodexPetCatalogChanged")
    private static let selectionDefaultsKey = "codexPetSelection"
    private static let legacyThemeDefaultsKey = "codexPetTheme"
    private static let defaultSelectionID = CodexPetTheme.suitSwimming.selectionID
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let petsDirectoryURL: URL
    private let bundledPet: CodexPet
    private var externalPets: [String: CodexPet] = [:]
    @Published private(set) var options: [CodexPetOption]
    @Published private(set) var selectedOptionID: String
    @Published private(set) var scanSummary: CodexPetScanSummary = .empty

    private init(defaults: UserDefaults = .standard, fileManager: FileManager = .default, petsDirectoryURL: URL? = nil) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.petsDirectoryURL = petsDirectoryURL ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex/pets", isDirectory: true)
        self.bundledPet = CodexPet.loadBundled()
        self.options = Self.builtInOptions
        let legacySelectionID = defaults.string(forKey: Self.legacyThemeDefaultsKey).flatMap(CodexPetTheme.init(rawValue:))?.selectionID
        self.selectedOptionID = defaults.string(forKey: Self.selectionDefaultsKey) ?? legacySelectionID ?? Self.defaultSelectionID
        rescan()
    }

    // 重新读取一级子目录并原子替换选项；当前选择失效时永久回退到默认内置主题。
    func rescan() {
        let result = scanExternalPets()
        externalPets = result.pets
        options = makeOptions(packages: result.packages)
        scanSummary = CodexPetScanSummary(availableCount: result.packages.count, issues: result.issues)
        if !options.contains(where: { $0.id == selectedOptionID }) { selectedOptionID = Self.defaultSelectionID }
        defaults.set(selectedOptionID, forKey: Self.selectionDefaultsKey)
        NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }

    // 菜单或设置页选择后立即落盘，并通知悬浮宠物从新图集首帧刷新。
    func select(optionID: String) {
        guard selectedOptionID != optionID, options.contains(where: { $0.id == optionID }) else { return }
        selectedOptionID = optionID
        defaults.set(optionID, forKey: Self.selectionDefaultsKey)
        NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }

    // 返回已校验并缓存的当前宠物；目录模型始终保证这里至少能回退到内置资源。
    func renderingSelection() -> CodexPetRenderingSelection {
        guard let option = options.first(where: { $0.id == selectedOptionID }) else { return CodexPetRenderingSelection(pet: bundledPet, theme: .suitSwimming) }
        switch option.source {
        case .bundled(let theme): return CodexPetRenderingSelection(pet: bundledPet, theme: theme)
        case .external(let id): return CodexPetRenderingSelection(pet: externalPets[id] ?? bundledPet, theme: externalPets[id] == nil ? .suitSwimming : nil)
        }
    }

    // 固定把三个内置 Trump 主题放在外部宠物之前。
    private static var builtInOptions: [CodexPetOption] {
        CodexPetTheme.allCases.map { CodexPetOption(id: $0.selectionID, displayName: $0.petDisplayName, source: .bundled($0)) }
    }

    // 外部宠物按显示名排序，只有与其他选项重名时才追加稳定 ID。
    private func makeOptions(packages: [CodexPetPackage]) -> [CodexPetOption] {
        let sortedPackages = packages.sorted { lhs, rhs in
            let result = lhs.displayName.localizedStandardCompare(rhs.displayName)
            return result == .orderedSame ? lhs.id < rhs.id : result == .orderedAscending
        }
        let baseNames = Self.builtInOptions.map(\.displayName) + sortedPackages.map(\.displayName)
        let nameCounts = Dictionary(grouping: baseNames, by: normalizedDisplayName).mapValues(\.count)
        let externalOptions = sortedPackages.map { package -> CodexPetOption in
            let displayName = nameCounts[normalizedDisplayName(package.displayName), default: 0] > 1 ? "\(package.displayName) (\(package.id))" : package.displayName
            return CodexPetOption(id: "external:\(package.id)", displayName: displayName, source: .external(package.id))
        }
        return Self.builtInOptions + externalOptions
    }

    // 名称判重忽略大小写和重音差异，避免菜单出现肉眼相同但无法区分的条目。
    private func normalizedDisplayName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    // 只读取一级真实目录；符号链接、无效包和重复 ID 都进入跳过明细。
    private func scanExternalPets() -> (packages: [CodexPetPackage], pets: [String: CodexPet], issues: [CodexPetScanIssue]) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: petsDirectoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else { return ([], [:], []) }
        let directoryURLs: [URL]
        do {
            directoryURLs = try fileManager.contentsOfDirectory(at: petsDirectoryURL, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        } catch {
            return ([], [:], [CodexPetScanIssue(directoryName: petsDirectoryURL.lastPathComponent, reason: "无法读取宠物目录")])
        }
        var loadedPackages: [(package: CodexPetPackage, pet: CodexPet)] = []
        var issues: [CodexPetScanIssue] = []
        for directoryURL in directoryURLs.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            guard let values = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
                issues.append(CodexPetScanIssue(directoryName: directoryURL.lastPathComponent, reason: "无法读取目录属性"))
                continue
            }
            if values.isSymbolicLink == true {
                issues.append(CodexPetScanIssue(directoryName: directoryURL.lastPathComponent, reason: "不支持符号链接目录"))
                continue
            }
            guard values.isDirectory == true else { continue }
            do {
                loadedPackages.append(try CodexPet.loadExternalPackage(at: directoryURL))
            } catch {
                issues.append(CodexPetScanIssue(directoryName: directoryURL.lastPathComponent, reason: error.localizedDescription))
            }
        }
        let groupedPackages = Dictionary(grouping: loadedPackages, by: { $0.package.id })
        var packages: [CodexPetPackage] = []
        var pets: [String: CodexPet] = [:]
        for id in groupedPackages.keys.sorted() {
            guard let matches = groupedPackages[id] else { continue }
            guard matches.count == 1, let match = matches.first else {
                for duplicate in matches { issues.append(CodexPetScanIssue(directoryName: duplicate.package.directoryName, reason: "宠物 ID \(id) 重复")) }
                continue
            }
            packages.append(match.package)
            pets[id] = match.pet
        }
        return (packages, pets, issues.sorted { $0.directoryName.localizedStandardCompare($1.directoryName) == .orderedAscending })
    }
}
