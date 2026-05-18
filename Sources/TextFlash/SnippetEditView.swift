import SwiftUI

// MARK: - 片段编辑面板

struct SnippetEditView: View {
    @ObservedObject var manager: SnippetManager

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

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(isNew ? "新建片段" : "编辑片段")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("取消") {
                    manager.editMode = .inactive
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            // 表单内容
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    groupPicker
                    abbreviationField
                    variableBar
                    expandedTextField
                    descriptionField
                }
                .padding()
            }

            Divider()

            // 底部按钮
            HStack {
                Spacer()
                Button("取消") {
                    manager.editMode = .inactive
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    save()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(abbreviation.trimmingCharacters(in: .whitespaces).isEmpty
                          || expandedText.trimmingLeadingWhitespaceAndNewlines().isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear(perform: populateFields)
    }

    // MARK: - 分组选择

    private var groupPicker: some View {
        HStack(spacing: 8) {
            Text("所属分组").font(.caption).foregroundColor(.secondary)
            Picker("", selection: $selectedGroupID) {
                ForEach(manager.groups) { group in
                    Text(group.name).tag(group.id as UUID?)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .disabled(!isNew)
    }

    // MARK: - 缩写输入

    private var abbreviationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("缩写触发词").font(.caption).foregroundColor(.secondary)
            TextField("例如 addr, sig", text: $abbreviation)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }

    // MARK: - 变量占位符快捷按钮

    private var variableBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("插入变量占位符").font(.caption).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    VariableButton("光标", raw: "{cursor}", into: $expandedText)
                    VariableButton("日期", raw: "{datetime:}", into: $expandedText)
                    VariableButton("剪贴板", raw: "{clipboard}", into: $expandedText)
                    VariableButton("回车", raw: "{enter}", into: $expandedText)
                    VariableButton("Tab",  raw: "{tab}", into: $expandedText)
                    VariableButton("←",    raw: "{left}", into: $expandedText)
                    VariableButton("→",    raw: "{right}", into: $expandedText)
                    VariableButton("↑",    raw: "{up}", into: $expandedText)
                    VariableButton("↓",    raw: "{down}", into: $expandedText)
                    VariableButton("粘贴", raw: "{paste}", into: $expandedText)
                }
            }
        }
    }

    // MARK: - 展开文本

    private var expandedTextField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("展开文本").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("\(expandedText.count) 字符")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            TextEditor(text: $expandedText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
    }

    // MARK: - 描述

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("描述").font(.caption).foregroundColor(.secondary)
            TextField("可选：备注/说明", text: $description)
                .textFieldStyle(.roundedBorder)
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
        let abbr = abbreviation.trimmingCharacters(in: .whitespaces)
        // 只裁剪前导空白（空格/换行），保留尾部格式
        let expanded = expandedText.trimmingLeadingWhitespaceAndNewlines()
        let desc = description.trimmingCharacters(in: .whitespaces)

        guard !abbr.isEmpty, !expanded.isEmpty, let gid = selectedGroupID else { return }

        switch manager.editMode {
        case .new:
            manager.addSnippet(abbreviation: abbr, expandedText: expanded, description: desc, toGroup: gid)
        case .existing(let original):
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
            Text(label)
                .font(.system(.caption))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .help(raw)
    }
}
