import SwiftUI

// MARK: - 片段编辑面板

struct SnippetEditView: View {
    @ObservedObject var manager: SnippetManager
    @ObservedObject private var settings = AppSettings.shared

    @State private var abbreviation: String = ""
    @State private var expandedText: String = ""
    @State private var description: String = ""
    @State private var selectedGroupID: UUID?

    /// 是否为新建模式
    private var isNew: Bool {
        if case .new = manager.editMode { return true }
        return false
    }

    /// 原始片段（编辑模式下）
    private var originalSnippet: Snippet? {
        if case .existing(let s) = manager.editMode { return s }
        return nil
    }

    private var trimmedAbbreviation: String {
        abbreviation.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedExpandedText: String {
        expandedText.trimmingLeadingWhitespaceAndNewlines()
    }

    private var hasAbbreviationConflict: Bool {
        manager.abbreviationExists(trimmedAbbreviation, excluding: originalSnippet?.id)
    }

    var body: some View {
        ZStack {
            EditPalette.window
                .ignoresSafeArea()

            VStack(spacing: 14) {
                editHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        formSection {
                            groupPicker
                            abbreviationField
                        }

                        formSection {
                            variableBar
                            expandedTextField
                        }

                        formSection {
                            descriptionField
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 2)
                }

                editFooter
            }
            .padding(.vertical, 16)
        }
        .frame(minWidth: 620, idealWidth: 660, minHeight: 560, idealHeight: 620)
        .preferredColorScheme(.light)
        .onAppear(perform: populateFields)
    }

    private var editHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: isNew ? "plus" : "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(EditPalette.accent)
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(isNew ? L10n.t("edit.new.title") : L10n.t("edit.existing.title"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(EditPalette.primaryText)
                Text(trimmedAbbreviation.isEmpty ? L10n.t("window.snippets") : trimmedAbbreviation)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(EditPalette.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                manager.editMode = .inactive
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(EditPalette.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(EditPalette.field)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(EditPalette.border))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(EditPalette.glass)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(EditPalette.border))
        .softEditShadow()
        .padding(.horizontal, 16)
    }

    private var editFooter: some View {
        HStack(spacing: 10) {
            Spacer()

            Button(L10n.t("common.cancel")) {
                manager.editMode = .inactive
            }
            .buttonStyle(SecondaryEditButtonStyle())
            .keyboardShortcut(.cancelAction)

            Button(L10n.t("common.save")) {
                save()
            }
            .buttonStyle(PrimaryEditButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(trimmedAbbreviation.isEmpty
                      || trimmedExpandedText.isEmpty
                      || hasAbbreviationConflict)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    private func formSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditPalette.glass)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(EditPalette.border))
        .softEditShadow()
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(EditPalette.mutedText)
            .textCase(.uppercase)
    }

    // MARK: - 分组选择

    private var groupPicker: some View {
        HStack(spacing: 10) {
            fieldLabel(L10n.t("edit.group"))
            Picker("", selection: $selectedGroupID) {
                ForEach(manager.groups) { group in
                    Text(group.name).tag(group.id as UUID?)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - 缩写输入

    private var abbreviationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(L10n.t("edit.abbreviation"))
            TextField(L10n.t("edit.abbreviation.placeholder"), text: $abbreviation)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(EditPalette.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(EditPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(hasAbbreviationConflict ? EditPalette.warning.opacity(0.42) : EditPalette.border))
            if hasAbbreviationConflict {
                Text(L10n.t("edit.abbreviation.conflict"))
                    .font(.caption2)
                    .foregroundColor(EditPalette.warning)
            }
        }
    }

    // MARK: - 变量占位符快捷按钮

    private var variableBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(L10n.t("edit.variables"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    VariableButton(L10n.t("edit.variable.cursor"), raw: "{cursor}", into: $expandedText)
                    VariableButton(L10n.t("edit.variable.date"), raw: "{datetime:}", into: $expandedText)
                    VariableButton(L10n.t("edit.variable.clipboard"), raw: "{clipboard}", into: $expandedText)
                    VariableButton(L10n.t("edit.variable.enter"), raw: "{enter}", into: $expandedText)
                    VariableButton(L10n.t("edit.variable.tab"), raw: "{tab}", into: $expandedText)
                }
            }
        }
    }

    // MARK: - 展开文本

    private var expandedTextField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                fieldLabel(L10n.t("edit.expandedText"))
                Spacer()
                Text(L10n.f("edit.characterCount", expandedText.count))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(EditPalette.mutedText)
                    .monospacedDigit()
            }
            PlainTextEditor(text: $expandedText)
                .frame(minHeight: 180)
                .background(EditPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(EditPalette.border, lineWidth: 1)
                )
        }
    }

    // MARK: - 描述

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(L10n.t("edit.description"))
            TextField(L10n.t("edit.description.placeholder"), text: $description)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(EditPalette.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(EditPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(EditPalette.border))
        }
    }

    // MARK: - 逻辑

    private func populateFields() {
        switch manager.editMode {
        case .new(let gid):
            abbreviation = ""
            expandedText = ""
            description = ""
            selectedGroupID = gid
        case .existing(let snippet):
            abbreviation = snippet.abbreviation
            expandedText = snippet.expandedText
            description = snippet.description
            selectedGroupID = manager.selectedGroupID
        case .inactive:
            break
        }
    }

    private func save() {
        let abbr = trimmedAbbreviation
        // 只裁剪前导空白（空格/换行），保留尾部格式
        let expanded = trimmedExpandedText
        let desc = description.trimmingCharacters(in: .whitespaces)

        guard !abbr.isEmpty,
              !expanded.isEmpty,
              !hasAbbreviationConflict,
              let gid = selectedGroupID
        else { return }

        switch manager.editMode {
        case .new:
            manager.addSnippet(abbreviation: abbr, expandedText: expanded, description: desc, toGroup: gid)
        case .existing(let original):
            // 分组改变时先移动到目标分组
            if let originalGroupID = manager.editingGroupID, gid != originalGroupID {
                manager.moveSnippet(original, from: originalGroupID, to: gid)
            }
            manager.updateSnippet(original, abbreviation: abbr, expandedText: expanded, description: desc, inGroup: gid)
        case .inactive:
            break
        }

        manager.editMode = .inactive
    }
}

