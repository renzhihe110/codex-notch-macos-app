import AppKit
import ApplicationServices
import Combine
import Foundation

// 保存单个 Xcode 编辑窗口的可见信息和对应辅助功能引用，点击行时可以直接唤醒同一个窗口。
struct XcodeWindowItem: Identifiable {
    let id: String
    let processIdentifier: pid_t
    let element: AXUIElement
    let projectName: String
    let detail: String
    let branchName: String?
    let localDirectory: String?
    let screenLabel: String
    let isCurrent: Bool
}

// 区分权限、进程和窗口为空三种状态，让 Dashboard 给出准确的下一步提示。
enum XcodeWindowAvailability: Equatable {
    case ready
    case permissionRequired
    case xcodeNotRunning
    case noProjectWindows
}

// 通过 macOS Accessibility API 只读发现 Xcode 项目窗口，并负责把用户点击的窗口提升到前台。
final class XcodeWindowManager: ObservableObject {
    @Published private(set) var windows: [XcodeWindowItem] = []
    @Published private(set) var availability: XcodeWindowAvailability = .noProjectWindows
    @Published private(set) var actionErrorMessage: String?
    private let fileManager = FileManager.default
    private let xcodeBundleIdentifier = "com.apple.dt.Xcode"
    private let ignoredWindowTitleFragments = ["settings", "preferences", "organizer", "devices and simulators", "documentation", "welcome to xcode", "设置", "偏好设置", "组织器", "设备与模拟器", "文档", "欢迎使用 xcode"]

