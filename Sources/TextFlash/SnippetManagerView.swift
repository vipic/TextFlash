import SwiftUI
import AppKit

// MARK: - 主窗口视图

struct SnippetManagerView: View {
    @ObservedObject var manager: SnippetManager
    @ObservedObject private var settings = AppSettings.shared
    @State private var hasAccessibilityPermission = EventController.shared.checkPermission()
    @State private var groupNameInput: String = ""
    @State private var showNewGroupAlert = false
    @State private var showRenameGroupAlert = false
    @State private var renameTarget: SnippetGroup?
    @State private var pendingGroupDeletion: SnippetGroup?
    @State private var pendingSnippetDeletion: PendingSnippetDeletion?
    @State private var pendingImportedGroups: [SnippetGroup]?
    @State private var importExportError: String?

    private struct PendingSnippetDeletion: Identifiable {
        let snippet: Snippet
        let groupID: UUID

        var id: UUID { snippet.id }
    }

    var body: some View {
        ZStack {
            GlassPalette.window
                .ignoresSafeArea()

            VStack(spacing: 14) {
                topGlassBar

                if !hasAccessibilityPermission {
                    permissionBanner
                }

                HStack(spacing: 14) {
                    groupSidebar
                        .frame(width: 196)
                        .glassPanel()

                    snippetColumn
                        .frame(minWidth: 360, idealWidth: 440)
                        .glassPanel()

                    detailPanel
                        .frame(minWidth: 340, idealWidth: 410)
                        .glassPanel()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .padding(.top, 16)
        }
        .frame(minWidth: 900, idealWidth: 1040, minHeight: 560, idealHeight: 640)
        .preferredColorScheme(.light)
        .sheet(isPresented: Binding(
            get: { manager.editMode != .inactive },
            set: { if !$0 { manager.editMode = .inactive } }
        )) {
            SnippetEditView(manager: manager)
                .preferredColorScheme(nil)
        }
        .alert(L10n.t("snippets.group.new.title"), isPresented: $showNewGroupAlert) {
            TextField(L10n.t("snippets.group.name"), text: $groupNameInput)
            Button(L10n.t("common.cancel"), role: .cancel) { groupNameInput = "" }
            Button(L10n.t("common.confirm")) {
                let name = groupNameInput.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { manager.addGroup(name: name) }
                groupNameInput = ""
            }
        } message: {
            Text(L10n.t("snippets.group.new.message"))
        }
        .alert(L10n.t("snippets.group.rename.title"), isPresented: $showRenameGroupAlert) {
            TextField(L10n.t("snippets.group.name"), text: $groupNameInput)
            Button(L10n.t("common.cancel"), role: .cancel) {
                groupNameInput = ""
                renameTarget = nil
            }
            Button(L10n.t("common.confirm")) {
                let name = groupNameInput.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, let target = renameTarget {
                    manager.renameGroup(target, to: name)
                }
                groupNameInput = ""
                renameTarget = nil
            }
        } message: {
            Text(L10n.t("snippets.group.rename.message"))
        }
        .alert(L10n.t("snippets.group.delete.title"), isPresented: Binding(
            get: { pendingGroupDeletion != nil },
            set: { if !$0 { pendingGroupDeletion = nil } }
        )) {
            Button(L10n.t("common.cancel"), role: .cancel) { pendingGroupDeletion = nil }
            Button(L10n.t("common.delete"), role: .destructive) {
                if let group = pendingGroupDeletion {
                    manager.deleteGroup(group)
                }
                pendingGroupDeletion = nil
            }
        } message: {
            Text(L10n.t("snippets.group.delete.message"))
        }
        .alert(L10n.t("snippets.delete.title"), isPresented: Binding(
            get: { pendingSnippetDeletion != nil },
            set: { if !$0 { pendingSnippetDeletion = nil } }
        )) {
            Button(L10n.t("common.cancel"), role: .cancel) { pendingSnippetDeletion = nil }
            Button(L10n.t("common.delete"), role: .destructive) {
                if let pending = pendingSnippetDeletion {
                    manager.deleteSnippet(pending.snippet, fromGroup: pending.groupID)
                }
                pendingSnippetDeletion = nil
            }
        } message: {
            Text(L10n.t("snippets.delete.message"))
        }
        .alert(L10n.t("snippets.importExport.failed"), isPresented: Binding(
            get: { importExportError != nil },
            set: { if !$0 { importExportError = nil } }
        )) {
            Button(L10n.t("common.confirm"), role: .cancel) { importExportError = nil }
        } message: {
            Text(importExportError ?? "")
        }
        .alert(L10n.t("snippets.import.title"), isPresented: Binding(
            get: { pendingImportedGroups != nil },
            set: { if !$0 { pendingImportedGroups = nil } }
        )) {
            Button(L10n.t("common.cancel"), role: .cancel) { pendingImportedGroups = nil }
            Button(L10n.t("snippets.import.confirm"), role: .destructive) {
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
            Text(L10n.f("snippets.import.message", pendingImportedGroups?.count ?? 0, count))
        }
        .alert(L10n.t("snippets.operation.failed"), isPresented: Binding(
            get: { manager.operationErrorMessage != nil },
            set: { if !$0 { manager.operationErrorMessage = nil } }
        )) {
            Button(L10n.t("common.confirm"), role: .cancel) { manager.operationErrorMessage = nil }
        } message: {
            Text(manager.operationErrorMessage ?? "")
        }
    }

    // MARK: - Top Bar

    private var topGlassBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TextFlash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(GlassPalette.primaryText)
                Text(L10n.t("window.snippets"))
                    .font(.system(size: 12))
                    .foregroundColor(GlassPalette.secondaryText)
            }

            Spacer(minLength: 16)

            searchField
                .frame(minWidth: 280, idealWidth: 420, maxWidth: 520)

            HStack(spacing: 6) {
                toolbarIcon("square.and.arrow.down", help: L10n.t("snippets.toolbar.import")) {
                    importSnippets()
                }
                toolbarIcon("square.and.arrow.up", help: L10n.t("snippets.toolbar.export")) {
                    exportSnippets()
                }
                toolbarIcon("plus", help: L10n.t("snippets.toolbar.newSnippet"), prominent: true) {
                    createSnippet()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(GlassPalette.glass)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(GlassPalette.border))
        .softShadow()
        .padding(.horizontal, 16)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(GlassPalette.mutedText)

            TextField(L10n.t("snippets.search.placeholder"), text: $manager.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(GlassPalette.primaryText)

            if !manager.searchQuery.isEmpty {
                Button {
                    manager.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(GlassPalette.mutedText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(GlassPalette.field)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(GlassPalette.border)
        )
    }

    private func toolbarIcon(
        _ symbol: String,
        help: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(prominent ? .white : GlassPalette.secondaryText)
                .frame(width: 32, height: 32)
                .background(prominent ? GlassPalette.accent : GlassPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(prominent ? GlassPalette.accent.opacity(0.65) : GlassPalette.border)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var permissionBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(GlassPalette.warning)

            Text(L10n.t("snippets.permission.banner"))
                .font(.system(size: 12))
                .foregroundColor(GlassPalette.secondaryText)

            Spacer()

            Button {
                requestAccessibilityPermission()
            } label: {
                Text(L10n.t("snippets.permission.open"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(GlassPalette.warning)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(GlassPalette.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(GlassPalette.warning.opacity(0.18)))
        .padding(.horizontal, 16)
    }

    // MARK: - Sidebar

    private var groupSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel(L10n.t("snippets.group.sidebarTitle"))
                Spacer()
                Button {
                    groupNameInput = ""
                    showNewGroupAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(GlassPalette.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(GlassPalette.field)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(GlassPalette.border))
                }
                .buttonStyle(.plain)
                .help(L10n.t("snippets.group.addHelp"))
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(manager.groups) { group in
                        groupRow(group)
                            .contextMenu { groupContextMenu(group) }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func groupRow(_ group: SnippetGroup) -> some View {
        let selected = manager.selectedGroupID == group.id

        return Button {
            manager.selectedGroupID = group.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "folder.fill" : "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(selected ? GlassPalette.accent : GlassPalette.mutedText)
                    .frame(width: 16)

                Text(group.name)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? GlassPalette.primaryText : GlassPalette.secondaryText)
                    .lineLimit(1)

                Spacer()

                CountPill(value: group.snippets.count, selected: selected)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? GlassPalette.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func groupContextMenu(_ group: SnippetGroup) -> some View {
        Button(L10n.t("common.rename")) {
            renameTarget = group
            groupNameInput = group.name
            showRenameGroupAlert = true
        }
        Divider()
        Button(L10n.t("common.delete"), role: .destructive) {
            pendingGroupDeletion = group
        }
        .disabled(manager.groups.count <= 1)
    }

    // MARK: - Snippets

    private var snippetColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let group = manager.selectedGroup {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(GlassPalette.primaryText)
                        Text(L10n.f("snippets.count", manager.filteredSnippets.count))
                            .font(.system(size: 12))
                            .foregroundColor(GlassPalette.secondaryText)
                    }

                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                snippetListArea(group: group)
            } else {
                emptyState
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func snippetListArea(group: SnippetGroup) -> some View {
        let snippets = manager.filteredSnippets
        if snippets.isEmpty {
            emptySnippetState(hasSearch: !manager.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(snippets.enumerated()), id: \.element.id) { index, snippet in
                        let selected = manager.selectedSnippetID == snippet.id
                        let nextSelected = index + 1 < snippets.count && manager.selectedSnippetID == snippets[index + 1].id
                        VStack(spacing: 0) {
                            snippetRow(snippet, group: group)
                                .contextMenu { snippetContextMenu(snippet, group: group) }
                            if !selected, !nextSelected, index != snippets.indices.last {
                                Divider()
                                    .overlay(GlassPalette.border)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
                .background(GlassPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(GlassPalette.border))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private func snippetRow(_ snippet: Snippet, group: SnippetGroup) -> some View {
        let selected = manager.selectedSnippetID == snippet.id

        return Button {
            manager.selectedSnippetID = snippet.id
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(snippet.abbreviation)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(GlassPalette.accent)

                    if !snippet.description.isEmpty {
                        Text(snippet.description)
                            .font(.system(size: 12))
                            .foregroundColor(selected ? GlassPalette.primaryText.opacity(0.78) : GlassPalette.secondaryText)
                            .lineLimit(1)
                    }

                }

                SyntaxHighlightedText(text: snippet.expandedText, singleLine: true)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? GlassPalette.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func snippetContextMenu(_ snippet: Snippet, group: SnippetGroup) -> some View {
        Button(L10n.t("common.edit")) {
            manager.editMode = .existing(snippet)
        }
        Divider()
        Button(L10n.t("common.delete"), role: .destructive) {
            pendingSnippetDeletion = PendingSnippetDeletion(snippet: snippet, groupID: group.id)
        }
    }

    // MARK: - Detail

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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel(L10n.t("snippets.detail.title"))
                    Text(snippet.abbreviation)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundColor(GlassPalette.primaryText)
                }

                Spacer()

                Button {
                    manager.editMode = .existing(snippet)
                } label: {
                    Label(L10n.t("common.edit"), systemImage: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(GlassPalette.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(GlassPalette.field)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(GlassPalette.border))
                }
                .buttonStyle(.plain)
                .help(L10n.t("snippets.detail.editHelp"))
            }
            .padding(18)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !snippet.description.isEmpty {
                        DetailField(label: L10n.t("edit.description"), value: snippet.description)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        sectionLabel(L10n.t("snippets.expandedText"))

                        SyntaxHighlightedText(text: snippet.expandedText)
                            .font(.system(size: 13))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(GlassPalette.field)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(GlassPalette.border))
                    }

                    HStack {
                        MetricTile(title: L10n.t("snippets.detail.trigger"), value: snippet.abbreviation)
                    }
                }
                .padding(18)
            }
        }
        .padding(.top, 2)
    }

    private var detailEmpty: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.word.spacing")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(GlassPalette.mutedText.opacity(0.55))
            Text(L10n.t("snippets.detail.empty"))
                .font(.system(size: 13))
                .foregroundColor(GlassPalette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 30))
                .foregroundColor(GlassPalette.mutedText.opacity(0.55))
            Text(manager.groups.isEmpty ? L10n.t("snippets.empty.createGroup") : L10n.t("snippets.empty.selectGroup"))
                .font(.system(size: 13))
                .foregroundColor(GlassPalette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptySnippetState(hasSearch: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: hasSearch ? "magnifyingglass" : "text.word.spacing")
                .font(.system(size: 28))
                .foregroundColor(GlassPalette.mutedText.opacity(0.55))
            Text(hasSearch ? L10n.t("snippets.empty.noMatches") : L10n.t("snippets.empty.createSnippet"))
                .font(.system(size: 13))
                .foregroundColor(GlassPalette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(GlassPalette.mutedText)
            .textCase(.uppercase)
    }

    private func createSnippet() {
        if let gid = manager.selectedGroupID {
            manager.editMode = .new(inGroup: gid)
        } else if let first = manager.groups.first {
            manager.editMode = .new(inGroup: first.id)
        }
    }

    private func requestAccessibilityPermission() {
        let granted = EventController.shared.requestPermission()
        if !granted {
            EventController.openAccessibilitySettings()
        }
        hasAccessibilityPermission = EventController.shared.checkPermission()
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

// MARK: - Soft Glass Components

private enum GlassPalette {
    static let window = Color(red: 0.965, green: 0.960, blue: 0.985)
    static let glass = Color.white.opacity(0.68)
    static let field = Color.white.opacity(0.74)
    static let surface = Color.white.opacity(0.58)
    static let border = Color(red: 0.60, green: 0.56, blue: 0.72).opacity(0.20)
    static let accent = Color(red: 0.42, green: 0.38, blue: 0.82)
    static let accentSoft = Color(red: 0.58, green: 0.52, blue: 0.92).opacity(0.16)
    static let warning = Color(red: 0.78, green: 0.48, blue: 0.16)
    static let primaryText = Color(red: 0.12, green: 0.115, blue: 0.16)
    static let secondaryText = Color(red: 0.39, green: 0.37, blue: 0.47)
    static let mutedText = Color(red: 0.56, green: 0.53, blue: 0.62)
}

private extension View {
    func glassPanel() -> some View {
        self
            .background(GlassPalette.glass)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(GlassPalette.border))
            .softShadow()
    }

    func softShadow() -> some View {
        shadow(color: Color(red: 0.42, green: 0.36, blue: 0.62).opacity(0.08), radius: 18, x: 0, y: 10)
    }
}

private struct CountPill: View {
    let value: Int
    let selected: Bool

    var body: some View {
        Text("\(value)")
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(selected ? GlassPalette.primaryText : GlassPalette.mutedText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(selected ? GlassPalette.accent.opacity(0.10) : GlassPalette.field)
            .clipShape(Capsule())
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.18)))
    }
}

private struct DetailField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(GlassPalette.mutedText)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(GlassPalette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(GlassPalette.mutedText)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(GlassPalette.primaryText)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassPalette.field)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(GlassPalette.border))
    }
}

// MARK: - Preview

#if !DISABLE_PREVIEWS
#Preview {
    SnippetManagerView(manager: SnippetManager())
}
#endif
