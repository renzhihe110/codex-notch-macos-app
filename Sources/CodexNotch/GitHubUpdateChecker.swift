import Combine
import Foundation

// 通过公开 GitHub Releases 检查新版本；未签名应用只跳转下载页，不在进程内替换 App。
@MainActor
final class GitHubUpdateChecker: ObservableObject {
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/renzhihe110/codex-notch-macos-app/releases/latest")!

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
            } catch {
                statusMessage = "检查失败，请确认网络后重试。"
            }
        }
    }

    // GitHub latest release 接口只读取公开元数据，不携带账号凭证或本地 Codex 数据。
    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CodexNotch/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw UpdateCheckError.invalidResponse }
        if httpResponse.statusCode == 404 { throw UpdateCheckError.noRelease }
        guard httpResponse.statusCode == 200 else { throw UpdateCheckError.invalidResponse }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
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
private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

// 区分“尚无 Release”和其他异常，设置页可给出更准确的提示。
private enum UpdateCheckError: Error {
    case invalidResponse
    case noRelease
}
