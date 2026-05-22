import Foundation
import Combine

// MARK: - 通知名称

extension Notification.Name {
    /// 片段数据变更时广播，后端引擎监听此通知以重载匹配表
    static let textFlashSnippetsDidChange = Notification.Name("TextFlashSnippetsDidChange")
}

// MARK: - SnippetManager

/// 片段管理器的 ViewModel — 负责分组/片段的 CRUD，持久化到 SQLite，以及通知后端引擎
@MainActor
final class SnippetManager: ObservableObject {

    // MARK: 发布属性

    @Published var groups: [SnippetGroup] = []
    @Published var selectedGroupID: UUID? {
        didSet {
            if selectedGroupID != oldValue {
                selectedSnippetID = nil
            }
        }
    }
    @Published var selectedSnippetID: UUID?
    @Published var operationErrorMessage: String?

    // MARK: 搜索

    @Published var searchQuery: String = ""

    /// 当前分组中匹配搜索的片段
    var filteredSnippets: [Snippet] {
        let snippets = selectedGroupSnippets
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return snippets }
        return snippets.filter { snippet in
            snippet.abbreviation.localizedCaseInsensitiveContains(q) ||
            snippet.description.localizedCaseInsensitiveContains(q) ||
            snippet.expandedText.localizedCaseInsensitiveContains(q)
        }
    }

    // MARK: 编辑状态（由 View 驱动）

    @Published var editMode: EditMode = .inactive {
        didSet {
            switch editMode {
            case .new(let groupID):
                editingSnippet = Snippet()
                editingGroupID = groupID
            case .existing(let snippet):
                editingSnippet = snippet
                editingGroupID = selectedGroupID
            case .inactive:
                editingSnippet = nil
                editingGroupID = nil
            }
        }
    }
    @Published var editingSnippet: Snippet?
    @Published var editingGroupID: UUID?

    enum EditMode: Equatable {
        case inactive
        case new(inGroup: UUID)
        case existing(Snippet)
    }

    enum OperationError: LocalizedError {
        case databaseWriteFailed

        var errorDescription: String? {
            switch self {
            case .databaseWriteFailed:
                return "数据库写入失败"
            }
        }
    }

    // MARK: 计算属性

    var selectedGroup: SnippetGroup? {
        groups.first { $0.id == selectedGroupID }
    }

    var selectedGroupSnippets: [Snippet] {
        selectedGroup?.snippets ?? []
    }

    // MARK: 持久化

    private let db = DatabaseManager.shared

    init() {
        reload()
        if groups.isEmpty {
            createDefaultGroup()
        }
    }

    // MARK: - 分组操作

    func addGroup(name: String) {
        let group = SnippetGroup(name: name)
        let sortOrder = groups.count
        guard db.insertGroup(id: group.id, name: name, sortOrder: sortOrder) else {
            reportDatabaseWriteFailure()
            return
        }
        groups.append(group)
        selectedGroupID = group.id
        notify()
    }

    func renameGroup(_ group: SnippetGroup, to name: String) {
        guard let idx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        guard db.updateGroupName(id: group.id, name: name) else {
            reportDatabaseWriteFailure()
            return
        }
        groups[idx].name = name
        notify()
    }

    func deleteGroup(_ group: SnippetGroup) {
        guard db.deleteGroup(id: group.id) else {
            reportDatabaseWriteFailure()
            return
        }
        groups.removeAll { $0.id == group.id }
        if selectedGroupID == group.id {
            selectedGroupID = groups.first?.id
        }
        notify()
    }

    func moveGroup(from source: IndexSet, to destination: Int) {
        var reordered = groups
        reordered.move(fromOffsets: source, toOffset: destination)
        let orders = reordered.enumerated().map { ($0.element.id, $0.offset) }
        guard db.updateGroupSortOrders(orders) else {
            reportDatabaseWriteFailure()
            return
        }
        groups = reordered
        notify()
    }

    // MARK: - 片段操作

    func addSnippet(abbreviation: String, expandedText: String, description: String, toGroup groupID: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let snippet = Snippet(
            abbreviation: abbreviation,
            expandedText: expandedText,
            description: description
        )
        let sortOrder = groups[idx].snippets.count
        guard db.insertSnippet(
            id: snippet.id,
            groupID: groupID,
            abbreviation: abbreviation,
            expandedText: expandedText,
            description: description,
            sortOrder: sortOrder
        ) else {
            reportDatabaseWriteFailure()
            return
        }
        groups[idx].snippets.append(snippet)
        selectedSnippetID = snippet.id
        notify()
    }

    func updateSnippet(_ snippet: Snippet, abbreviation: String, expandedText: String, description: String, inGroup groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }),
              let sIdx = groups[gIdx].snippets.firstIndex(where: { $0.id == snippet.id })
        else { return }
        guard db.updateSnippet(id: snippet.id, abbreviation: abbreviation, expandedText: expandedText, description: description) else {
            reportDatabaseWriteFailure()
            return
        }
        groups[gIdx].snippets[sIdx].abbreviation = abbreviation
        groups[gIdx].snippets[sIdx].expandedText = expandedText
        groups[gIdx].snippets[sIdx].description = description
        notify()
    }

    func deleteSnippet(_ snippet: Snippet, fromGroup groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard db.deleteSnippet(id: snippet.id) else {
            reportDatabaseWriteFailure()
            return
        }
        groups[gIdx].snippets.removeAll { $0.id == snippet.id }
        if selectedSnippetID == snippet.id {
            selectedSnippetID = nil
        }
        notify()
    }

    func deleteSnippets(_ snippets: Set<Snippet>, fromGroup groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let ids = Set(snippets.map { $0.id })
        guard db.deleteSnippets(ids: ids) else {
            reportDatabaseWriteFailure()
            return
        }
        groups[gIdx].snippets.removeAll { ids.contains($0.id) }
        if let sel = selectedSnippetID, ids.contains(sel) {
            selectedSnippetID = nil
        }
        notify()
    }

    func moveSnippet(from source: IndexSet, to destination: Int, inGroup groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        var reordered = groups[gIdx].snippets
        reordered.move(fromOffsets: source, toOffset: destination)
        let orders = reordered.enumerated().map { ($0.element.id, $0.offset) }
        guard db.updateSnippetSortOrders(orders) else {
            reportDatabaseWriteFailure()
            return
        }
        groups[gIdx].snippets = reordered
        notify()
    }

    func moveSnippet(_ snippet: Snippet, from sourceGroupID: UUID, to targetGroupID: UUID) {
        guard let srcIdx = groups.firstIndex(where: { $0.id == sourceGroupID }),
              let tgtIdx = groups.firstIndex(where: { $0.id == targetGroupID })
        else { return }
        guard db.moveSnippet(id: snippet.id, toGroup: targetGroupID, sortOrder: groups[tgtIdx].snippets.count) else {
            reportDatabaseWriteFailure()
            return
        }
        groups[srcIdx].snippets.removeAll { $0.id == snippet.id }
        groups[tgtIdx].snippets.append(snippet)
        if selectedGroupID == sourceGroupID {
            selectedGroupID = targetGroupID
            selectedSnippetID = snippet.id
        }
        notify()
    }

    func abbreviationExists(_ abbreviation: String, excluding excludedSnippetID: UUID? = nil) -> Bool {
        let normalized = abbreviation.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return false }

        return groups.contains { group in
            group.snippets.contains { snippet in
                snippet.id != excludedSnippetID && snippet.abbreviation == normalized
            }
        }
    }

    func exportJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(SnippetBackup(groups: groups))
    }

    func parseImportJSONData(_ data: Data) throws -> [SnippetGroup] {
        let backup = try JSONDecoder().decode(SnippetBackup.self, from: data)
        return try SnippetBackupValidator.normalizedGroups(from: backup)
    }

    func replaceAllGroups(_ normalizedGroups: [SnippetGroup]) throws {
        try writeAutomaticBackup()
        guard db.replaceAllGroups(normalizedGroups) else {
            throw SnippetImportExportError.databaseWriteFailed
        }
        groups = normalizedGroups
        selectedGroupID = groups.first?.id
        selectedSnippetID = nil
        searchQuery = ""
        notify()
    }

    func importJSONData(_ data: Data) throws {
        try replaceAllGroups(parseImportJSONData(data))
    }

    func backupDirectoryURL() throws -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SnippetImportExportError.backupDirectoryUnavailable
        }

        let backupDir = appSupport
            .appendingPathComponent("TextFlash")
            .appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        return backupDir
    }

    // MARK: - 内部方法

    /// 从数据库重新加载全部数据
    private func reload() {
        groups = db.fetchAllGroups()
        if selectedGroupID == nil {
            selectedGroupID = groups.first?.id
        }
    }

    private func createDefaultGroup() {
        let group = SnippetGroup(name: "通用")
        guard db.insertGroup(id: group.id, name: "通用", sortOrder: 0) else {
            reportDatabaseWriteFailure()
            return
        }
        groups.append(group)
        selectedGroupID = group.id
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: .textFlashSnippetsDidChange, object: self)
    }

    private func reportDatabaseWriteFailure() {
        operationErrorMessage = OperationError.databaseWriteFailed.localizedDescription
    }

    private func writeAutomaticBackup() throws {
        guard !groups.isEmpty else { return }
        let backupDir = try backupDirectoryURL()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "TextFlash-AutoBackup-\(formatter.string(from: Date())).json"
        try exportJSONData().write(to: backupDir.appendingPathComponent(filename), options: .atomic)
        pruneAutomaticBackups(in: backupDir, keeping: 20)
    }

    private func pruneAutomaticBackups(in backupDir: URL, keeping limit: Int) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let backups = urls
            .filter { $0.lastPathComponent.hasPrefix("TextFlash-AutoBackup-") && $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }

        for url in backups.dropFirst(limit) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

