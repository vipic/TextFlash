import SwiftUI
import AppKit

// MARK: - 主窗口视图（暗色液态玻璃主题）

struct SnippetManagerView: View {
    @ObservedObject var manager: SnippetManager
    @State private var groupNameInput: String = ""
    @State private var showNewGroupAlert = false
    @State private var showRenameGroupAlert = false
    @State private var renameTarget: SnippetGroup?
    @State private var hoverAddGroup = false
    @State private var pendingGroupDeletion: SnippetGroup?
    @State private var pendingSnippetDeletion: PendingSnippetDeletion?
    @State private var pendingImportedGroups: [SnippetGroup]?
    @State private var importExportError: String?

    // MARK: - 配色常量

    private let borderSubtle = Color.primary.opacity(0.08)

    private struct PendingSnippetDeletion: Identifiable {
        let snippet: Snippet
        let groupID: UUID

        var id: UUID { snippet.id }
    }

    var body: some View {
        NavigationSplitView {
            groupSidebar
                .frame(minWidth: 140)
                .navigationSplitViewColumnWidth(min: 140, ideal: 180, max: 220)
        } content: {
            snippetContent
                .frame(minWidth: 300)
        } detail: {
            detailPanel
                .frame(minWidth: 280)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 400)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 480, idealHeight: 560)
        .toolbar { toolbarContent }
        .preferredColorScheme(nil)  // 跟随系统外观
        .sheet(isPresented: Binding(
            get: { manager.editMode != .inactive },
            set: { if !$0 { manager.editMode = .inactive } }
        )) {
            SnippetEditView(manager: manager)
                .preferredColorScheme(nil)  // 跟随系统外观
        }
        .alert("新建分组", isPresented: $showNewGroupAlert) {
            TextField("分组名称", text: $groupNameInput)
            Button("取消", role: .cancel) { groupNameInput = "" }
            Button("确定") {
                let name = groupNameInput.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { manager.addGroup(name: name) }
                groupNameInput = ""
            }
        } message: {
            Text("输入新分组的名称")
        }
        .alert("重命名分组", isPresented: $showRenameGroupAlert) {
            TextField("分组名称", text: $groupNameInput)
            Button("取消", role: .cancel) { groupNameInput = ""; renameTarget = nil }
            Button("确定") {
                let name = groupNameInput.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, let target = renameTarget {
                    manager.renameGroup(target, to: name)
                }
                groupNameInput = ""
                renameTarget = nil
            }
        } message: {
            Text("输入新的分组名称")
        }
        .alert("删除分组？", isPresented: Binding(
            get: { pendingGroupDeletion != nil },
            set: { if !$0 { pendingGroupDeletion = nil } }
        )) {
            Button("取消", role: .cancel) { pendingGroupDeletion = nil }
            Button("删除", role: .destructive) {
                if let group = pendingGroupDeletion {
                    manager.deleteGroup(group)
                }
                pendingGroupDeletion = nil
            }
        } message: {
            Text("分组内的所有片段都会被删除，此操作无法撤销。")
        }
        .alert("删除片段？", isPresented: Binding(
            get: { pendingSnippetDeletion != nil },
            set: { if !$0 { pendingSnippetDeletion = nil } }
        )) {
            Button("取消", role: .cancel) { pendingSnippetDeletion = nil }
            Button("删除", role: .destructive) {
                if let pending = pendingSnippetDeletion {
                    manager.deleteSnippet(pending.snippet, fromGroup: pending.groupID)
                }
                pendingSnippetDeletion = nil
            }
        } message: {
            Text("这个片段会被永久删除。")
        }
        .alert("导入导出失败", isPresented: Binding(
            get: { importExportError != nil },
            set: { if !$0 { importExportError = nil } }
        )) {
            Button("确定", role: .cancel) { importExportError = nil }
        } message: {
            Text(importExportError ?? "")
        }
        .alert("导入片段？", isPresented: Binding(
            get: { pendingImportedGroups != nil },
            set: { if !$0 { pendingImportedGroups = nil } }
        )) {
            Button("取消", role: .cancel) { pendingImportedGroups = nil }
            Button("导入并覆盖", role: .destructive) {
                guard let groups = pendingImportedGroups else { return }
                do {
                    try manager.replaceAllGroups(groups)
                } catch {
                    importExportError = error.localizedDescription
                }
                pendingImportedGroups = nil
            }
        } message: {
            let count = pendingImportedGroups?.reduce(0) { $0 + $1.snippets.count } ?? 0
            Text("这会替换当前所有分组和片段。将导入 \(pendingImportedGroups?.count ?? 0) 个分组、\(count) 个片段。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { manager.operationErrorMessage != nil },
            set: { if !$0 { manager.operationErrorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { manager.operationErrorMessage = nil }
        } message: {
            Text(manager.operationErrorMessage ?? "")
        }
    }

    // MARK: - 分组侧栏

    @ViewBuilder
    private var groupSidebar: some View {
        VStack(spacing: 0) {
            // 标题栏安全区（给红绿灯留空间）
            Color.clear.frame(height: 24)

            // 标题行
            HStack {
                Text("分组")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Spacer()
                Button {
                    groupNameInput = ""
                    showNewGroupAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(hoverAddGroup ? 0.14 : 0.07))
                )
                .onHover { hoverAddGroup = $0 }
                .help("新建分组")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            Divider().overlay(borderSubtle)
                .padding(.bottom, 4)

            // 分组列表
            List(selection: $manager.selectedGroupID) {
                ForEach(manager.groups) { group in
                    groupRow(group)
                        .contextMenu { groupContextMenu(group) }
                        .tag(group.id)
                }
                .onMove(perform: manager.moveGroup)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .padding(.leading, -8)
        }
    }

    private func groupRow(_ group: SnippetGroup) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundColor(.blue.opacity(0.7))

            Text(group.name)
                .font(.system(size: 13, weight: .regular))
                .lineLimit(1)

            Spacer()

            Text("\(group.snippets.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func groupContextMenu(_ group: SnippetGroup) -> some View {
        Button("重命名") {
            renameTarget = group
            groupNameInput = group.name
            showRenameGroupAlert = true
        }
        Divider()
        Button("删除", role: .destructive) {
            pendingGroupDeletion = group
        }
        .disabled(manager.groups.count <= 1)
    }

    // MARK: - 片段内容区

    @ViewBuilder
    private var snippetContent: some View {
        VStack(spacing: 0) {
            // 搜索栏
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().overlay(borderSubtle)

            if let group = manager.selectedGroup {
                snippetHeader(group: group)
                Divider().overlay(borderSubtle)
                snippetListArea(group: group)
            } else {
                emptyState
            }
        }
    }

    // MARK: 搜索栏

    private var searchBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.leading, 10)

            TextField("搜索片段…", text: $manager.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.vertical, 7)
                .padding(.horizontal, 6)
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderSubtle))
    }

    // MARK: 片段列表

    private func snippetHeader(group: SnippetGroup) -> some View {
        HStack(spacing: 6) {
            Text(group.name)
                .font(.system(size: 13, weight: .semibold))
            Text("·")
                .foregroundColor(.secondary)
            let count = manager.filteredSnippets.count
            Text("\(count) 个片段")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func snippetListArea(group: SnippetGroup) -> some View {
        let snippets = manager.filteredSnippets
        if snippets.isEmpty {
            emptySnippetState(hasSearch: !manager.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
        } else {
            List(selection: $manager.selectedSnippetID) {
                ForEach(snippets) { snippet in
                    snippetRow(snippet, group: group)
                        .tag(snippet.id)
                        .contextMenu { snippetContextMenu(snippet, group: group) }
                }
                .onMove { source, dest in
                    manager.moveSnippet(from: source, to: dest, inGroup: group.id)
                }
                .moveDisabled(!manager.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .listStyle(.inset)
        }
    }

    private func snippetRow(_ snippet: Snippet, group: SnippetGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // 缩写（等宽字体 + 强调色）
            HStack(spacing: 6) {
                Text(snippet.abbreviation)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.blue)

                if !snippet.description.isEmpty {
                    Text("—")
                        .foregroundColor(.secondary)
                    Text(snippet.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // 展开文本预览（语法高亮）
            SyntaxHighlightedText(text: snippet.expandedText, singleLine: true)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func snippetContextMenu(_ snippet: Snippet, group: SnippetGroup) -> some View {
        Button("编辑") {
            manager.editMode = .existing(snippet)
        }
        Divider()
        Button("删除", role: .destructive) {
            pendingSnippetDeletion = PendingSnippetDeletion(snippet: snippet, groupID: group.id)
        }
    }

    // MARK: - 详情面板

    @ViewBuilder
    private var detailPanel: some View {
        if let group = manager.selectedGroup,
           let sid = manager.selectedSnippetID,
           let snippet = group.snippets.first(where: { $0.id == sid }) {
            snippetDetail(snippet)
        } else {
            detailEmpty
        }
    }

    private func snippetDetail(_ snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("片段详情")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Spacer()
                detailActionButton(symbol: "pencil", help: "编辑 (⌘E)") {
                    manager.editMode = .existing(snippet)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().overlay(borderSubtle)

            // 详情体
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 缩写标签
                    Text(snippet.abbreviation)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    // 描述
                    if !snippet.description.isEmpty {
                        Text(snippet.description)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    // 展开文本
                    VStack(alignment: .leading, spacing: 8) {
                        Text("展开文本")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.6)

                        SyntaxHighlightedText(text: snippet.expandedText)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderSubtle))
                    }

                    // 变量图例
                    variableLegend
                }
                .padding(16)
            }
        }
    }

    /// 变量颜色图例
    private var variableLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("变量说明")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            HStack(spacing: 12) {
                legendItem(color: .green, label: "{clipboard}")
                legendItem(color: .orange, label: "{enter}")
                legendItem(color: .purple, label: "{tab}")
                legendItem(color: .secondary, label: "{cursor}")
                legendItem(color: .blue, label: "{datetime:…}")
            }
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private var detailEmpty: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.word.spacing")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.3))
            Text("选择片段查看详情")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailActionButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .frame(width: 24, height: 24)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .help(help)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.word.spacing")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.3))
            if manager.groups.isEmpty {
                Text("点击 + 按钮创建第一个分组")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                Text("从左侧选择一个分组")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptySnippetState(hasSearch: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: hasSearch ? "magnifyingglass" : "text.word.spacing")
                .font(.system(size: 26))
                .foregroundColor(.secondary.opacity(0.3))
            if hasSearch {
                Text("没有匹配的片段")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                Text("点击右上角 + 新建片段")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                importSnippets()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help("导入片段")

            Button {
                exportSnippets()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("导出片段")

            Button {
                if let gid = manager.selectedGroupID {
                    manager.editMode = .new(inGroup: gid)
                } else if let first = manager.groups.first {
                    manager.editMode = .new(inGroup: first.id)
                }
            } label: {
                Image(systemName: "plus")
            }
            .help("新建片段")
        }
    }

    private func exportSnippets() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "TextFlash-Snippets.json"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try manager.exportJSONData().write(to: url, options: .atomic)
        } catch {
            importExportError = error.localizedDescription
        }
    }

    private func importSnippets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            pendingImportedGroups = try manager.parseImportJSONData(data)
        } catch {
            importExportError = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    SnippetManagerView(manager: SnippetManager())
}
