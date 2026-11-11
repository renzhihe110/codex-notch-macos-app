import Foundation
import SQLite3

// Codex 数据读取结果，允许 UI 在展示数据的同时呈现读取错误。
struct CodexStoreSnapshot: Equatable {
    let sessions: [CodexSession]
    let errors: [String]
    let loadedAt: Date
}

// 当前轮次仅由明确事件推进；条目完成和统计记录不覆盖任务生命周期。
private struct SessionEventSummary { var lifecycle: SessionLifecycle = .unknown; var turnID: String?; var waitingCallID: String?; var lastEvent: String?; var errorHint: String?; var latestMessage: String?; var completionEventAt: Date?; var lastActivityAt: Date?; var hasLifecycleEvent = false }

// 状态日志保存完整行游标，文件替换、截短或原位改写时重新恢复状态。
private struct SessionRolloutCursor { let url: URL; let fileNumber: UInt64?; var consumedByteCount: UInt64 = 0; var pendingLineData = Data(); var discardingPartialLine = false; var summary = SessionEventSummary(); var lastKnownFileSize: UInt64 = 0; var modificationDate: Date? }

// SQLite 候选库同时记录线程数据时间和文件时间，便于稳定选择当前活跃库。
private struct SQLiteDatabaseCandidate {
    let url: URL
    let latestThreadDate: Date
    let fileFreshness: Date
}

// 保存单个 rollout 的累计 Token 计数，所有字段都保持与 Codex 原始事件一致。
private struct TokenCounters {
    var input: Int64 = 0
    var cachedInput: Int64 = 0
    var output: Int64 = 0
    var total: Int64 = 0

    func delta(from previous: TokenCounters) -> TokenCounters? {
        guard input >= previous.input, cachedInput >= previous.cachedInput, output >= previous.output, total >= previous.total else { return nil }
        return TokenCounters(input: input - previous.input, cachedInput: cachedInput - previous.cachedInput, output: output - previous.output, total: total - previous.total)
    }

    mutating func add(_ other: TokenCounters) -> Bool {
        let inputResult = input.addingReportingOverflow(other.input)
        let cachedResult = cachedInput.addingReportingOverflow(other.cachedInput)
        let outputResult = output.addingReportingOverflow(other.output)
        let totalResult = total.addingReportingOverflow(other.total)
        guard !inputResult.overflow, !cachedResult.overflow, !outputResult.overflow, !totalResult.overflow else { return false }
        input = inputResult.partialValue
        cachedInput = cachedResult.partialValue
        output = outputResult.partialValue
        total = totalResult.partialValue
        return true
    }
}

// 记录 rollout 增量解析位置，避免每秒刷新都重复读取完整日志。
private struct TokenRolloutCursor {
    let url: URL
    let dayStart: Date
    var consumedByteCount: UInt64 = 0
    var pendingLineData = Data()
    var previousUsage = TokenCounters()
    var todayUsage = TokenCounters()
    var latestEventAt: Date?
    var isValid = true
    var lastKnownFileSize: UInt64 = 0
}

// 状态库发现结果保留线程 ID 和路径，缺失路径的线程会计入不完整数量。
private struct TokenRolloutCandidate {
    let threadID: String
    let url: URL?
}

// 只读访问本机 Codex 状态文件，不写入 SQLite 或 jsonl。
final class CodexStoreReader {
    private let codexHome: URL
    private let maxSessions: Int
    // 状态与 Token 使用各自的 reader 实例；这里的游标只在状态读取队列访问。
    private var sessionRolloutCursors: [String: SessionRolloutCursor] = [:]
    private var lastSuccessfulSnapshot: CodexStoreSnapshot?
    private var selectedDatabaseURL: URL?
    private var tokenRolloutCursors: [String: TokenRolloutCursor] = [:]
    private var lastCompleteTodayTokenUsage: TodayTokenUsage?
    // 每个 reader 在自己的串行队列复用日期解析器，避免恢复日志时逐行创建格式化器。
    private let eventDateFormatter = ISO8601DateFormatter()
    private let fractionalEventDateFormatter: ISO8601DateFormatter = { let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter }()

