import AppKit

// 描述当前 App 固定内置的 Codex v2 宠物资源，不扩展为外部宠物管理器。
struct CodexPetManifest: Codable {
    let id: String
    let displayName: String
    let description: String
    let spriteVersionNumber: Int
    let spritesheetPath: String
}

// 统一声明标准动作和 16 个观察方向在 v2 图集中的位置与时长。
enum CodexPetPose: Hashable {
    case idle
    case runningRight
    case runningLeft
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review
    case look(Int)

    var row: Int {
        switch self {
        case .idle: return 0
        case .runningRight: return 1
        case .runningLeft: return 2
        case .waving: return 3
        case .jumping: return 4
        case .failed: return 5
        case .waiting: return 6
        case .running: return 7
        case .review: return 8
        case .look(let direction): return direction < 8 ? 9 : 10
        }
    }

    var columns: [Int] {
        switch self {
        case .idle, .waiting, .running, .review: return Array(0..<6)
        case .runningRight, .runningLeft, .failed: return Array(0..<8)
        case .waving: return Array(0..<4)
        case .jumping: return Array(0..<5)
        case .look(let direction): return [direction % 8]
        }
    }

    var frameDurations: [TimeInterval] {
        switch self {
        case .idle: return [0.28, 0.11, 0.11, 0.14, 0.14, 0.32]
        case .runningRight, .runningLeft: return [0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.22]
        case .waving: return [0.14, 0.14, 0.14, 0.28]
        case .jumping: return [0.14, 0.14, 0.14, 0.14, 0.28]
        case .failed: return [0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.24]
        case .waiting: return [0.15, 0.15, 0.15, 0.15, 0.15, 0.26]
        case .running: return [0.12, 0.12, 0.12, 0.12, 0.12, 0.22]
        case .review: return [0.15, 0.15, 0.15, 0.15, 0.15, 0.28]
        case .look: return [0.25]
        }
    }

    var isOneShot: Bool {
        self == .waving || self == .jumping
    }
}

// 读取内置宠物清单和 WebP 图集，并按需缓存切出的透明帧。
final class CodexPet {
    let manifest: CodexPetManifest
    private let atlas: CGImage
    private var frameCache: [CodexPetPose: [NSImage]] = [:]
    private var themedAtlasCache: [CodexPetTheme: CGImage] = [:]
    private var themedFrameCache: [CodexPetTheme: [CodexPetPose: [NSImage]]] = [:]
    private let cellSize = CGSize(width: 192, height: 208)

    // App bundle 使用标准 Contents/Resources 路径，SwiftPM 命令行运行时回退生成的 Bundle.module。
    private static let bundledResources: Bundle = {
        let appResourceBundleURL = Bundle.main.resourceURL?.appendingPathComponent("CodexNotch_CodexNotch.bundle")
        if let appResourceBundleURL, let appResourceBundle = Bundle(url: appResourceBundleURL) { return appResourceBundle }
        return Bundle.module
    }()

    private init(manifest: CodexPetManifest, atlas: CGImage) {
        self.manifest = manifest
        self.atlas = atlas
    }

    // 固定从 SwiftPM 资源包的 Pets/Trump 子目录加载，缺失或版本错误时立即暴露打包问题。
    static func loadBundled() -> CodexPet {
        guard let manifestURL = bundledURL(named: "pet", fileExtension: "json"), let data = try? Data(contentsOf: manifestURL), let manifest = try? JSONDecoder().decode(CodexPetManifest.self, from: data) else { preconditionFailure("缺少或无法解析 Trump pet.json") }
        guard manifest.id == "trump", manifest.spriteVersionNumber == 2, manifest.spritesheetPath == "spritesheet.webp" else { preconditionFailure("Trump pet.json 与内置 v2 契约不一致") }
        let atlasName = (manifest.spritesheetPath as NSString).deletingPathExtension
        let atlasExtension = (manifest.spritesheetPath as NSString).pathExtension
        guard let atlasURL = bundledURL(named: atlasName, fileExtension: atlasExtension), let image = NSImage(contentsOf: atlasURL), let atlas = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { preconditionFailure("缺少或无法解析 Trump spritesheet.webp") }
        guard atlas.width == 1536, atlas.height == 2288 else { preconditionFailure("Trump v2 图集尺寸必须为 1536×2288") }
        return CodexPet(manifest: manifest, atlas: atlas)
    }

