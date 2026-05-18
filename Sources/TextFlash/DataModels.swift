import Foundation

/// 文本展开片段
struct Snippet: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var abbreviation: String = ""      // 缩写触发词
    var expandedText: String = ""      // 展开文本（含变量占位符）
    var description: String = ""       // 描述/备注
}

/// 片段分组
struct SnippetGroup: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var snippets: [Snippet] = []
}

// MARK: - String 扩展

extension String {
    /// 只裁剪前导空白和换行符，保留尾部格式
    func trimmingLeadingWhitespaceAndNewlines() -> String {
        guard let idx = firstIndex(where: { !$0.isWhitespace && !$0.isNewline }) else {
            return ""
        }
        return String(self[idx...])
    }
}
