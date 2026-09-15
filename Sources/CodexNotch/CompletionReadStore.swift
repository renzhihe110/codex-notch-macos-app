import Combine
import Foundation

// 只读解析 Codex 官方持久化的未读任务集合，并在文件未变化时复用最近快照。
final class CodexOfficialUnreadReader {
    // 新版 Codex 将未读列表移至根节点，并按身份和主机分组。
    private static let threadReadStateKey = "electron-thread-read-state-v1"
    private static let persistedAtomStateKey = "electron-persisted-atom-state"
    private static let unreadThreadIDsKey = "unread-thread-ids-by-host-v1"
    private let globalStateURL: URL
    private var cachedFileSignature: OfficialUnreadFileSignature?
    private var cachedUnreadSessionIDs: Set<String>?

    init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.globalStateURL = codexHome.appendingPathComponent(".codex-global-state.json")
    }

    // Codex 通过原子替换写入全局状态；读取或解析短暂失败时保留最近一次成功结果并在下轮重试。
    func loadUnreadSessionIDs() -> Set<String>? {
        guard let fileSignature = fileSignature() else { return cachedUnreadSessionIDs }
        if fileSignature == cachedFileSignature { return cachedUnreadSessionIDs }
        do {
            let data = try Data(contentsOf: globalStateURL, options: .mappedIfSafe)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return cachedUnreadSessionIDs
            }
            // 新格式存在时只读取当前未读集合，不合并可能已经过期的旧版或迁移记录。
            let unreadThreadIDsByHostGroups: [[String: [String]]]
            if let readStateValue = root[Self.threadReadStateKey] {
                guard let readState = readStateValue as? [String: Any], let version = readState["version"] as? Int, version == 1, let unreadByIdentity = readState["unreadByIdentity"] as? [String: [String: [String]]] else {
                    return cachedUnreadSessionIDs
                }
                unreadThreadIDsByHostGroups = Array(unreadByIdentity.values)
            } else {
                // 旧版客户端继续读取原有字段；结构异常时保留最近成功快照。
                guard let persistedAtomState = root[Self.persistedAtomStateKey] as? [String: Any], let unreadThreadIDsByHost = persistedAtomState[Self.unreadThreadIDsKey] as? [String: [String]] else {
                    return cachedUnreadSessionIDs
                }
                unreadThreadIDsByHostGroups = [unreadThreadIDsByHost]
            }
            // 沿用按任务 ID 汇总的行为，后续仅展示当前已完成任务的未读状态。
            var unreadSessionIDs = Set<String>()
            for unreadThreadIDsByHost in unreadThreadIDsByHostGroups {
                for hostUnreadSessionIDs in unreadThreadIDsByHost.values {
                    unreadSessionIDs.formUnion(hostUnreadSessionIDs)
                }
            }
            cachedFileSignature = fileSignature
            cachedUnreadSessionIDs = unreadSessionIDs
            return unreadSessionIDs
        } catch {
            return cachedUnreadSessionIDs
        }
    }

    // 文件编号覆盖原子替换场景，时间和大小避免内容未变时重复解析数 MB 的 JSON。
    private func fileSignature() -> OfficialUnreadFileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: globalStateURL.path), let modificationDate = attributes[.modificationDate] as? Date, let size = (attributes[.size] as? NSNumber)?.uint64Value else { return nil }
        let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        return OfficialUnreadFileSignature(fileNumber: fileNumber, modificationDate: modificationDate, size: size)
    }
}

// 向 UI 发布 Codex 官方未读集合与当前已完成任务的交集，不再维护第二套已读状态。
final class CompletionReadStore: ObservableObject {
    static let shared = CompletionReadStore()

    @Published private(set) var unreadSessionIDs = Set<String>()

    // 官方状态读取失败时不覆盖现有快照，避免一次短暂故障把所有蓝点误清空。
    func reconcile(sessions: [CodexSession], officialUnreadSessionIDs: Set<String>?) {
        guard let officialUnreadSessionIDs else { return }
        let completedSessionIDs = Set(sessions.filter(Self.isCompleted).map(\.id))
        let nextUnreadSessionIDs = officialUnreadSessionIDs.intersection(completedSessionIDs)
        guard unreadSessionIDs != nextUnreadSessionIDs else { return }
        unreadSessionIDs = nextUnreadSessionIDs
    }

    // 只有已完成且仍在 Codex 官方未读集合中的任务显示“待查看”。
    func isUnread(_ session: CodexSession) -> Bool {
        Self.isCompleted(session) && unreadSessionIDs.contains(session.id)
    }

    // 缺少真实 task_complete 时间时不推断完成，避免元数据更新时间触发误报。
    private static func isCompleted(_ session: CodexSession) -> Bool {
        session.isCompleted
    }
}

// 记录官方状态文件版本，避免在每秒刷新周期中重复解析未变化的内容。
private struct OfficialUnreadFileSignature: Equatable {
    let fileNumber: UInt64?
    let modificationDate: Date
    let size: UInt64
}
