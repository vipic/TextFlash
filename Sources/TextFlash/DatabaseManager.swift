import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - SQLite 数据库管理（纯 Swift，无第三方依赖）

/// 使用系统内置 SQLite3，NSRecursiveLock 线程安全
final class DatabaseManager {
    static let shared = DatabaseManager()

    private let lock = NSRecursiveLock()
    private var db: OpaquePointer?
    private let dbPath: String
    private(set) var initializationError: String?

    /// 数据库 schema 版本（PRAGMA user_version）
    private var schemaVersion: Int32 {
        get {
            guard db != nil else { return 0 }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return sqlite3_column_int(stmt, 0)
        }
        set { execute("PRAGMA user_version = \(newValue);") }
    }

    private init() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            dbPath = ""
            initializationError = "无法获取 Application Support 目录"
            print("[DatabaseManager] \(initializationError ?? "初始化失败")")
            return
        }

        let dir = appSupport.appendingPathComponent("TextFlash")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            dbPath = dir.appendingPathComponent("textflash.db").path
            initializationError = "无法创建数据库目录: \(error.localizedDescription)"
            print("[DatabaseManager] \(initializationError ?? "初始化失败")")
            return
        }

        dbPath = dir.appendingPathComponent("textflash.db").path
        guard openDatabase() else { return }
        createTables()
        runMigrations()
        migrateFromJSONIfNeeded()
    }

    deinit {
        if let db = db { sqlite3_close(db) }
    }

    // MARK: - 初始化

    @discardableResult
    private func openDatabase() -> Bool {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            initializationError = "无法打开数据库: \(lastError())"
            print("[DatabaseManager] \(initializationError ?? "初始化失败") (\(dbPath))")
            if let db = db { sqlite3_close(db) }
            db = nil
            return false
        }
        execute("PRAGMA journal_mode=WAL;")
        execute("PRAGMA synchronous=FULL;")
        execute("PRAGMA foreign_keys=ON;")
        print("[DatabaseManager] 数据库已打开: \(dbPath)")
        return true
    }

    private func createTables() {
        execute("""
            CREATE TABLE IF NOT EXISTS groups (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0
            );
        """)
        execute("""
            CREATE TABLE IF NOT EXISTS snippets (
                id TEXT PRIMARY KEY,
                group_id TEXT NOT NULL,
                abbreviation TEXT NOT NULL,
                expanded_text TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
                FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE
            );
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_snippets_group ON snippets(group_id, sort_order);")
        execute("CREATE INDEX IF NOT EXISTS idx_snippets_abbr ON snippets(abbreviation);")
        print("[DatabaseManager] 数据库表初始化完成")
    }

    private func runMigrations() {
        let version = schemaVersion
        if version < 1 { schemaVersion = 1 }
    }

    private func lastError() -> String {
        guard let db = db else { return "database is nil" }
        return String(cString: sqlite3_errmsg(db))
    }

    // MARK: - 执行

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard db != nil else {
            print("[DatabaseManager] SQL 执行失败: database is nil")
            return false
        }
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK, let msg = errMsg {
            print("[DatabaseManager] SQL 执行失败: \(String(cString: msg))")
            sqlite3_free(msg)
            return false
        }
        return true
    }

    @discardableResult
    private func transaction(_ body: () -> Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard execute("BEGIN IMMEDIATE TRANSACTION;") else { return false }
        if body() {
            return execute("COMMIT;")
        } else {
            execute("ROLLBACK;")
            return false
        }
    }

    /// 执行参数化 SQL（带闭包绑定参数）
    @discardableResult
    private func executeParam(_ sql: String, bind: (OpaquePointer) -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard db != nil else {
            print("[DatabaseManager] prepare 失败: database is nil — \(sql.prefix(60))")
            return false
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            print("[DatabaseManager] prepare 失败: \(lastError()) — \(sql.prefix(60))")
            return false
        }
        defer { sqlite3_finalize(s) }
        bind(s)
        let rc = sqlite3_step(s)
        let ok = rc == SQLITE_DONE || rc == SQLITE_OK
        if !ok { print("[DatabaseManager] step 失败: \(lastError()) — \(sql.prefix(60))") }
        return ok
    }

    /// 查询（带闭包绑定参数 + 行映射）
    private func queryParam<T>(_ sql: String, bind: (OpaquePointer) -> Void, row: (OpaquePointer) -> T) -> [T] {
        lock.lock(); defer { lock.unlock() }
        guard db != nil else {
            print("[DatabaseManager] query prepare 失败: database is nil")
            return []
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            print("[DatabaseManager] query prepare 失败: \(lastError())")
            return []
        }
        defer { sqlite3_finalize(s) }
        bind(s)
        var results: [T] = []
        while sqlite3_step(s) == SQLITE_ROW { results.append(row(s)) }
        return results
    }

    // MARK: - 分组 CRUD

    func groupCount() -> Int {
        let rows = queryParam("SELECT COUNT(*) FROM groups;", bind: { _ in }) { Int(sqlite3_column_int($0, 0)) }
        return rows.first ?? 0
    }

    func fetchAllGroups() -> [SnippetGroup] {
        let groups = queryParam("SELECT id, name, sort_order FROM groups ORDER BY sort_order;", bind: { _ in }) { stmt in
            let id = UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0))) ?? UUID()
            let name = String(cString: sqlite3_column_text(stmt, 1))
            return SnippetGroup(id: id, name: name, snippets: [])
        }
        var result: [SnippetGroup] = []
        for var group in groups {
            group.snippets = fetchSnippets(forGroup: group.id)
            result.append(group)
        }
        return result
    }

    @discardableResult
    func insertGroup(id: UUID, name: String, sortOrder: Int) -> Bool {
        executeParam("INSERT INTO groups (id, name, sort_order) VALUES (?, ?, ?);") { s in
            sqlite3_bind_text(s, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(s, 2, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(s, 3, Int32(sortOrder))
        }
    }

    @discardableResult
    func updateGroupName(id: UUID, name: String) -> Bool {
        executeParam("UPDATE groups SET name = ? WHERE id = ?;") { s in
            sqlite3_bind_text(s, 1, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(s, 2, id.uuidString, -1, SQLITE_TRANSIENT)
        }
    }

    @discardableResult
    func updateGroupSortOrders(_ orders: [(UUID, Int)]) -> Bool {
        transaction {
            for (id, order) in orders {
                guard executeParam("UPDATE groups SET sort_order = ? WHERE id = ?;", bind: { s in
                    sqlite3_bind_int(s, 1, Int32(order))
                    sqlite3_bind_text(s, 2, id.uuidString, -1, SQLITE_TRANSIENT)
                }) else { return false }
            }
            return true
        }
    }

    @discardableResult
    func deleteGroup(id: UUID) -> Bool {
        executeParam("DELETE FROM groups WHERE id = ?;") { s in
            sqlite3_bind_text(s, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        }
    }

    @discardableResult
    func replaceAllGroups(_ groups: [SnippetGroup]) -> Bool {
        transaction {
            guard execute("DELETE FROM snippets;"),
                  execute("DELETE FROM groups;")
            else { return false }

            for (groupIndex, group) in groups.enumerated() {
                guard executeParam("INSERT INTO groups (id, name, sort_order) VALUES (?, ?, ?);", bind: { s in
                    sqlite3_bind_text(s, 1, group.id.uuidString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(s, 2, group.name, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(s, 3, Int32(groupIndex))
                }) else { return false }

                for (snippetIndex, snippet) in group.snippets.enumerated() {
                    guard executeParam("""
                        INSERT INTO snippets (id, group_id, abbreviation, expanded_text, description, sort_order, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, strftime('%s', 'now'), strftime('%s', 'now'));
                    """, bind: { s in
                        sqlite3_bind_text(s, 1, snippet.id.uuidString, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(s, 2, group.id.uuidString, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(s, 3, snippet.abbreviation, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(s, 4, snippet.expandedText, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(s, 5, snippet.description, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_int(s, 6, Int32(snippetIndex))
                    }) else { return false }
                }
            }
            return true
        }
    }

    // MARK: - 片段 CRUD

    func fetchSnippets(forGroup groupID: UUID) -> [Snippet] {
        queryParam("""
            SELECT id, abbreviation, expanded_text, description, sort_order
            FROM snippets WHERE group_id = ? ORDER BY sort_order;
        """, bind: { s in
            sqlite3_bind_text(s, 1, groupID.uuidString, -1, SQLITE_TRANSIENT)
        }) { stmt in
            let id = UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0))) ?? UUID()
            return Snippet(
                id: id,
                abbreviation: String(cString: sqlite3_column_text(stmt, 1)),
                expandedText: String(cString: sqlite3_column_text(stmt, 2)),
                description: String(cString: sqlite3_column_text(stmt, 3))
            )
        }
    }

    func fetchAllSnippets() -> [Snippet] {
        queryParam("SELECT id, abbreviation, expanded_text, description FROM snippets ORDER BY group_id, sort_order;", bind: { _ in }) { stmt in
            let id = UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0))) ?? UUID()
            return Snippet(
                id: id,
                abbreviation: String(cString: sqlite3_column_text(stmt, 1)),
                expandedText: String(cString: sqlite3_column_text(stmt, 2)),
                description: String(cString: sqlite3_column_text(stmt, 3))
            )
        }
    }

    @discardableResult
    func insertSnippet(id: UUID, groupID: UUID, abbreviation: String, expandedText: String, description: String, sortOrder: Int) -> Bool {
        executeParam("""
            INSERT INTO snippets (id, group_id, abbreviation, expanded_text, description, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, strftime('%s', 'now'), strftime('%s', 'now'));
        """) { s in
            sqlite3_bind_text(s, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(s, 2, groupID.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(s, 3, abbreviation, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(s, 4, expandedText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(s, 5, description, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(s, 6, Int32(sortOrder))
        }
    }

    @discardableResult
    func updateSnippet(id: UUID, abbreviation: String, expandedText: String, description: String) -> Bool {
        executeParam("""
            UPDATE snippets SET abbreviation = ?, expanded_text = ?, description = ?, updated_at = strftime('%s', 'now')
            WHERE id = ?;
        """) { s in
            sqlite3_bind_text(s, 1, abbreviation, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(s, 2, expandedText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(s, 3, description, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(s, 4, id.uuidString, -1, SQLITE_TRANSIENT)
        }
    }

    @discardableResult
    func updateSnippetSortOrders(_ orders: [(UUID, Int)]) -> Bool {
        transaction {
            for (id, order) in orders {
                guard executeParam("UPDATE snippets SET sort_order = ?, updated_at = strftime('%s', 'now') WHERE id = ?;", bind: { s in
                    sqlite3_bind_int(s, 1, Int32(order))
                    sqlite3_bind_text(s, 2, id.uuidString, -1, SQLITE_TRANSIENT)
                }) else { return false }
            }
            return true
        }
    }

    @discardableResult
    func deleteSnippet(id: UUID) -> Bool {
        executeParam("DELETE FROM snippets WHERE id = ?;") { s in
            sqlite3_bind_text(s, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        }
    }

    @discardableResult
    func deleteSnippets(ids: Set<UUID>) -> Bool {
        transaction {
            for id in ids {
                guard executeParam("DELETE FROM snippets WHERE id = ?;", bind: { s in
                    sqlite3_bind_text(s, 1, id.uuidString, -1, SQLITE_TRANSIENT)
                }) else { return false }
            }
            return true
        }
    }

    @discardableResult
    func moveSnippet(id: UUID, toGroup groupID: UUID, sortOrder: Int) -> Bool {
        executeParam("UPDATE snippets SET group_id = ?, sort_order = ?, updated_at = strftime('%s', 'now') WHERE id = ?;") { s in
            sqlite3_bind_text(s, 1, groupID.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(s, 2, Int32(sortOrder))
            sqlite3_bind_text(s, 3, id.uuidString, -1, SQLITE_TRANSIENT)
        }
    }

    // MARK: - JSON 迁移

    /// 首次启动时从旧 JSON 文件迁移数据
    private func migrateFromJSONIfNeeded() {
        if groupCount() > 0 { return }

        let candidates: [URL] = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/Github/TextFlash/data/snippets.json"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/Luigi/TextFlash/data/snippets.json"),
        ]

        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let store = try? JSONDecoder().decode(LegacyStore.self, from: data),
                  !store.groups.isEmpty
            else { continue }

            print("[DatabaseManager] 从 JSON 迁移数据 (\(store.groups.count) 个分组)")
            for (gi, group) in store.groups.enumerated() {
                insertGroup(id: group.id, name: group.name, sortOrder: gi)
                for (si, snippet) in group.snippets.enumerated() {
                    insertSnippet(
                        id: snippet.id, groupID: group.id,
                        abbreviation: snippet.abbreviation,
                        expandedText: snippet.expandedText,
                        description: snippet.description, sortOrder: si
                    )
                }
            }
            print("[DatabaseManager] JSON 迁移完成")
            return
        }
    }
}

// MARK: - 旧 JSON 格式（仅迁移用）

private struct LegacyStore: Codable {
    var groups: [LegacyGroup]
}
private struct LegacyGroup: Codable {
    var id: UUID; var name: String; var snippets: [LegacySnippet]
}
private struct LegacySnippet: Codable {
    var id: UUID; var abbreviation: String; var expandedText: String; var description: String
}