struct SnippetBackup: Codable {
    let groups: [SnippetGroup]
}

enum SnippetBackupValidator {
    static func normalizedGroups(from backup: SnippetBackup) throws -> [SnippetGroup] {
        let groups = backup.groups.isEmpty ? [SnippetGroup(name: "通用")] : backup.groups
        try validate(groups)
        return groups
    }

    static func validate(_ groups: [SnippetGroup]) throws {
        var seenAbbreviations: Set<String> = []

        for group in groups {
            if group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw SnippetImportExportError.invalidBackup("存在空分组名称")
            }

            for snippet in group.snippets {
                let abbreviation = snippet.abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
                let expansion = snippet.expandedText.trimmingLeadingWhitespaceAndNewlines()

                if abbreviation.isEmpty {
                    throw SnippetImportExportError.invalidBackup("存在空缩写触发词")
                }
                if expansion.isEmpty {
                    throw SnippetImportExportError.invalidBackup("缩写 \(snippet.abbreviation) 的展开文本为空")
                }
                if seenAbbreviations.contains(abbreviation) {
                    throw SnippetImportExportError.invalidBackup("缩写 \(abbreviation) 重复")
                }
                seenAbbreviations.insert(abbreviation)
            }
        }
    }
}

enum SnippetImportExportError: LocalizedError {
    case databaseWriteFailed
    case invalidBackup(String)
    case backupDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .databaseWriteFailed:
            return "写入数据库失败"
        case .invalidBackup(let message):
            return "备份文件无效：\(message)"
        case .backupDirectoryUnavailable:
            return "无法打开备份目录"
        }
    }
}
