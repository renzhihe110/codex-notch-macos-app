import AppKit
import Foundation

// 负责从会话点击跳转到 Codex，优先保持用户在 Codex App 内。
final class JumpRouter {
    private let workspace: NSWorkspace
    private let codexBundleIdentifier = "com.openai.codex"
    private let codexApplicationURL = URL(fileURLWithPath: "/Applications/Codex.app")
    private let codexExecutableCandidates = ["/Applications/Codex.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    // 构造 Codex App 已支持的 thread 深链，会被官方 App 映射到 /local/<thread-id>。
    func codexDeepLinkURL(for session: CodexSession) -> URL? {
        codexThreadDeepLinkURL(threadID: session.id)
    }

    // 尝试跳转到指定会话；优先用 Codex App 深链，失败时才打开 Terminal resume。
    func jump(to session: CodexSession, completion: @escaping (Result<Void, JumpRouterError>) -> Void) {
        if openThreadDeepLink(for: session) {
            activateCodexAppSoon(completion: completion)
            return
        }
        openInstalledCodexApp { [weak self] didOpen in
            guard let self else { return }
            if didOpen, self.openThreadDeepLink(for: session) {
                self.activateCodexAppSoon(completion: completion)
            } else {
                self.resumeWithVisibleTerminal(threadID: session.id, completion: completion)
            }
        }
    }

    // 深链只能接受 UUID 形态的本地 conversation id，避免把异常字符串塞进 URL。
    private func codexThreadDeepLinkURL(threadID: String) -> URL? {
        let trimmedID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isUUIDLike(trimmedID) else { return nil }
        return URL(string: "codex://threads/\(trimmedID)")
    }

    // 按 Codex App parser 的 UUID 规则做轻量校验，兼容 UUIDv7。
    private func isUUIDLike(_ value: String) -> Bool {
        value.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil
    }

    // 打开 thread 深链，把会话选择交给 Codex App 自己的 deep link handler。
    private func openThreadDeepLink(for session: CodexSession) -> Bool {
        guard let url = codexDeepLinkURL(for: session) else { return false }
        return workspace.open(url)
    }

    // URL scheme 负责切换路由，短延迟后补一次激活，确保前台看到目标会话。
    private func activateCodexAppSoon(completion: @escaping (Result<Void, JumpRouterError>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.activateRunningCodexApp()
            completion(.success(()))
        }
    }

    // 只激活已经运行的 Codex App，不再打开根 deep link 干扰目标 thread。
    private func activateRunningCodexApp() {
        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: codexBundleIdentifier).first {
            runningApp.activate(options: [.activateIgnoringOtherApps])
        }
    }

    // 依次尝试 bundle id 与固定路径候选，真正是否可打开交给 NSWorkspace 判断。
    private func openInstalledCodexApp(completion: @escaping (Bool) -> Void) {
        if let bundleURL = workspace.urlForApplication(withBundleIdentifier: codexBundleIdentifier) {
            openApplication(at: bundleURL, completion: completion)
            return
        }
        openApplication(at: codexApplicationURL, completion: completion)
    }

    // 使用 NSWorkspace 打开应用；这里不打开根 scheme，避免覆盖目标 thread 深链。
    private func openApplication(at url: URL, completion: @escaping (Bool) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration) { _, error in
            guard error == nil else {
                completion(false)
                return
            }
            completion(true)
        }
    }

    // 通过 Terminal 打开可交互窗口运行 resume，避免后台进程吞掉用户交互。
    private func resumeWithVisibleTerminal(threadID: String, completion: @escaping (Result<Void, JumpRouterError>) -> Void) {
        let command = terminalResumeCommand(threadID: threadID)
        let script = """
        on run argv
            tell application "Terminal"
                activate
                do script item 1 of argv
            end tell
        end run
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, command]
        process.terminationHandler = { process in
            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    completion(.success(()))
                } else {
                    completion(.failure(.unavailable(threadID: threadID)))
                }
            }
        }
        do {
            try process.run()
        } catch {
            completion(.failure(.unavailable(threadID: threadID)))
        }
    }

    // 优先使用 GUI App 内置 CLI，再尝试常见安装路径，最后退回 env 查找。
    private func codexExecutableParts() -> [String] {
        for path in codexExecutableCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return [path]
        }
        return ["/usr/bin/env", "codex"]
    }

    // 拼出给终端执行的命令，每个参数都独立 shell quote。
    private func terminalResumeCommand(threadID: String) -> String {
        (codexExecutableParts() + ["resume", threadID]).map(shellQuoted).joined(separator: " ")
    }

    // 使用 POSIX 单引号规则保护任意参数内容。
    private func shellQuoted(_ value: String) -> String {
        if value.isEmpty { return "''" }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

}

// 给 UI 提供短错误，同时保留完整 thread id 方便用户手动处理。
enum JumpRouterError: LocalizedError {
    case unavailable(threadID: String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let threadID):
            return "跳转失败，thread: \(threadID)"
        }
    }
}
