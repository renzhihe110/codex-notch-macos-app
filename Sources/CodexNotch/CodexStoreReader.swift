import Foundation
import SQLite3

// Codex 数据读取结果，允许 UI 在展示数据的同时呈现读取错误。
struct CodexStoreSnapshot: Equatable {
    let sessions: [CodexSession]
    let errors: [String]
    let loadedAt: Date
}

// 只读访问本机 Codex 状态文件，不写入 SQLite 或 jsonl。
final class CodexStoreReader {
    private let codexHome: URL
    private let maxSessions: Int
    private let sessionTailLineLimit: Int
    private var lastSuccessfulSnapshot: CodexStoreSnapshot?

    init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"), maxSessions: Int = 8, sessionTailLineLimit: Int = 80) {
        self.codexHome = codexHome
        self.maxSessions = maxSessions
        self.sessionTailLineLimit = sessionTailLineLimit
    }

    // 优先从 SQLite 读取未归档线程，失败或为空时退回 session_index.jsonl。
    func loadSnapshot() -> CodexStoreSnapshot {
        var errors: [String] = []
        var sessions = loadSQLiteSessions(errors: &errors)
        if sessions.isEmpty {
            sessions = loadSessionIndexFallback(errors: &errors)
        }
        if sessions.isEmpty, let cachedSnapshot = lastSuccessfulSnapshot {
            return CodexStoreSnapshot(sessions: cachedSnapshot.sessions, errors: errors, loadedAt: Date())
        }
        let snapshot = CodexStoreSnapshot(sessions: sessions, errors: errors, loadedAt: Date())
        if !sessions.isEmpty {
            lastSuccessfulSnapshot = snapshot
        }
        return snapshot
    }

    private func loadSQLiteSessions(errors: inout [String]) -> [CodexSession] {
        let databaseURL = codexHome.appendingPathComponent("state_5.sqlite")
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard openResult == SQLITE_OK, let database else {
            errors.append("SQLite 打开失败：\(sqliteMessage(database))")
            if database != nil { sqlite3_close(database) }
            return []
        }
        defer { sqlite3_close(database) }

        let columns = threadColumns(database: database, errors: &errors)
        guard columns.contains("id") else {
            errors.append("SQLite threads 表缺少 id 字段")
            return []
        }

        let rolloutPathExpr = nullableColumn("rollout_path", columns: columns)
        let titleExpr = nullableColumn("title", columns: columns)
        let cwdExpr = nullableColumn("cwd", columns: columns)
        let updatedExpr = columns.contains("updated_at_ms") ? "updated_at_ms" : nullableColumn("updated_at", columns: columns)
        let archivedFilter = columns.contains("archived") ? "WHERE COALESCE(archived, 0) = 0" : ""
        let sql = "SELECT id, \(titleExpr), \(cwdExpr), \(updatedExpr), \(rolloutPathExpr) FROM threads \(archivedFilter) ORDER BY \(updatedExpr) DESC LIMIT ?"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            errors.append("SQLite 查询准备失败：\(sqliteMessage(database))")
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(maxSessions))

        var sessions: [CodexSession] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if let id = sqliteText(statement, index: 0), !id.isEmpty {
                let cwd = sqliteText(statement, index: 2) ?? ""
                let title = preferredTitle(title: sqliteText(statement, index: 1), cwd: cwd, fallback: id)
                let updatedAt = dateFromSQLiteMilliseconds(statement: statement, index: 3)
                let summary = sessionTailSummary(threadID: id, rolloutPath: sqliteText(statement, index: 4), errors: &errors)
                sessions.append(CodexSession(id: id, title: title, cwd: cwd, updatedAt: updatedAt, lastEvent: summary.lastEvent, errorHint: summary.errorHint, latestMessage: summary.latestMessage, status: .green, attention: nil))
            }
            stepResult = sqlite3_step(statement)
        }
        if stepResult != SQLITE_DONE {
            errors.append("SQLite 查询执行失败：\(sqliteMessage(database))")
        }
        if sessions.isEmpty {
            errors.append("SQLite 未读取到未归档会话")
        }
        return sessions
    }

    private func loadSessionIndexFallback(errors: inout [String]) -> [CodexSession] {
        let indexURL = codexHome.appendingPathComponent("session_index.jsonl")
        let lines = tailLines(from: indexURL, maxLines: maxSessions * 3, errors: &errors)
        var sessions: [CodexSession] = []
        // 从尾部倒序读取时按 id 去重，保留同一会话的最新索引记录。
        var seenIDs = Set<String>()
        for line in lines.reversed() {
            guard sessions.count < maxSessions, let object = jsonObject(from: line), let id = object["id"] as? String, !id.isEmpty else { continue }
            guard seenIDs.insert(id).inserted else { continue }
            let cwd = object["cwd"] as? String ?? ""
            let title = preferredTitle(title: object["thread_name"] as? String, cwd: cwd, fallback: id)
            let updatedAt = isoDate((object["updated_at"] as? String) ?? "") ?? Date(timeIntervalSince1970: 0)
            let summary = sessionTailSummary(threadID: id, rolloutPath: nil, errors: &errors)
            sessions.append(CodexSession(id: id, title: title, cwd: cwd, updatedAt: updatedAt, lastEvent: summary.lastEvent, errorHint: summary.errorHint, latestMessage: summary.latestMessage, status: .green, attention: nil))
        }
        if sessions.isEmpty {
            errors.append("session_index.jsonl 未读取到可用会话")
        }
        return sessions
    }

    // 从对应会话 jsonl 尾部抽取事件类型、失败关键词和最新自然语言短句。
    private func sessionTailSummary(threadID: String, rolloutPath: String?, errors: inout [String]) -> (lastEvent: String?, errorHint: String?, latestMessage: String?) {
        guard let sessionURL = sessionFileURL(threadID: threadID, rolloutPath: rolloutPath) else { return (nil, nil, nil) }
        let lines = tailLines(from: sessionURL, maxLines: sessionTailLineLimit, errors: &errors)
        let failureWords = ["error", "failed", "failure", "exception", "panic", "timeout", "denied", "cancelled"]
        var lastEvent: String?
        var matchedFailures: [String] = []
        var latestMessage: String?
        for line in lines {
            guard let object = jsonObject(from: line) else { continue }
            let metadata = failureKeywordSource(from: object).lowercased()
            lastEvent = eventType(from: object) ?? lastEvent
            latestMessage = conversationMessage(from: object) ?? latestMessage
            for word in failureWords where metadata.contains(word) && !matchedFailures.contains(word) {
                matchedFailures.append(word)
            }
        }
        return (lastEvent, matchedFailures.isEmpty ? nil : matchedFailures.joined(separator: ", "), latestMessage)
    }

    // SQLite 有 rollout_path 时直接定位文件；fallback 缺路径时才递归查找。
    private func sessionFileURL(threadID: String, rolloutPath: String?) -> URL? {
        if let rolloutPath {
            let trimmedPath = rolloutPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPath.isEmpty {
                let resolvedURL = (trimmedPath as NSString).isAbsolutePath ? URL(fileURLWithPath: trimmedPath) : codexHome.appendingPathComponent(trimmedPath)
                return FileManager.default.fileExists(atPath: resolvedURL.path) ? resolvedURL : nil
            }
        }
        return findSessionFile(threadID: threadID)
    }

    private func findSessionFile(threadID: String) -> URL? {
        let sessionsURL = codexHome.appendingPathComponent("sessions")
        guard let enumerator = FileManager.default.enumerator(at: sessionsURL, includingPropertiesForKeys: nil) else { return nil }
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" && fileURL.lastPathComponent.contains(threadID) {
            return fileURL
        }
        return nil
    }

    private func threadColumns(database: OpaquePointer, errors: inout [String]) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(threads)", -1, &statement, nil) == SQLITE_OK, let statement else {
            errors.append("SQLite threads 字段检查失败：\(sqliteMessage(database))")
            return []
        }
        defer { sqlite3_finalize(statement) }
        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqliteText(statement, index: 1) {
                columns.insert(name)
            }
        }
        return columns
    }

    private func nullableColumn(_ name: String, columns: Set<String>) -> String {
        columns.contains(name) ? name : "NULL"
    }

    private func sqliteText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL, let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    private func dateFromSQLiteMilliseconds(statement: OpaquePointer, index: Int32) -> Date {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return Date(timeIntervalSince1970: 0) }
        let value = sqlite3_column_int64(statement, index)
        let seconds = value > 10_000_000_000 ? TimeInterval(value) / 1000 : TimeInterval(value)
        return Date(timeIntervalSince1970: seconds)
    }

    private func sqliteMessage(_ database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return "未知错误" }
        return String(cString: message)
    }

    // 标题只使用线程标题或安全占位，避免把会话正文片段展示到 UI。
    private func preferredTitle(title: String?, cwd: String, fallback: String) -> String {
        let cwdName = URL(fileURLWithPath: cwd).lastPathComponent
        let cleanedThreadTitle = cleanedTitle(title ?? "")
        if !cleanedThreadTitle.isEmpty {
            return cleanedThreadTitle
        }
        if let linkedOnlyTitle = linkedOnlyTitle(from: title ?? "") {
            return linkedOnlyTitle
        }
        for value in [cwdName.isEmpty ? nil : cwdName, fallback] {
            let trimmed = cleanedTitle(value ?? "")
            if !trimmed.isEmpty { return trimmed }
        }
        return fallback
    }

    // 去掉标题开头的 skill/plugin/file Markdown 链接，让刘海优先显示真实任务内容。
    private func cleanedTitle(_ value: String) -> String {
        let flattened = value.replacingOccurrences(of: "\n", with: " ")
        let pattern = #"^\s*(\[[^\]]+\]\([^)]+\)\s*)+"#
        let range = NSRange(flattened.startIndex..<flattened.endIndex, in: flattened)
        let stripped = (try? NSRegularExpression(pattern: pattern))?.stringByReplacingMatches(in: flattened, range: range, withTemplate: "") ?? flattened
        return stripped.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // 标题只有 skill/plugin 链接时保留链接文本，避免 UI 回退成工作目录名。
    private func linkedOnlyTitle(from value: String) -> String? {
        let flattened = value.replacingOccurrences(of: "\n", with: " ")
        let stripPattern = #"^\s*(\[[^\]]+\]\([^)]+\)\s*)+$"#
        let fullRange = NSRange(flattened.startIndex..<flattened.endIndex, in: flattened)
        guard (try? NSRegularExpression(pattern: stripPattern))?.firstMatch(in: flattened, range: fullRange) != nil else { return nil }
        let linkPattern = #"\[([^\]]+)\]\([^)]+\)"#
        guard let match = (try? NSRegularExpression(pattern: linkPattern))?.firstMatch(in: flattened, range: fullRange), match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: flattened) else { return nil }
        let title = String(flattened[range]).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func tailLines(from url: URL, maxLines: Int, errors: inout [String]) -> [String] {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let fileSize = try handle.seekToEnd()
            let maxBytes = UInt64(max(maxLines, 1) * 4096)
            let offset = fileSize > maxBytes ? fileSize - maxBytes : 0
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            let text = String(decoding: data, as: UTF8.self)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            return Array(lines.suffix(maxLines))
        } catch {
            errors.append("读取 \(url.lastPathComponent) 失败：\(error.localizedDescription)")
            return []
        }
    }

    private func jsonObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private func eventType(from object: [String: Any]) -> String? {
        // Codex rollout 外层 type 多是 event_msg/response_item，真正状态在 payload.type。
        let payload = object["payload"] as? [String: Any]
        if let payloadType = payload?["type"] as? String {
            if payloadType == "token_count" { return nil }
            if let status = payload?["status"] as? String, !status.isEmpty {
                return "\(payloadType):\(status)"
            }
            return payloadType
        }
        return object["type"] as? String
    }

    // 只抽取用户和助手的自然语言正文，跳过工具调用、工具输出和统计事件。
    private func conversationMessage(from object: [String: Any]) -> String? {
        guard let payload = object["payload"] as? [String: Any] else { return nil }
        let payloadType = (payload["type"] as? String) ?? ""
        let role = (payload["role"] as? String)?.lowercased()
        guard shouldDisplayConversation(payloadType: payloadType, role: role) else { return nil }
        let rawMessage = (payload["message"] as? String) ?? textContent(from: payload["content"])
        guard let cleanedMessage = cleanedConversationText(rawMessage ?? "") else { return nil }
        return conversationPrefix(payloadType: payloadType, role: role) + cleanedMessage
    }

    // 仅允许真实对话消息进入刘海屏，避免把 tool output 当成正文滚动展示。
    private func shouldDisplayConversation(payloadType: String, role: String?) -> Bool {
        if let role, role == "user" || role == "assistant" { return true }
        return payloadType == "user_message" || payloadType == "agent_message"
    }

    private func conversationPrefix(payloadType: String, role: String?) -> String {
        if role == "user" || payloadType == "user_message" { return "你：" }
        if role == "assistant" || payloadType == "agent_message" { return "Codex：" }
        return ""
    }

    private func textContent(from value: Any?) -> String? {
        if let text = value as? String { return text }
        guard let items = value as? [Any] else { return nil }
        let pieces = items.compactMap { item -> String? in
            if let text = item as? String { return text }
            guard let object = item as? [String: Any] else { return nil }
            let type = (object["type"] as? String) ?? ""
            guard type == "input_text" || type == "output_text" || type == "text" || object["text"] != nil else { return nil }
            return object["text"] as? String
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: " ")
    }

    private func cleanedConversationText(_ value: String) -> String? {
        let flattened = value.replacingOccurrences(of: "\n", with: " ")
        let collapsed = flattened.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(120))
    }

    private func failureKeywordSource(from object: [String: Any]) -> String {
        let payload = object["payload"] as? [String: Any]
        let values = [
            object["type"] as? String,
            payload?["type"] as? String,
            payload?["name"] as? String,
            payload?["status"] as? String,
            payload?["level"] as? String,
            payload?["code"] as? String,
            payload?["reason"] as? String,
            payload?["kind"] as? String
        ]
        return values.compactMap { $0 }.joined(separator: " ")
    }

    private func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
