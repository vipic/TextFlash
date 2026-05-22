import Foundation
import AppKit

/// 变量处理器 — 解析文本中的占位符变量，替换为实际值。
///
/// 支持的变量：
/// - `{cursor}` — 标记光标最终位置（替换为空字符串，记录偏移量）
/// - `{datetime:format}` — 当前日期时间，format 为 DateFormatter 模式（如 `yyyy-MM-dd HH:mm`）
/// - `{clipboard}` — 当前系统剪贴板纯文本内容
/// - `{enter}` — 替换为换行符 `\n`
/// - `{tab}` — 替换为制表符 `\t`
///
/// 转义规则：
/// - `\{` → 输出字面量 `{`
/// - `\\` → 输出字面量 `\`
/// - 未知/无法闭合的占位符保持原文不做替换
public struct VariableProcessor {
    private let clipboardProvider: () -> String?
    private let dateProvider: () -> Date

    /// - Parameters:
    ///   - clipboardProvider: 剪贴板读取闭包，默认读取 `NSPasteboard.general`
    ///   - dateProvider: 日期获取闭包，默认为当前时间 `Date()`
    public init(
        clipboardProvider: @escaping () -> String? = {
            NSPasteboard.general.string(forType: .string)
        },
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.clipboardProvider = clipboardProvider
        self.dateProvider = dateProvider
    }

    /// 处理文本中的变量占位符。
    /// - Parameter text: 原始模板文本
    /// - Returns: `processed` 为替换后的纯文本，`cursorOffset` 为光标应在的字符位置（-1 表示不移动）
    public func process(text: String) -> (processed: String, cursorOffset: Int) {
        var result = ""
        var cursorOffset = -1
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]

            // 转义处理：反斜杠
            if char == "\\" {
                let nextIndex = text.index(after: index)
                if nextIndex < text.endIndex {
                    let next = text[nextIndex]
                    switch next {
                    case "{":
                        // \{ → 字面量 {
                        result.append("{")
                        index = text.index(after: nextIndex)
                        continue
                    case "}":
                        // \} → 字面量 }
                        result.append("}")
                        index = text.index(after: nextIndex)
                        continue
                    case "\\":
                        // \\ → 字面量 \
                        result.append("\\")
                        index = text.index(after: nextIndex)
                        continue
                    default:
                        // 其他转义保持原样（如 \n 这种不需要我们处理）
                        result.append(char)
                        index = nextIndex
                        continue
                    }
                }
                // 反斜杠在字符串末尾，原样保留
                result.append(char)
                index = text.index(after: index)
                continue
            }

            // 变量占位符：{...}
            if char == "{" {
                if let closeIndex = findClosingBrace(in: text, from: text.index(after: index)) {
                    let content = String(text[text.index(after: index)..<closeIndex])
                    let positionBefore = result.count
                    let (replacement, offset) = resolveVariable(content, cursorPosition: positionBefore)
                    result.append(replacement)
                    if offset >= 0 && cursorOffset == -1 {
                        cursorOffset = offset
                    }
                    index = text.index(after: closeIndex)
                    continue
                }
                // 无法闭合的 {，原样保留
            }

            result.append(char)
            index = text.index(after: index)
        }

        return (result, cursorOffset)
    }

    // MARK: - Private

    /// 从 start 开始查找匹配的 `}`，用深度计数处理嵌套花括号
    private func findClosingBrace(in text: String, from start: String.Index) -> String.Index? {
        var depth = 1
        var index = start
        while index < text.endIndex {
            let c = text[index]
            if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func resolveVariable(_ content: String, cursorPosition: Int) -> (replacement: String, offset: Int) {
        let trimmed = content.trimmingCharacters(in: .whitespaces)

        if trimmed == "cursor" {
            return ("", cursorPosition)
        }

        if trimmed == "enter" {
            return ("\n", -1)
        }

        if trimmed == "tab" {
            return ("\t", -1)
        }

        if trimmed == "clipboard" {
            let clip = clipboardProvider() ?? ""
            return (clip, -1)
        }

        // 宽松匹配 datetime: 允许冒号前后有空格
        let datetimePrefix = "datetime"
        if trimmed.hasPrefix(datetimePrefix) {
            let afterDatetime = trimmed.dropFirst(datetimePrefix.count)
            // 跳过冒号前的空格，找到冒号
            if let colonIndex = afterDatetime.firstIndex(of: ":") {
                let format = String(afterDatetime[afterDatetime.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                let formatter = DateFormatter()
                formatter.dateFormat = format
                let dateString = formatter.string(from: dateProvider())
                return (dateString, -1)
            }
        }

        // 未知变量 — 保留原文
        return ("{" + content + "}", -1)
    }
}
