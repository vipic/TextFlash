import SwiftUI

// MARK: - 主窗口视图

struct SnippetManagerView: View {
    @ObservedObject var manager: SnippetManager
    @State private var groupNameInput: String = ""
    @State private var showNewGroupAlert = false
    @State private var showRenameGroupAlert = false
    @State private var renameTarget: SnippetGroup?

    var body: some View {
        NavigationSplitView {
            // 左侧：分组列表
            groupSidebar
                .frame(minWidth: 140)
                .navigationSplitViewColumnWidth(min: 140, ideal: 180, max: 220)
        } detail: {
            // 右侧：片段列表
            snippetContent
                .frame(minWidth: 400)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 600, minHeight: 400, idealHeight: 500)
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: Binding(
            get: { manager.editMode != .inactive },
            set: { if !$0 { manager.editMode = .inactive } }
        )) {
            SnippetEditView(manager: manager)
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
            Button("取消", role: .cancel) { groupNameInput = "" }
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
    }

    // MARK: - 分组侧栏

    @ViewBuilder
    private var groupSidebar: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("分组")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // 分组列表
            List(selection: $manager.selectedGroupID) {
                ForEach(manager.groups) { group in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 12))
                        Text(group.name)
                            .lineLimit(1)
                        Spacer()
                        Text("\(group.snippets.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("重命名") {
                            renameTarget = group
                            groupNameInput = group.name
                            showRenameGroupAlert = true
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            manager.deleteGroup(group)
                        }
                        .disabled(manager.groups.count <= 1)
                    }
                    .tag(group.id)
                }
                .onMove(perform: manager.moveGroup)
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - 片段内容区

    @ViewBuilder
    private var snippetContent: some View {
        VStack(spacing: 0) {
            if let group = manager.selectedGroup {
                snippetHeader(group: group)
                Divider()
                snippetList(group: group)
            } else {
                emptyState
            }
        }
    }

    private func snippetHeader(group: SnippetGroup) -> some View {
        HStack {
            Text(group.name)
                .font(.headline)
            Text("· \(group.snippets.count) 个片段")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.word.spacing")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            if manager.groups.isEmpty {
                Text("点击 + 按钮创建第一个分组")
                    .foregroundColor(.secondary)
            } else {
                Text("从左侧选择一个分组")
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func snippetList(group: SnippetGroup) -> some View {
        if group.snippets.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "plus.square")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                Text("点击 + 按钮新建片段")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $manager.selectedSnippetID) {
                ForEach(group.snippets) { snippet in
                    snippetRow(snippet, group: group)
                        .contextMenu {
                            Button("编辑") {
                                manager.editMode = .existing(snippet)
                            }
                            Divider()
                            Button("删除", role: .destructive) {
                                manager.deleteSnippet(snippet, fromGroup: group.id)
                            }
                        }
                }
                .onMove { source, dest in
                    manager.moveSnippet(from: source, to: dest, inGroup: group.id)
                }
            }
            .listStyle(.inset)
        }
    }

    private func snippetRow(_ snippet: Snippet, group: SnippetGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // 缩写
            HStack(spacing: 6) {
                Text(snippet.abbreviation)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.accentColor)
                if !snippet.description.isEmpty {
                    Text("—")
                        .foregroundColor(.secondary)
                    Text(snippet.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            // 展开文本预览
            Text(snippet.expandedText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding(.vertical, 2)
        .onTapGesture(count: 2) {
            manager.editMode = .existing(snippet)
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                groupNameInput = ""
                showNewGroupAlert = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("新建分组")
            .accessibilityLabel("新建分组")

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
            .accessibilityLabel("新建片段")

            Button {
                if let sid = manager.selectedSnippetID,
                   let snippet = manager.selectedGroupSnippets.first(where: { $0.id == sid }) {
                    manager.editMode = .existing(snippet)
                }
            } label: {
                Image(systemName: "pencil")
            }
            .help("编辑选中片段")
            .accessibilityLabel("编辑选中片段")
            .disabled(manager.selectedSnippetID == nil)

            Button {
                if let gid = manager.selectedGroupID,
                   let sid = manager.selectedSnippetID {
                    if let snippet = manager.selectedGroupSnippets.first(where: { $0.id == sid }) {
                        manager.deleteSnippet(snippet, fromGroup: gid)
                    }
                }
            } label: {
                Image(systemName: "trash")
            }
            .help("删除选中片段")
            .accessibilityLabel("删除选中片段")
            .disabled(manager.selectedSnippetID == nil)
        }
    }
}
