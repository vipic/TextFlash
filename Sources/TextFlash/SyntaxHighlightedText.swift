import SwiftUI

// MARK: - 变量语法高亮组件

/// 解析包含 `{clipboard}` `{enter}` `{cursor}` `{datetime:...}` 占位符的文本，
/// 将其渲染为带颜色的胶囊标签 + 普通文本的混合视图。
struct SyntaxHighlightedText: View {
    let text: String
    /// 单行预览模式——截断到一行，变量紧凑显示
    var singleLine: Bool = false

    var body: some View {
        if singleLine {
            AnyLayout(HStackLayout(alignment: .center, spacing: 2)) {
                ForEach(segments) { segment in
                    segmentView(segment, compact: true)
                }
            }
            .lineLimit(1)
        } else {
            FlowLayout(spacing: 4) {
                ForEach(segments) { segment in
                    segmentView(segment, compact: false)
                }
            }
        }
    }

    // MARK: - Segment Model

    private struct Segment: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind: Equatable {
            case plain      // 普通文本
            case clipboard  // {clipboard} — 绿色
            case enter      // {enter} — 橙色
            case tab        // {tab} — 紫色
            case cursor     // {cursor} — 灰色
            case datetime   // {datetime:...} — 蓝色
        }
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "{", let close = findClosing(from: text.index(after: index)) {
                let variable = String(text[text.index(after: index)..<close])
                let kind = classify(variable)
                result.append(Segment(text: variableTag(variable, kind: kind), kind: kind))
                index = text.index(after: close)
            } else {
                // 收集连续的普通字符
                let start = index
                while index < text.endIndex, text[index] != "{" {
                    index = text.index(after: index)
                }
                let plain = String(text[start..<index])
                if !plain.isEmpty {
                    result.append(Segment(text: plain, kind: .plain))
                }
            }
        }
        return result
    }

    private func findClosing(from start: String.Index) -> String.Index? {
        var depth = 1
        var index = start
        while index < text.endIndex {
            if text[index] == "{" { depth += 1 }
            else if text[index] == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func classify(_ variable: String) -> Segment.Kind {
        let trimmed = variable.trimmingCharacters(in: .whitespaces)
        if trimmed == "clipboard" { return .clipboard }
        if trimmed == "enter" { return .enter }
        if trimmed == "tab" { return .tab }
        if trimmed == "cursor" { return .cursor }
        if trimmed.hasPrefix("datetime") { return .datetime }
        return .plain
    }

    /// 将变量转为中文标签
    private func variableTag(_ variable: String, kind: Segment.Kind) -> String {
        switch kind {
        case .clipboard: return "剪贴板"
        case .enter: return "↵ 换行"
        case .tab: return "⇥ Tab"
        case .cursor: return "▎光标"
        case .datetime: return "日期时间"
        case .plain: return "{\(variable)}"
        }
    }

    // MARK: - View Builders

    @ViewBuilder
    private func segmentView(_ segment: Segment, compact: Bool) -> some View {
        switch segment.kind {
        case .plain:
            Text(segment.text)
                .foregroundColor(.primary)

        case .clipboard:
            pillTag(segment.text, bg: Color.green.opacity(0.18), fg: .green, compact: compact)

        case .enter:
            pillTag(segment.text, bg: Color.orange.opacity(0.15), fg: .orange, compact: compact)

        case .tab:
            pillTag(segment.text, bg: Color.purple.opacity(0.15), fg: .purple, compact: compact)

        case .cursor:
            pillTag(segment.text, bg: Color.white.opacity(0.10), fg: .secondary, compact: compact)

        case .datetime:
            pillTag(segment.text, bg: Color.blue.opacity(0.15), fg: .blue, compact: compact)
        }
    }

    private func pillTag(_ label: String, bg: Color, fg: Color, compact: Bool) -> some View {
        Text(label)
            .font(.system(size: compact ? 10 : 12, weight: .semibold, design: .monospaced))
            .foregroundColor(fg)
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, 1)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 3 : 4))
    }
}

// MARK: - 简易 FlowLayout（用于多行展开文本中的变量标签）

/// 水平自动换行的流式布局
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.last?.maxY ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let size = item.sizeThatFits(.unspecified)
                item.place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { let items: [LayoutSubviews.Element]; let width: CGFloat; let height: CGFloat; let maxY: CGFloat }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var currentItems: [LayoutSubviews.Element] = []
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let itemWidth = currentItems.isEmpty ? size.width : size.width + spacing
            if currentWidth + itemWidth > maxWidth, !currentItems.isEmpty {
                rows.append(Row(items: currentItems, width: currentWidth, height: currentItems.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0, maxY: 0))
                currentItems = []
                currentWidth = 0
            }
            currentWidth += currentItems.isEmpty ? size.width : size.width + spacing
            currentItems.append(subview)
        }
        if !currentItems.isEmpty {
            rows.append(Row(items: currentItems, width: currentWidth, height: currentItems.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0, maxY: 0))
        }
        // Calculate maxY
        var y: CGFloat = 0
        for i in rows.indices {
            let height = rows[i].height
            rows[i] = Row(items: rows[i].items, width: rows[i].width, height: height, maxY: y + height)
            y += height + spacing
        }
        return rows
    }
}

// MARK: - Preview

#if !DISABLE_PREVIEWS
#Preview {
    VStack(alignment: .leading, spacing: 20) {
        Text("单行预览:").font(.caption).foregroundColor(.secondary)
        SyntaxHighlightedText(text: "git diff {clipboard} {enter}", singleLine: true)

        Divider()

        Text("完整展开:").font(.caption).foregroundColor(.secondary)
        SyntaxHighlightedText(text: "git diff {clipboard}\n{enter}")
            .frame(width: 300)
    }
    .padding()
    .preferredColorScheme(.dark)
}
#endif
