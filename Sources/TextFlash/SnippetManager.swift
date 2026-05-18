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
        db.insertGroup(id: group.id, name: name, sortOrder: sortOrder)
        groups.append(group)
        selectedGroupID = group.id
        notify()
    }

    func renameGroup(_ group: SnippetGroup, to name: String) {
        guard let idx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        db.updateGroupName(id: group.id, name: name)
        groups[idx].name = name
        notify()
    }

    func deleteGroup(_ group: SnippetGroup) {
        db.deleteGroup(id: group.id)
        groups.removeAll { $0.id == group.id }
        if selectedGroupID == group.id {
            selectedGroupID = groups.first?.id
        }
        notify()
    }

    func moveGroup(from source: IndexSet, to destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        let orders = groups.enumerated().map { ($0.element.id, $0.offset) }
        db.updateGroupSortOrders(orders)
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
        db.insertSnippet(
            id: snippet.id,
            groupID: groupID,
            abbreviation: abbreviation,
            expandedText: expandedText,
            description: description,
            sortOrder: sortOrder
        )
        groups[idx].snippets.append(snippet)
        selectedSnippetID = snippet.id
        notify()
    }

    func updateSnippet(_ snippet: Snippet, abbreviation: String, expandedText: String, description: String, inGroup groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }),
              let sIdx = groups[gIdx].snippets.firstIndex(where: { $0.id == snippet.id })
        else { return }
        db.updateSnippet(id: snippet.id, abbreviation: abbreviation, expandedText: expandedText, description: description)
        groups[gIdx].snippets[sIdx].abbreviation = abbreviation
        groups[gIdx].snippets[sIdx].expandedText = expandedText
        groups[gIdx].snippets[sIdx].description = description
        notify()
    }

    func deleteSnippet(_ snippet: Snippet, fromGroup groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        db.deleteSnippet(id: snippet.id)
        groups[gIdx].snippets.removeAll { $0.id == snippet.id }
        if selectedSnippetID == snippet.id {
            selectedSnippetID = nil
        }
        notify()
    }

    func deleteSnippets(_ snippets: Set<Snippet>, fromGroup groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let ids = Set(snippets.map { $0.id })
        db.deleteSnippets(ids: ids)
        groups[gIdx].snippets.removeAll { ids.contains($0.id) }
        if let sel = selectedSnippetID, ids.contains(sel) {
            selectedSnippetID = nil
        }
        notify()
    }

    func moveSnippet(from source: IndexSet, to destination: Int, inGroup groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[gIdx].snippets.move(fromOffsets: source, toOffset: destination)
        let orders = groups[gIdx].snippets.enumerated().map { ($0.element.id, $0.offset) }
        db.updateSnippetSortOrders(orders)
        notify()
    }

    func moveSnippet(_ snippet: Snippet, from sourceGroupID: UUID, to targetGroupID: UUID) {
        guard let srcIdx = groups.firstIndex(where: { $0.id == sourceGroupID }),
              let tgtIdx = groups.firstIndex(where: { $0.id == targetGroupID })
        else { return }
        db.moveSnippet(id: snippet.id, toGroup: targetGroupID, sortOrder: groups[tgtIdx].snippets.count)
        groups[srcIdx].snippets.removeAll { $0.id == snippet.id }
        groups[tgtIdx].snippets.append(snippet)
        if selectedGroupID == sourceGroupID {
            selectedGroupID = targetGroupID
            selectedSnippetID = snippet.id
        }
        notify()
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
        db.insertGroup(id: group.id, name: "通用", sortOrder: 0)
        groups.append(group)
        selectedGroupID = group.id
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: .textFlashSnippetsDidChange, object: self)
    }
}
