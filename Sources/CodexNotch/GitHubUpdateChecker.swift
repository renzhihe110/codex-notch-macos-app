import Combine
import Foundation

// 通过公开 GitHub Releases 检查新版本；未签名应用只跳转下载页，不在进程内替换 App。
@MainActor
final class GitHubUpdateChecker: ObservableObject {
    private static let latestReleasePageURL = URL(string: "https://github.com/renzhihe110/codex-notch-macos-app/releases/latest")!

    @Published private(set) var isChecking = false
    @Published private(set) var statusMessage = "通过 GitHub Releases 检查公开版本。"
    @Published private(set) var latestReleaseURL: URL?
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.2"

    // 手动检查期间禁用重复请求，并把网络和版本格式错误收敛成设置页可读状态。
    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        latestReleaseURL = nil
        statusMessage = "正在检查更新…"
        Task {
            defer { isChecking = false }
            do {
                let release = try await fetchLatestRelease()
                guard let latestVersion = Self.numericVersion(release.tagName) else {
                    statusMessage = "最新 Release 标签不是支持的版本格式。"
                    return
                }
                if Self.isNewer(latestVersion, than: Self.numericVersion(currentVersion) ?? [0]) {
                    latestReleaseURL = release.htmlURL
                    statusMessage = "发现新版本 \(release.tagName)，当前版本 \(currentVersion)。"
                } else {
                    statusMessage = "当前已是最新版本（\(currentVersion)）。"
                }
            } catch UpdateCheckError.noRelease {
                statusMessage = "GitHub 暂未发布可用版本。"
            } catch UpdateCheckError.httpStatus(let statusCode) {
                statusMessage = "GitHub 返回异常状态（HTTP \(statusCode)）。"
            } catch UpdateCheckError.invalidResponse {
                statusMessage = "GitHub 返回了无法识别的版本信息。"
            // 真实网络错误按常见原因展示，避免再把服务端状态误报成断网。
            } catch let error as URLError {
                switch error.code {
                case .notConnectedToInternet:
                    statusMessage = "当前网络不可用。"
                case .timedOut:
                    statusMessage = "连接 GitHub 超时。"
                default:
                    statusMessage = "无法连接 GitHub（错误码 \(error.code.rawValue)）。"
                }
            } catch {
                statusMessage = "检查失败，请稍后重试。"
            }
        }
    }

    // 跟随公开 latest 页面重定向读取标签，绕开匿名 REST API 的共享 IPv4 限额。
    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.latestReleasePageURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "HEAD"
        request.setValue("CodexNotch/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw UpdateCheckError.invalidResponse }
        if httpResponse.statusCode == 404 { throw UpdateCheckError.noRelease }
        guard httpResponse.statusCode == 200 else { throw UpdateCheckError.httpStatus(httpResponse.statusCode) }
        guard let finalURL = httpResponse.url, finalURL.path.contains("/releases/tag/"), let tagName = finalURL.lastPathComponent.removingPercentEncoding, !tagName.isEmpty else { throw UpdateCheckError.invalidResponse }
        return GitHubRelease(tagName: tagName, htmlURL: finalURL)
    }

    // 版本标签采用 v1.2.3 或 1.2.3；其他命名不参与大小比较，避免误报更新。
    private static func numericVersion(_ rawValue: String) -> [Int]? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" { value.removeFirst() }
        guard let coreVersion = value.split(separator: "-", maxSplits: 1).first else { return nil }
        let components = coreVersion.split(separator: ".")
        guard !components.isEmpty else { return nil }
        var numbers: [Int] = []
        for component in components {
            guard let number = Int(component) else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    // 不同位数按缺失位补零，使 1.2、1.2.0 和 1.2.0.0 具有一致语义。
    private static func isNewer(_ candidate: [Int], than current: [Int]) -> Bool {
        let count = max(candidate.count, current.count)
        for index in 0..<count {
            let candidatePart = index < candidate.count ? candidate[index] : 0
            let currentPart = index < current.count ? current[index] : 0
            if candidatePart != currentPart { return candidatePart > currentPart }
        }
        return false
    }
}

// 只解析版本标签和网页地址，避免把 Release 正文或资产列表带入应用状态。
private struct GitHubRelease {
    let tagName: String
    let htmlURL: URL
}

// 区分“尚无 Release”和其他异常，设置页可给出更准确的提示。
private enum UpdateCheckError: Error {
    case invalidResponse
    case noRelease
    case httpStatus(Int)
}
