import Foundation
import Combine

// MARK: - 通知名称

extension Notification.Name {
    /// 片段数据变更时广播，后端引擎监听此通知以重载匹配表
    static let textFlashSnippetsDidChange = Notification.Name("TextFlashSnippetsDidChange")
}

// MARK: - SnippetManager

/// 片段管理器的 ViewModel — 负责分组/片段的 CRUD、持久化，以及通知后端引擎
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

    private let storeURL: URL

    init(dataDirectory: URL? = nil) {
        let dir: URL
        if let dataDirectory {
            dir = dataDirectory
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            dir = home.appendingPathComponent("Documents/Luigi/TextFlash/data")
        }
        self.storeURL = dir.appendingPathComponent("snippets.json")
        load()
        if groups.isEmpty {
            createDefaultGroup()
        }
    }

    // MARK: - 分组操作

    func addGroup(name: String) {
        let group = SnippetGroup(name: name)
        groups.append(group)
        selectedGroupID = group.id
        saveAndNotify()
    }

    func renameGroup(_ group: SnippetGroup, to name: String) {
        guard let idx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[idx].name = name
        saveAndNotify()
    }

    func deleteGroup(_ group: SnippetGroup) {
        groups.removeAll { $0.id == group.id }
        if selectedGroupID == group.id {
            selectedGroupID = groups.first?.id
        }
        saveAndNotify()
    }

    func moveGroup(from source: IndexSet, to destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        saveAndNotify()
    }

    // MARK: - 片段操作

    func addSnippet(abbreviation: String, expandedText: String, description: String, toGroup groupID: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let snippet = Snippet(
            abbreviation: abbreviation,
            expandedText: expandedText,
            description: description
        )
        groups[idx].snippets.append(snippet)
        selectedSnippetID = snippet.id
        saveAndNotify()
    }

    func updateSnippet(_ snippet: Snippet, abbreviation: String, expandedText: String, description: String, inGroup groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }),
              let sIdx = groups[gIdx].snippets.firstIndex(where: { $0.id == snippet.id })
        else { return }
        groups[gIdx].snippets[sIdx].abbreviation = abbreviation
        groups[gIdx].snippets[sIdx].expandedText = expandedText
        groups[gIdx].snippets[sIdx].description = description
        saveAndNotify()
    }

    func deleteSnippet(_ snippet: Snippet, fromGroup groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[gIdx].snippets.removeAll { $0.id == snippet.id }
        if selectedSnippetID == snippet.id {
            selectedSnippetID = nil
        }
        saveAndNotify()
    }

    func deleteSnippets(_ snippets: Set<Snippet>, fromGroup groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let ids = Set(snippets.map { $0.id })
        groups[gIdx].snippets.removeAll { ids.contains($0.id) }
        if let sel = selectedSnippetID, ids.contains(sel) {
            selectedSnippetID = nil
        }
        saveAndNotify()
    }

    func moveSnippet(from source: IndexSet, to destination: Int, inGroup groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[gIdx].snippets.move(fromOffsets: source, toOffset: destination)
        saveAndNotify()
    }

    func moveSnippet(_ snippet: Snippet, from sourceGroupID: UUID, to targetGroupID: UUID) {
        guard let srcIdx = groups.firstIndex(where: { $0.id == sourceGroupID }),
              let tgtIdx = groups.firstIndex(where: { $0.id == targetGroupID })
        else { return }
        groups[srcIdx].snippets.removeAll { $0.id == snippet.id }
        groups[tgtIdx].snippets.append(snippet)
        if selectedGroupID == sourceGroupID {
            selectedGroupID = targetGroupID
            selectedSnippetID = snippet.id
        }
        saveAndNotify()
    }

    // MARK: - 内部方法

    private func createDefaultGroup() {
        let group = SnippetGroup(name: "通用")
        groups.append(group)
        selectedGroupID = group.id
        saveAndNotify()
    }

    private func saveAndNotify() {
        if save() {
            NotificationCenter.default.post(name: .textFlashSnippetsDidChange, object: self)
        }
    }

    private func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return }
        do {
            let data = try Data(contentsOf: storeURL)
            let store = try JSONDecoder().decode(SnippetStore.self, from: data)
            groups = store.groups
            if selectedGroupID == nil {
                selectedGroupID = groups.first?.id
            }
        } catch {
            print("[SnippetManager] 加载失败: \(error.localizedDescription)")
        }
    }

    private func save() -> Bool {
        let fm = FileManager.default
        let dir = storeURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let store = SnippetStore(groups: groups)
            let data = try JSONEncoder().encode(store)
            try data.write(to: storeURL, options: .atomic)
            return true
        } catch {
            print("[SnippetManager] 保存失败: \(error.localizedDescription)")
            return false
        }
    }
}