// MARK: - 变量插入按钮

private struct VariableButton: View {
    let label: String
    let raw: String
    @Binding var text: String

    init(_ label: String, raw: String, into text: Binding<String>) {
        self.label = label
        self.raw = raw
        self._text = text
    }

    var body: some View {
        Button {
            text.append(raw)
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Text(raw)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(EditPalette.mutedText)
                    .lineLimit(1)
            }
            .foregroundColor(EditPalette.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(EditPalette.field)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(EditPalette.border))
        }
        .buttonStyle(.plain)
        .help(raw)
    }
}

// MARK: - 编辑面板视觉组件

private enum EditPalette {
    static let window = Color(red: 0.965, green: 0.960, blue: 0.985)
    static let glass = Color.white.opacity(0.68)
    static let field = Color.white.opacity(0.74)
    static let border = Color(red: 0.60, green: 0.56, blue: 0.72).opacity(0.20)
    static let accent = Color(red: 0.42, green: 0.38, blue: 0.82)
    static let warning = Color(red: 0.78, green: 0.48, blue: 0.16)
    static let primaryText = Color(red: 0.12, green: 0.115, blue: 0.16)
    static let secondaryText = Color(red: 0.39, green: 0.37, blue: 0.47)
    static let mutedText = Color(red: 0.56, green: 0.53, blue: 0.62)
}

private extension View {
    func softEditShadow() -> some View {
        shadow(color: Color(red: 0.42, green: 0.36, blue: 0.62).opacity(0.08), radius: 18, x: 0, y: 10)
    }
}

private struct PrimaryEditButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(EditPalette.accent.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

private struct SecondaryEditButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(EditPalette.secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(EditPalette.field.opacity(configuration.isPressed ? 0.70 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(EditPalette.border))
    }
}

// MARK: - 禁用智能引号的文本编辑器

/// 封装 NSTextView，禁用自动引号/破折号替换。
/// 在展开文本编辑区域使用，确保 `'` / `"` 保持原样不被转为弯引号。
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.drawsBackground = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