    // 每次打开 Dashboard 时请求一次权限，显示期间的定时刷新只检查现有授权状态。
    func refresh(requestPermission: Bool = false) {
        actionErrorMessage = nil
        guard isAccessibilityTrusted(requestPermission: requestPermission) else { windows = []; availability = .permissionRequired; return }
        let runningApplications = NSRunningApplication.runningApplications(withBundleIdentifier: xcodeBundleIdentifier).filter { !$0.isTerminated }
        guard !runningApplications.isEmpty else { windows = []; availability = .xcodeNotRunning; return }
        windows = runningApplications.flatMap(windowItems(for:)).sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
        }
        availability = windows.isEmpty ? .noProjectWindows : .ready
    }

    // 激活 Xcode 进程后设置聚焦窗口并执行 AXRaise，确保切到具体项目而不是只唤醒应用。
    @discardableResult func activate(_ item: XcodeWindowItem) -> Bool {
        guard AXIsProcessTrusted() else { actionErrorMessage = "缺少辅助功能权限，无法切换 Xcode 窗口"; return false }
        guard let runningApplication = NSRunningApplication.runningApplications(withBundleIdentifier: xcodeBundleIdentifier).first(where: { $0.processIdentifier == item.processIdentifier && !$0.isTerminated }) else { actionErrorMessage = "Xcode 已关闭，请重新打开项目"; return false }
        let applicationElement = AXUIElementCreateApplication(item.processIdentifier)
        runningApplication.activate(options: [.activateIgnoringOtherApps])
        AXUIElementSetAttributeValue(item.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        let focusStatus = AXUIElementSetAttributeValue(applicationElement, kAXFocusedWindowAttribute as CFString, item.element)
        let mainStatus = AXUIElementSetAttributeValue(item.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        let raiseStatus = AXUIElementPerformAction(item.element, kAXRaiseAction as CFString)
        guard focusStatus == .success || mainStatus == .success || raiseStatus == .success else { refresh(); actionErrorMessage = "Xcode 窗口已变化，请重新选择"; return false }
        actionErrorMessage = nil
        return true
    }

    // 首次触发使用系统标准授权提示，后续刷新避免重复弹窗。
    private func isAccessibilityTrusted(requestPermission: Bool) -> Bool {
        guard requestPermission else { return AXIsProcessTrusted() }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // 单个 Xcode 进程可能有多个项目窗口，只保留带编辑文档或项目特征的标准窗口。
    private func windowItems(for application: NSRunningApplication) -> [XcodeWindowItem] {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let windowElements: [AXUIElement] = attributeValue(kAXWindowsAttribute as CFString, from: applicationElement) else { return [] }
        let focusedWindow: AXUIElement? = attributeValue(kAXFocusedWindowAttribute as CFString, from: applicationElement)
        return windowElements.compactMap { window in
            guard let title = stringAttribute(kAXTitleAttribute as CFString, from: window)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
            let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: window)
            let document = stringAttribute(kAXDocumentAttribute as CFString, from: window)
            guard isProjectWindow(title: title, subrole: subrole, document: document) else { return nil }
            let displayInfo = displayInfo(title: title, document: document)
            let repositoryInfo = repositoryInfo(for: document)
            let identifier = "\(application.processIdentifier):\(CFHash(window))"
            return XcodeWindowItem(id: identifier, processIdentifier: application.processIdentifier, element: window, projectName: displayInfo.projectName, detail: displayInfo.detail, branchName: repositoryInfo.branchName, localDirectory: repositoryInfo.localDirectory, screenLabel: screenLabel(for: window), isCurrent: focusedWindow.map { CFEqual($0, window) } ?? false)
        }
    }

    // Xcode 的设置、Organizer 和文档窗口同样是标准窗口，需要通过标题和 AXDocument 进一步排除。
    private func isProjectWindow(title: String, subrole: String?, document: String?) -> Bool {
        guard subrole == (kAXStandardWindowSubrole as String) else { return false }
        let normalizedTitle = title.lowercased()
        guard !ignoredWindowTitleFragments.contains(where: normalizedTitle.contains) else { return false }
        let normalizedDocument = document?.lowercased() ?? ""
        let hasProjectContainer = normalizedTitle.contains(".xcworkspace") || normalizedTitle.contains(".xcodeproj") || normalizedDocument.contains(".xcworkspace") || normalizedDocument.contains(".xcodeproj")
        let hasEditorDocument = document?.isEmpty == false
        let hasEditorSeparator = title.contains(" — ") || title.contains(" – ")
        return hasProjectContainer || hasEditorDocument || hasEditorSeparator
    }

    // 优先从文档路径识别 workspace/project，再用窗口标题补齐当前文件信息。
    private func displayInfo(title: String, document: String?) -> (projectName: String, detail: String) {
        let titleParts = normalizedTitleParts(title)
        let projectContainer = projectContainerName(from: document)
        let documentLeaf = documentFileName(from: document)
        let fallbackProjectPart = titleParts.first(where: { !looksLikeSourceFile($0) }) ?? titleParts.first ?? title
        let projectName = strippingProjectExtension(projectContainer ?? fallbackProjectPart)
        var details: [String] = []
        if let projectContainer { appendUnique(projectContainer, to: &details) }
        for part in titleParts where strippingProjectExtension(part) != projectName { appendUnique(part, to: &details) }
        if let documentLeaf, documentLeaf != projectContainer { appendUnique(documentLeaf, to: &details) }
        return (projectName, details.isEmpty ? title : details.prefix(2).joined(separator: " · "))
    }

    // 根据当前文档向上定位 Git 仓库，并返回分支名与可读的本地根目录。
    private func repositoryInfo(for document: String?) -> (branchName: String?, localDirectory: String?) { guard let documentURL = documentURL(from: document) else { return (nil, nil) }; let workingDirectory = projectDirectory(for: documentURL); guard let repositoryRoot = gitOutput(arguments: ["-C", workingDirectory.path, "rev-parse", "--show-toplevel"]) else { return (nil, shortenedPath(workingDirectory)) }; let branchName = gitOutput(arguments: ["-C", repositoryRoot, "branch", "--show-current"]); return (branchName?.isEmpty == false ? branchName : "Detached HEAD", shortenedPath(URL(fileURLWithPath: repositoryRoot))) }

    // 通过 NSString 兼容当前 macOS Foundation 的波浪号路径缩写 API。
    private func shortenedPath(_ url: URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }

    // AXDocument 会指向文件或项目 bundle，统一转成可供 Git 使用的目录。
    private func projectDirectory(for documentURL: URL) -> URL { var isDirectory: ObjCBool = false; guard fileManager.fileExists(atPath: documentURL.path, isDirectory: &isDirectory), isDirectory.boolValue else { return documentURL.deletingLastPathComponent() }; return documentURL }

    // 通过系统 Git 命令兼容普通仓库和 Git worktree，失败时静默按非 Git 项目处理。
    private func gitOutput(arguments: [String]) -> String? { let process = Process(); let output = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git"); process.arguments = arguments; process.standardOutput = output; process.standardError = Pipe(); do { try process.run(); process.waitUntilExit() } catch { return nil }; guard process.terminationStatus == 0, let value = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }; return value }

    // 标题只按 Xcode 常见的长破折号分割，避免破坏项目名内部的普通连字符。
    private func normalizedTitleParts(_ title: String) -> [String] { title.replacingOccurrences(of: " – ", with: " — ").components(separatedBy: " — ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }

    // 文档 URL 的路径中若包含 xcworkspace 或 xcodeproj，使用它作为稳定且易识别的项目名来源。
    private func projectContainerName(from document: String?) -> String? { documentPathComponents(from: document).last(where: { let value = $0.lowercased(); return value.hasSuffix(".xcworkspace") || value.hasSuffix(".xcodeproj") }) }

    // 当前编辑文件名只作为副标题，项目容器本身不会重复显示两次。
    private func documentFileName(from document: String?) -> String? { documentPathComponents(from: document).last }

    // AXDocument 可能返回 file URL 或普通绝对路径，两种形式统一解码为本地 URL。
    private func documentURL(from document: String?) -> URL? { guard let document, !document.isEmpty else { return nil }; if let url = URL(string: document), url.isFileURL { return url }; let path = document.removingPercentEncoding ?? document; guard path.hasPrefix("/") else { return nil }; return URL(fileURLWithPath: path) }

    // 项目名和当前文件解析继续复用统一后的本地文档 URL。
    private func documentPathComponents(from document: String?) -> [String] { documentURL(from: document)?.pathComponents ?? [] }

    // 项目主标题不展示容器扩展名，副标题继续保留完整 workspace/project 文件名。
    private func strippingProjectExtension(_ value: String) -> String { let lowercased = value.lowercased(); if lowercased.hasSuffix(".xcworkspace") || lowercased.hasSuffix(".xcodeproj") { return (value as NSString).deletingPathExtension }; return value }

    // 常见源码扩展名用于区分标题中的项目名与当前文件名。
    private func looksLikeSourceFile(_ value: String) -> Bool { ["swift", "m", "mm", "h", "hpp", "cpp", "c", "cc", "metal", "plist", "storyboard", "xib"].contains((value as NSString).pathExtension.lowercased()) }

    // 副标题去重时忽略大小写，避免标题和 AXDocument 返回同一个文件名。
    private func appendUnique(_ value: String, to values: inout [String]) { guard !values.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }; values.append(value) }

    // 读取窗口中心坐标并映射到主屏或外接屏标签，坐标缺失时保持标签为空。
    private func screenLabel(for window: AXUIElement) -> String {
        guard let position = pointAttribute(kAXPositionAttribute as CFString, from: window), let size = sizeAttribute(kAXSizeAttribute as CFString, from: window), let primaryScreen = NSScreen.screens.first else { return "" }
        let appKitCenter = CGPoint(x: position.x + size.width / 2, y: primaryScreen.frame.maxY - position.y - size.height / 2)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitCenter) }) else { return "" }
        return screen === primaryScreen ? "主屏" : "外接屏"
    }

    // 泛型属性读取集中处理 AXError，调用方只处理实际业务值。
    private func attributeValue<T>(_ attribute: CFString, from element: AXUIElement) -> T? { var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }; return value as? T }

    // 文本属性单独兼容 NSString 桥接，避免不同系统版本返回类型差异。
    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? { let value: CFTypeRef? = rawAttributeValue(attribute, from: element); if let stringValue = value as? String { return stringValue }; if let urlValue = value as? URL { return urlValue.absoluteString }; return nil }

    // AXValue 点坐标读取封装，避免在窗口筛选逻辑中散落指针操作。
    private func pointAttribute(_ attribute: CFString, from element: AXUIElement) -> CGPoint? { guard let value: AXValue = attributeValue(attribute, from: element), AXValueGetType(value) == .cgPoint else { return nil }; var point = CGPoint.zero; guard AXValueGetValue(value, .cgPoint, &point) else { return nil }; return point }

    // AXValue 尺寸读取封装，用于判断窗口所在屏幕。
    private func sizeAttribute(_ attribute: CFString, from element: AXUIElement) -> CGSize? { guard let value: AXValue = attributeValue(attribute, from: element), AXValueGetType(value) == .cgSize else { return nil }; var size = CGSize.zero; guard AXValueGetValue(value, .cgSize, &size) else { return nil }; return size }

    // 原始属性读取只给需要桥接 CFString 的路径使用。
    private func rawAttributeValue(_ attribute: CFString, from element: AXUIElement) -> CFTypeRef? { var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }; return value }
}