    // SwiftPM 处理资源时可能展平目录，因此同时接受源码子目录和 bundle 根目录中的固定文件名。
    private static func bundledURL(named name: String, fileExtension: String) -> URL? {
        bundledResources.url(forResource: name, withExtension: fileExtension, subdirectory: "Pets/Trump") ?? bundledResources.url(forResource: name, withExtension: fileExtension)
    }

    // 按图集顶端起算的行列裁切帧，避免每次刷新悬浮窗都重复解码 WebP。
    func frames(for pose: CodexPetPose) -> [NSImage] {
        if let cached = frameCache[pose] { return cached }
        let frames = cropFrames(for: pose, from: atlas)
        frameCache[pose] = frames
        return frames
    }

    // 完整主题使用独立 v2 图集；单行动画主题仅替换任务运行姿态。
    func frames(for pose: CodexPetPose, theme: CodexPetTheme) -> [NSImage] {
        if let resourceName = theme.spritesheetResourceName {
            if let cached = themedFrameCache[theme]?[pose] { return cached }
            let frames = cropFrames(for: pose, from: themedAtlas(for: theme, resourceName: resourceName))
            var cache = themedFrameCache[theme] ?? [:]
            cache[pose] = frames
            themedFrameCache[theme] = cache
            return frames
        }
        guard pose == .running, let resourcePrefix = theme.runningResourcePrefix else { return frames(for: pose) }
        if let cached = themedFrameCache[theme]?[pose] { return cached }
        let frames = (0..<6).map { index -> NSImage in
            let name = "\(resourcePrefix)-\(String(format: "%02d", index))"
            guard let url = Self.bundledThemeURL(named: name, fileExtension: "png"), let image = NSImage(contentsOf: url) else { preconditionFailure("缺少或无法解析 Trump 主题帧：\(name).png") }
            image.size = cellSize
            return image
        }
        themedFrameCache[theme] = [pose: frames]
        return frames
    }

    // 主题图集首次使用时才解码，并继续校验完整 v2 尺寸契约。
    private func themedAtlas(for theme: CodexPetTheme, resourceName: String) -> CGImage {
        if let cached = themedAtlasCache[theme] { return cached }
        guard let url = Self.bundledThemeURL(named: resourceName, fileExtension: "webp"), let image = NSImage(contentsOf: url), let atlas = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { preconditionFailure("缺少或无法解析 Trump 主题图集：\(resourceName).webp") }
        guard atlas.width == 1536, atlas.height == 2288 else { preconditionFailure("Trump 主题 v2 图集尺寸必须为 1536×2288") }
        themedAtlasCache[theme] = atlas
        return atlas
    }

    // 所有图集共用同一裁切契约，保证主题切换不会改变动作帧数和时序。
    private func cropFrames(for pose: CodexPetPose, from sourceAtlas: CGImage) -> [NSImage] {
        pose.columns.map { column -> NSImage in
            let rect = CGRect(x: CGFloat(column) * cellSize.width, y: CGFloat(pose.row) * cellSize.height, width: cellSize.width, height: cellSize.height)
            guard let frame = sourceAtlas.cropping(to: rect) else { preconditionFailure("Trump 图集裁切失败：row=\(pose.row), column=\(column)") }
            return NSImage(cgImage: frame, size: cellSize)
        }
    }

    // SwiftPM 可能展平资源目录，因此主题资源同时接受源码子目录和 bundle 根目录。
    private static func bundledThemeURL(named name: String, fileExtension: String) -> URL? {
        bundledResources.url(forResource: name, withExtension: fileExtension, subdirectory: "Pets/Trump/Themes") ?? bundledResources.url(forResource: name, withExtension: fileExtension)
    }
}