    init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"), maxSessions: Int = 15) {
        self.codexHome = codexHome
        self.maxSessions = maxSessions
    }

    // 首次展示只读取标题等 SQLite 元数据，不触碰会话日志和 Token 统计。
    func loadTitleSnapshot() -> CodexStoreSnapshot {
        let now = Date()
        var sqliteErrors: [String] = []
        var sessions = loadSQLiteSessionsFromAvailableDatabase(errors: &sqliteErrors, includeDetails: false)
        var errors = sqliteErrors
        if sessions.isEmpty {
            var fallbackErrors: [String] = []
            sessions = loadSessionIndexFallback(errors: &fallbackErrors, includeDetails: false)
            errors = sessions.isEmpty ? sqliteErrors + fallbackErrors : fallbackErrors
        }
        return CodexStoreSnapshot(sessions: sessions, errors: errors, loadedAt: now)
    }

    // 优先从 SQLite 读取未归档线程，失败或为空时退回 session_index.jsonl。
    func loadSnapshot() -> CodexStoreSnapshot {
        let now = Date()
        var sqliteErrors: [String] = []
        var sessions = loadSQLiteSessionsFromAvailableDatabase(errors: &sqliteErrors)
        var errors = sqliteErrors
        if sessions.isEmpty {
            var fallbackErrors: [String] = []
            sessions = loadSessionIndexFallback(errors: &fallbackErrors)
            errors = sessions.isEmpty ? sqliteErrors + fallbackErrors : fallbackErrors
        }
        if sessions.isEmpty, let cachedSnapshot = lastSuccessfulSnapshot {
            return CodexStoreSnapshot(sessions: cachedSnapshot.sessions, errors: errors, loadedAt: now)
        }
        // 只保留可见任务游标，避免长期运行后积累已离开列表的日志缓存。
        let visibleSessionIDs = Set(sessions.map(\.id))
        sessionRolloutCursors = sessionRolloutCursors.filter { visibleSessionIDs.contains($0.key) }
        let snapshot = CodexStoreSnapshot(sessions: sessions, errors: errors, loadedAt: now)
        if !sessions.isEmpty {
            lastSuccessfulSnapshot = snapshot
        }
        return snapshot
    }

    // 从当前可用的 Codex SQLite 状态库读取，优先选择 threads 数据最新的库。
    private func loadSQLiteSessionsFromAvailableDatabase(errors: inout [String], includeDetails: Bool = true) -> [CodexSession] {
        let databaseURLs = sqliteDatabaseURLs()
        selectedDatabaseURL = databaseURLs.first
        var collectedErrors: [String] = []
        for databaseURL in databaseURLs {
            var databaseErrors: [String] = []
            let sessions = loadSQLiteSessions(databaseURL: databaseURL, errors: &databaseErrors, includeDetails: includeDetails)
            if !sessions.isEmpty {
                selectedDatabaseURL = databaseURL
                errors.append(contentsOf: databaseErrors)
                return sessions
            }
            collectedErrors.append(contentsOf: databaseErrors)
        }
        if databaseURLs.isEmpty {
            errors.append("SQLite 状态库不存在")
        } else {
            errors.append(contentsOf: collectedErrors)
        }
        return []
    }

    // 自动发现 Codex 可能迁移出来的 state_*.sqlite，避免路径变化后再次写死修复。
    private func sqliteDatabaseURLs() -> [URL] {
        discoverSQLiteDatabaseCandidates().sorted { lhs, rhs in
            if lhs.latestThreadDate != rhs.latestThreadDate { return lhs.latestThreadDate > rhs.latestThreadDate }
            return lhs.fileFreshness > rhs.fileFreshness
        }.map(\.url)
    }

    // 只扫描 ~/.codex 和一级子目录，覆盖 sqlite/ 迁移场景，同时避开 sessions 深层 jsonl。
    private func discoverSQLiteDatabaseCandidates() -> [SQLiteDatabaseCandidate] {
        sqliteSearchDirectories().flatMap { stateDatabaseURLs(in: $0) }.reduce(into: [URL: SQLiteDatabaseCandidate]()) { candidates, url in
            guard let latestThreadDate = latestThreadDate(in: url) else { return }
            candidates[url] = SQLiteDatabaseCandidate(url: url, latestThreadDate: latestThreadDate, fileFreshness: sqliteFreshness(for: url))
        }.map(\.value)
    }

    // 搜索根目录和直接子目录，未来 state_6.sqlite 或 sqlite/state_6.sqlite 都能自动命中。
    private func sqliteSearchDirectories() -> [URL] {
        let childDirectories = (try? FileManager.default.contentsOfDirectory(at: codexHome, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).filter { isDirectory($0) }) ?? []
        return [codexHome] + childDirectories
    }

    // 状态库文件统一使用 state_*.sqlite 命名，避免把 logs/goals/memories 误当作 thread 状态库。
    private func stateDatabaseURLs(in directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []).filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
    }

    // 目录判断走资源值，失败时按非目录处理，保持扫描逻辑保守。
    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    // WAL 模式下最新数据可能只体现在 -wal 文件上，-shm 会被读进程触碰，不能代表数据新旧。
    private func sqliteFreshness(for databaseURL: URL) -> Date {
        let relatedURLs = [databaseURL, URL(fileURLWithPath: databaseURL.path + "-wal")]
        return relatedURLs.compactMap { modificationDate(for: $0) }.max() ?? .distantPast
    }

    // 文件可能不存在或暂时不可读，排序时把这类路径当作最旧处理。
    private func modificationDate(for url: URL) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }

    // 轻量探测 threads 最新更新时间，打不开或结构不匹配的 sqlite 不进入候选列表。
    private func latestThreadDate(in databaseURL: URL) -> Date? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let database else {
            if database != nil { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }
        let columns = threadColumns(database: database)
        guard columns.contains("id") else { return nil }
        let updatedExpr = latestThreadUpdatedExpression(columns: columns)
        return latestThreadDate(database: database, sql: "SELECT MAX(\(updatedExpr)) FROM threads")
    }

    // 迁移库可能有 updated_at_ms 但部分值为空，排序时回退 updated_at。
    private func latestThreadUpdatedExpression(columns: Set<String>) -> String {
        if columns.contains("updated_at_ms") && columns.contains("updated_at") { return "COALESCE(updated_at_ms, updated_at)" }
        if columns.contains("updated_at_ms") { return "updated_at_ms" }
        return nullableColumn("updated_at", columns: columns)
    }

    // MAX(updated_at*) 可能是秒或毫秒，复用现有阈值规则转换成 Date。
    private func latestThreadDate(database: OpaquePointer, sql: String) -> Date? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        let value = sqlite3_column_int64(statement, 0)
        let seconds = value > 10_000_000_000 ? TimeInterval(value) / 1000 : TimeInterval(value)
        return Date(timeIntervalSince1970: seconds)
    }

    private func loadSQLiteSessions(databaseURL: URL, errors: inout [String], includeDetails: Bool) -> [CodexSession] {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard openResult == SQLITE_OK, let database else {
            errors.append("\(databaseURL.lastPathComponent) 打开失败：\(sqliteMessage(database))")
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
        // name 与原始 title 分开读取，供主副标题组合展示；旧数据库会为 name 返回 NULL。
        let nameExpr = nullableColumn("name", columns: columns)
        let titleExpr = nullableColumn("title", columns: columns)
        let cwdExpr = nullableColumn("cwd", columns: columns)
        // 侧边栏会话通过父线程 ID 关联主线程，旧数据库缺少该列时返回 NULL。
        let attachedThreadParentIDExpr = nullableColumn("attached_thread_parent_id", columns: columns)
        // 创建与活动时间分别读取，可见列表在截断前按最后活动时间排序。
        let createdExpr = threadTimestampExpression(baseName: "created_at", columns: columns)
        let updatedExpr = threadTimestampExpression(baseName: "updated_at", columns: columns)
        // 在 LIMIT 前排除已归档和 subagent 元数据，保证最多 15 条都是真实主任务。
        var sessionFilters: [String] = []
        if columns.contains("archived") { sessionFilters.append("COALESCE(archived, 0) = 0") }
        if columns.contains("thread_source") { sessionFilters.append("COALESCE(thread_source, '') != 'subagent'") }
        if columns.contains("source") { sessionFilters.append("COALESCE(source, '') NOT LIKE '%subagent%'") }
        let sessionFilter = sessionFilters.isEmpty ? "" : "WHERE \(sessionFilters.joined(separator: " AND "))"
        let sql = "SELECT id, \(nameExpr), \(titleExpr), \(cwdExpr), \(createdExpr), \(updatedExpr), \(rolloutPathExpr), \(attachedThreadParentIDExpr) FROM threads \(sessionFilter) ORDER BY \(updatedExpr) DESC, id DESC LIMIT ?"

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
                let cleanedName = cleanedTitle(sqliteText(statement, index: 1) ?? "")
                let cwd = sqliteText(statement, index: 3) ?? ""
                let title = preferredTitle(title: sqliteText(statement, index: 2), cwd: cwd, fallback: id)
                let createdAt = dateFromSQLiteMilliseconds(statement: statement, index: 4)
                let updatedAt = dateFromSQLiteMilliseconds(statement: statement, index: 5)
                let summary = includeDetails ? sessionTailSummary(threadID: id, rolloutPath: sqliteText(statement, index: 6), errors: &errors) : SessionEventSummary()
                // 只有数据库明确提供关联字段时才分类，空父线程表示主线程。
                let threadKind: SessionThreadKind?
                if columns.contains("attached_thread_parent_id") {
                    let parentThreadID = sqliteText(statement, index: 7)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    threadKind = parentThreadID.isEmpty ? .main : .sidebar
                } else {
                    threadKind = nil
                }
                sessions.append(CodexSession(id: id, name: cleanedName.isEmpty ? nil : cleanedName, threadKind: threadKind, title: title, cwd: cwd, createdAt: createdAt, updatedAt: updatedAt, lastEvent: summary.lastEvent, errorHint: summary.errorHint, latestMessage: summary.latestMessage, completionEventAt: summary.completionEventAt, lifecycle: summary.lifecycle, lastActivityAt: summary.lastActivityAt, status: .yellow, attention: nil))
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

    // 汇总当前本地自然日的真实 Token 增量，数据库级失败时回退同一天最后完整值。
    func loadTodayTokenUsage(now: Date = Date()) -> TodayTokenUsage {
        let dayStart = Calendar.current.startOfDay(for: now)
        // Token 队列独立发现数据库，不读取任务状态日志，也不共享状态 reader 的可变缓存。
        selectedDatabaseURL = sqliteDatabaseURLs().first
        guard let databaseURL = selectedDatabaseURL, let candidates = todayTokenRolloutCandidates(databaseURL: databaseURL, dayStart: dayStart, now: now) else {
            return fallbackTodayTokenUsage(dayStart: dayStart, message: "Token 统计暂不可用")
        }
        var aggregate = TokenCounters()
        var includedThreadCount = 0
        var excludedThreadCount = 0
        var latestEventAt: Date?
        var activeThreadIDs = Set<String>()
        for candidate in candidates {
            activeThreadIDs.insert(candidate.threadID)
            guard let url = candidate.url, let cursor = updatedTokenCursor(threadID: candidate.threadID, url: url, dayStart: dayStart) else {
                excludedThreadCount += 1
                continue
            }
            guard cursor.isValid, aggregate.add(cursor.todayUsage) else {
                excludedThreadCount += 1
                continue
            }
            includedThreadCount += 1
            if let eventAt = cursor.latestEventAt, latestEventAt == nil || eventAt > latestEventAt! {
                latestEventAt = eventAt
            }
        }
        tokenRolloutCursors = tokenRolloutCursors.filter { activeThreadIDs.contains($0.key) }
        let errorMessage = excludedThreadCount > 0 ? "有 \(excludedThreadCount) 个任务未计入 Token 统计" : nil
        let usage = TodayTokenUsage(dayStart: dayStart, inputTokens: aggregate.input, cachedInputTokens: aggregate.cachedInput, outputTokens: aggregate.output, includedThreadCount: includedThreadCount, excludedThreadCount: excludedThreadCount, updatedAt: latestEventAt, errorMessage: errorMessage)
        if usage.isComplete {
            lastCompleteTodayTokenUsage = usage
        }
        return usage
    }

    // 只回退同一自然日的数据，避免午夜后短暂故障显示昨天用量。
    private func fallbackTodayTokenUsage(dayStart: Date, message: String) -> TodayTokenUsage {
        if let cached = lastCompleteTodayTokenUsage, cached.dayStart == dayStart {
            return cached.markedIncomplete(message)
        }
        return TodayTokenUsage.empty(dayStart: dayStart).markedIncomplete(message)
    }

    // 按数据库真实秒/毫秒字段筛出今天有更新的全部线程，包含今天归档的任务。
    private func todayTokenRolloutCandidates(databaseURL: URL, dayStart: Date, now: Date) -> [TokenRolloutCandidate]? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let database else {
            if database != nil { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }
        let columns = threadColumns(database: database)
        guard columns.contains("id"), columns.contains("rollout_path"), let updatedFilter = tokenTimestampFilter(baseName: "updated_at", columns: columns, date: dayStart), let createdFilter = tokenTimestampFilter(baseName: "created_at", columns: columns, date: now) else { return nil }
        let sql = "SELECT id, rollout_path FROM threads WHERE \(updatedFilter.expression) >= ? AND \(createdFilter.expression) <= ? ORDER BY id"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, updatedFilter.boundValue)
        sqlite3_bind_int64(statement, 2, createdFilter.boundValue)
        var candidates: [TokenRolloutCandidate] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if let threadID = sqliteText(statement, index: 0), !threadID.isEmpty {
                candidates.append(TokenRolloutCandidate(threadID: threadID, url: resolvedRolloutURL(sqliteText(statement, index: 1))))
            }
            stepResult = sqlite3_step(statement)
        }
        return stepResult == SQLITE_DONE ? candidates : nil
    }

    // 迁移期数据库可能同时存在秒和毫秒字段，表达式与绑定值必须使用同一单位。
    private func tokenTimestampFilter(baseName: String, columns: Set<String>, date: Date) -> (expression: String, boundValue: Int64)? {
        let millisecondsName = "\(baseName)_ms"
        if columns.contains(millisecondsName) {
            let expression = columns.contains(baseName) ? "COALESCE(\(millisecondsName), \(baseName) * 1000)" : millisecondsName
            return (expression, Int64((date.timeIntervalSince1970 * 1000).rounded(.down)))
        }
        guard columns.contains(baseName) else { return nil }
        return (baseName, Int64(date.timeIntervalSince1970.rounded(.down)))
    }

    // rollout_path 兼容绝对路径和相对 CODEX_HOME 路径，不在这里暴露真实路径错误。
    private func resolvedRolloutURL(_ rawPath: String?) -> URL? {
        guard let rawPath else { return nil }
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return (path as NSString).isAbsolutePath ? URL(fileURLWithPath: path) : codexHome.appendingPathComponent(path)
    }

    // 文件未变时复用游标；增长时只解析新增字节，缩短、换日或换路径时从头重建。
    private func updatedTokenCursor(threadID: String, url: URL, dayStart: Date) -> TokenRolloutCursor? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path), let number = attributes[.size] as? NSNumber else { return nil }
        let fileSize = number.uint64Value
        var cursor = tokenRolloutCursors[threadID] ?? TokenRolloutCursor(url: url, dayStart: dayStart)
        let requiresReset = cursor.url != url || cursor.dayStart != dayStart || fileSize < cursor.consumedByteCount
        if requiresReset || (!cursor.isValid && fileSize != cursor.lastKnownFileSize) {
            cursor = TokenRolloutCursor(url: url, dayStart: dayStart)
        }
        guard cursor.isValid else { return cursor }
        guard fileSize > cursor.consumedByteCount else {
            cursor.lastKnownFileSize = fileSize
            tokenRolloutCursors[threadID] = cursor
            return cursor
        }
        do {
            try appendTokenEvents(from: url, fileSize: fileSize, cursor: &cursor)
        } catch {
            cursor.isValid = false
        }
        cursor.lastKnownFileSize = fileSize
        tokenRolloutCursors[threadID] = cursor
        return cursor
    }

    // 固定块读取新增日志并保留最后半行，避免完整日志和正在写入的 JSON 行进入内存。
    private func appendTokenEvents(from url: URL, fileSize: UInt64, cursor: inout TokenRolloutCursor) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: cursor.consumedByteCount)
        while cursor.consumedByteCount < fileSize {
            let remaining = fileSize - cursor.consumedByteCount
            let readCount = min(64 * 1024, Int(remaining))
            guard let chunk = try handle.read(upToCount: readCount), !chunk.isEmpty else { break }
            cursor.consumedByteCount += UInt64(chunk.count)
            cursor.pendingLineData.append(chunk)
            try consumeCompleteTokenLines(cursor: &cursor)
        }
    }

    // 只有完整换行记录才参与 JSON 校验，文件尾部半行留待下一次刷新继续拼接。
    private func consumeCompleteTokenLines(cursor: inout TokenRolloutCursor) throws {
        while let newlineIndex = cursor.pendingLineData.firstIndex(of: 0x0A) {
            let line = Data(cursor.pendingLineData[..<newlineIndex])
            let nextIndex = cursor.pendingLineData.index(after: newlineIndex)
            cursor.pendingLineData.removeSubrange(cursor.pendingLineData.startIndex..<nextIndex)
            guard line.range(of: Data("\"token_count\"".utf8)) != nil else { continue }
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any], let payload = object["payload"] as? [String: Any], object["type"] as? String == "event_msg", payload["type"] as? String == "token_count" else { continue }
            guard let eventAt = isoDate(object["timestamp"] as? String ?? ""), let usage = tokenCounters(from: payload), let delta = usage.delta(from: cursor.previousUsage) else { throw CocoaError(.fileReadCorruptFile) }
            cursor.previousUsage = usage
            guard eventAt >= cursor.dayStart else { continue }
            guard cursor.todayUsage.add(delta) else { throw CocoaError(.fileReadTooLarge) }
            cursor.latestEventAt = eventAt
        }
    }

    // token_count 必须满足服务端累计字段关系，异常字段整条 rollout 直接失效。
    private func tokenCounters(from payload: [String: Any]) -> TokenCounters? {
        guard let info = payload["info"] as? [String: Any], let rawUsage = info["total_token_usage"] as? [String: Any], let input = tokenInteger(rawUsage["input_tokens"]), let cachedInput = tokenInteger(rawUsage["cached_input_tokens"]), let output = tokenInteger(rawUsage["output_tokens"]), let total = tokenInteger(rawUsage["total_tokens"]), cachedInput <= input else { return nil }
        let sum = input.addingReportingOverflow(output)
        guard !sum.overflow, sum.partialValue == total else { return nil }
        return TokenCounters(input: input, cachedInput: cachedInput, output: output, total: total)
    }

    // JSON 数值只接受可精确转换的非负 Int64，拒绝布尔值和小数。
    private func tokenInteger(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, String(cString: number.objCType) != "c", let integer = Int64(number.stringValue), integer >= 0 else { return nil }
        return integer
    }

    private func loadSessionIndexFallback(errors: inout [String], includeDetails: Bool = true) -> [CodexSession] {
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
            let summary = includeDetails ? sessionTailSummary(threadID: id, rolloutPath: nil, errors: &errors) : SessionEventSummary()
            sessions.append(CodexSession(id: id, name: nil, threadKind: nil, title: title, cwd: cwd, createdAt: updatedAt, updatedAt: updatedAt, lastEvent: summary.lastEvent, errorHint: summary.errorHint, latestMessage: summary.latestMessage, completionEventAt: summary.completionEventAt, lifecycle: summary.lifecycle, lastActivityAt: summary.lastActivityAt, status: .yellow, attention: nil))
        }
        if sessions.isEmpty {
            errors.append("session_index.jsonl 未读取到可用会话")
        }
        return sessions
    }

    // 文件未变时复用状态，增长时增量读取；临时失败保留可信状态，换文件则重新建立状态。
    private func sessionTailSummary(threadID: String, rolloutPath: String?, errors: inout [String]) -> SessionEventSummary { let cached = sessionRolloutCursors[threadID]; guard let url = sessionFileURL(threadID: threadID, rolloutPath: rolloutPath), let attributes = try? FileManager.default.attributesOfItem(atPath: url.path), let size = (attributes[.size] as? NSNumber)?.uint64Value else { return cached?.summary ?? SessionEventSummary() }; let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value; let modifiedAt = attributes[.modificationDate] as? Date; let requiresReset = cached == nil || cached?.url != url || cached?.fileNumber != fileNumber || size < (cached?.consumedByteCount ?? 0) || (size == cached?.lastKnownFileSize && modifiedAt != cached?.modificationDate); do { var cursor: SessionRolloutCursor; if requiresReset { cursor = try initialSessionCursor(url: url, fileNumber: fileNumber, fileSize: size, errors: &errors) } else { cursor = cached!; try appendSessionEvents(fileSize: size, cursor: &cursor, errors: &errors) }; cursor.lastKnownFileSize = size; cursor.modificationDate = modifiedAt; sessionRolloutCursors[threadID] = cursor; var summary = cursor.summary; if cursor.consumedByteCount < size { summary.lifecycle = .unknown; summary.completionEventAt = nil }; return summary } catch { errors.append("会话状态读取失败，将在下一轮重试"); return requiresReset ? SessionEventSummary() : (cached?.summary ?? SessionEventSummary()) } }

    // 首次从末尾逐次扩大窗口恢复生命周期，只解析完整行；达到 8 MiB 预算仍不确定时保持未知。
    private func initialSessionCursor(url: URL, fileNumber: UInt64?, fileSize: UInt64, errors: inout [String]) throws -> SessionRolloutCursor { let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }; var readSize = min(fileSize, UInt64(256 * 1024)); while true { var cursor = SessionRolloutCursor(url: url, fileNumber: fileNumber); let offset = fileSize - readSize; try handle.seek(toOffset: offset); let data = try handle.read(upToCount: Int(readSize)) ?? Data(); guard UInt64(data.count) == readSize else { throw CocoaError(.fileReadUnknown) }; cursor.consumedByteCount = fileSize; let parts = data.split(separator: 0x0A, omittingEmptySubsequences: false); cursor.discardingPartialLine = offset > 0 && parts.count == 1; cursor.pendingLineData = cursor.discardingPartialLine ? Data() : Data(parts.last ?? Data()); for line in parts.dropFirst(offset > 0 ? 1 : 0).dropLast() { consumeSessionLine(Data(line), summary: &cursor.summary, errors: &errors) }; if cursor.summary.hasLifecycleEvent || offset == 0 || readSize >= 8 * 1024 * 1024 { return cursor }; readSize = min(fileSize, min(readSize * 2, UInt64(8 * 1024 * 1024))) } }

    // 每轮最多处理 8 MiB 新增字节，尾部半行留待后续拼接，避免大日志一次占满刷新队列。
    private func appendSessionEvents(fileSize: UInt64, cursor: inout SessionRolloutCursor, errors: inout [String]) throws { guard fileSize > cursor.consumedByteCount else { return }; let handle = try FileHandle(forReadingFrom: cursor.url); defer { try? handle.close() }; try handle.seek(toOffset: cursor.consumedByteCount); let target = cursor.consumedByteCount + min(fileSize - cursor.consumedByteCount, UInt64(8 * 1024 * 1024)); while cursor.consumedByteCount < target { let count = Int(min(target - cursor.consumedByteCount, UInt64(64 * 1024))); guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { throw CocoaError(.fileReadUnknown) }; cursor.consumedByteCount += UInt64(chunk.count); cursor.pendingLineData.append(chunk); consumeSessionLines(cursor: &cursor, errors: &errors) } }

    // 仅消费换行结束的完整记录；初始化窗口从巨大行中间开始时，先丢弃该行剩余片段。
    private func consumeSessionLines(cursor: inout SessionRolloutCursor, errors: inout [String]) { while let newline = cursor.pendingLineData.firstIndex(of: 0x0A) { let line = Data(cursor.pendingLineData[..<newline]); cursor.pendingLineData.removeSubrange(cursor.pendingLineData.startIndex...newline); if cursor.discardingPartialLine { cursor.discardingPartialLine = false; continue }; consumeSessionLine(line, summary: &cursor.summary, errors: &errors) }; if cursor.discardingPartialLine { cursor.pendingLineData.removeAll(keepingCapacity: false) } }

    // 解析失败不会生成完成信号；仅提示日志读取不完整，不展示任何原始内容。
    private func consumeSessionLine(_ line: Data, summary: inout SessionEventSummary, errors: inout [String]) { guard !line.isEmpty else { return }; guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { let message = "会话日志包含无法解析的完整记录"; if !errors.contains(message) { errors.append(message) }; return }; applySessionEvent(object, summary: &summary) }

    // 每轮开始清除上一轮的完成时间、失败和输入等待，防止旧事件残留影响新任务。
    private func beginSessionTurn(turnID: String?, eventAt: Date?, summary: inout SessionEventSummary) { summary.lifecycle = .running; summary.turnID = turnID; summary.waitingCallID = nil; summary.completionEventAt = nil; summary.errorHint = nil; summary.lastEvent = "task_started"; summary.lastActivityAt = eventAt }

    // 生命周期只接受明确事件；统计、条目完成和未识别记录不会覆盖当前状态。
    private func applySessionEvent(_ object: [String: Any], summary: inout SessionEventSummary) { let payload = object["payload"] as? [String: Any] ?? [:]; guard let type = (payload["type"] as? String) ?? (object["type"] as? String) else { return }; let turnID = payload["turn_id"] as? String; let eventAt = isoDate(object["timestamp"] as? String ?? ""); if type == "task_started" { beginSessionTurn(turnID: turnID, eventAt: eventAt, summary: &summary); summary.hasLifecycleEvent = true; return }; if let turnID, let currentTurnID = summary.turnID, turnID != currentTurnID { return }; summary.latestMessage = conversationMessage(from: object) ?? summary.latestMessage; if Self.sessionActivityEventTypes.contains(type), let eventAt { summary.lastActivityAt = max(summary.lastActivityAt ?? eventAt, eventAt) }; switch type { case "task_complete": guard let completedAt = completionDate(from: object, eventType: type) else { return }; summary.lifecycle = .completed; summary.turnID = turnID ?? summary.turnID; summary.waitingCallID = nil; summary.completionEventAt = completedAt; summary.lastActivityAt = eventAt ?? completedAt; summary.errorHint = nil; summary.lastEvent = type; summary.hasLifecycleEvent = true; if let message = payload["last_agent_message"] as? String, let cleaned = cleanedConversationText(message) { summary.latestMessage = "Codex：" + cleaned }; case "turn_aborted": summary.lifecycle = .stopped; summary.turnID = turnID ?? summary.turnID; summary.waitingCallID = nil; summary.completionEventAt = nil; summary.errorHint = nil; summary.lastEvent = type; summary.hasLifecycleEvent = true; case "user_message": beginSessionTurn(turnID: turnID ?? summary.turnID, eventAt: eventAt, summary: &summary); case "message" where payload["role"] as? String == "user": if summary.lifecycle != .running { beginSessionTurn(turnID: turnID, eventAt: eventAt, summary: &summary) }; case "function_call", "custom_tool_call": guard summary.lifecycle != .completed && summary.lifecycle != .stopped else { return }; if payload["name"] as? String == "request_user_input", let callID = payload["call_id"] as? String { summary.lifecycle = .waitingInput; summary.waitingCallID = callID; summary.lastEvent = "request_user_input" } else { recordSessionActivity(type, summary: &summary) }; case "function_call_output", "custom_tool_call_output": if let callID = payload["call_id"] as? String, callID == summary.waitingCallID { summary.waitingCallID = nil; summary.lifecycle = .running }; recordSessionActivity(type, summary: &summary); case "reasoning", "agent_message", "message": recordSessionActivity(type, summary: &summary); case "error": guard summary.lifecycle != .completed && summary.lifecycle != .stopped else { return }; summary.lifecycle = .failed; summary.completionEventAt = nil; summary.errorHint = "error"; summary.lastEvent = type; default: break } }

    // 普通活动可恢复未知或失败状态，但不能把等待、已停止、已完成任务重新标记为运行。
    private func recordSessionActivity(_ type: String, summary: inout SessionEventSummary) { guard summary.lifecycle != .completed && summary.lifecycle != .stopped && summary.waitingCallID == nil else { return }; summary.lifecycle = .running; summary.completionEventAt = nil; summary.errorHint = nil; summary.lastEvent = type }

    // 事件活动时间只跟随真实任务输出与统计，后台设置更新不会延长停滞阈值。
    private static let sessionActivityEventTypes: Set<String> = ["task_started", "task_complete", "turn_aborted", "user_message", "message", "reasoning", "agent_message", "function_call", "function_call_output", "custom_tool_call", "custom_tool_call_output", "item_completed", "token_count", "token_usage_record", "error"]

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
        threadColumns(database: database) { errors.append($0) }
    }

    // 候选库探测只需要知道能不能读，不把失败噪音暴露给 UI。
    private func threadColumns(database: OpaquePointer) -> Set<String> {
        threadColumns(database: database) { _ in }
    }

    // 读取 threads 表字段，供正式加载和候选探测复用。
    private func threadColumns(database: OpaquePointer, onError: (String) -> Void) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(threads)", -1, &statement, nil) == SQLITE_OK, let statement else {
            onError("SQLite threads 字段检查失败：\(sqliteMessage(database))")
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

    // 迁移期秒与毫秒字段统一到毫秒，避免混合单位破坏时间排序。
    private func threadTimestampExpression(baseName: String, columns: Set<String>) -> String {
        let millisecondsName = "\(baseName)_ms"
        if columns.contains(millisecondsName) && columns.contains(baseName) { return "COALESCE(\(millisecondsName), \(baseName) * 1000)" }
        if columns.contains(millisecondsName) { return millisecondsName }
        return nullableColumn(baseName, columns: columns)
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

    // task_complete 的完成时间来自事件本身，不使用 thread updated_at，避免后台元数据刷新触发误弹。
    private func completionDate(from object: [String: Any], eventType: String?) -> Date? {
        guard eventType == "task_complete" else { return nil }
        let payload = object["payload"] as? [String: Any]
        if let completedAt = payload?["completed_at"] {
            return unixDate(from: completedAt)
        }
        return isoDate((object["timestamp"] as? String) ?? "")
    }

    private func unixDate(from value: Any) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        if let text = value as? String, let seconds = TimeInterval(text) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
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

    // 同时兼容带毫秒和不带毫秒的事件时间，格式化器不跨队列共享。
    private func isoDate(_ value: String) -> Date? { fractionalEventDateFormatter.date(from: value) ?? eventDateFormatter.date(from: value) }
}
