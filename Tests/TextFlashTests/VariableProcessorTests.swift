import Foundation
import Testing
@testable import TextFlash

@Test func snippetGroupCodableRoundTrip() throws {
    let group = SnippetGroup(
        name: "通用",
        snippets: [
            Snippet(abbreviation: "sig", expandedText: "Regards", description: "签名")
        ]
    )

    let data = try JSONEncoder().encode(group)
    let decoded = try JSONDecoder().decode(SnippetGroup.self, from: data)

    #expect(decoded.id == group.id)
    #expect(decoded.name == "通用")
    #expect(decoded.snippets.first?.abbreviation == "sig")
}

// MARK: - 固定日期 Provider，用于确定性测试
private func fixedDate() -> Date {
    let components = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(identifier: "Asia/Shanghai"),
        year: 2026, month: 5, day: 18,
        hour: 14, minute: 30, second: 45
    )
    return components.date!
}

private func formattedFixedDate(_ format: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = format
    return formatter.string(from: fixedDate())
}

// MARK: - 固定剪贴板 Provider
private func fixedClipboard() -> String? {
    "剪贴板内容"
}

// MARK: - 辅助工厂
private func makeProcessor(
    clipboard: @escaping () -> String? = { nil },
    date: @escaping () -> Date = { Date() }
) -> VariableProcessor {
    VariableProcessor(clipboardProvider: clipboard, dateProvider: date)
}

// MARK: - 纯文本（无变量）

@Test func plainTextNoVariables() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "Hello World")
    #expect(result == "Hello World")
    #expect(offset == -1)
}

@Test func emptyString() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "")
    #expect(result == "")
    #expect(offset == -1)
}

// MARK: - {cursor}

@Test func cursorOnly() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "{cursor}")
    #expect(result == "")
    #expect(offset == 0)
}

@Test func cursorAtStart() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "{cursor}World")
    #expect(result == "World")
    #expect(offset == 0)
}

@Test func cursorAtEnd() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "Hello{cursor}")
    #expect(result == "Hello")
    #expect(offset == 5)
}

@Test func cursorInMiddle() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "Hello {cursor} World")
    #expect(result == "Hello  World")
    #expect(offset == 6)
}

@Test func multipleCursorsFirstWins() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "{cursor} A {cursor} B")
    #expect(result == " A  B")
    #expect(offset == 0)
}

@Test func cursorWithWhitespace() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "{ cursor }")
    #expect(result == "")
    #expect(offset == 0)
}

// MARK: - {datetime:format}

@Test func datetimeDateFormat() {
    let p = makeProcessor(date: fixedDate)
    let (result, offset) = p.process(text: "{datetime:yyyy-MM-dd}")
    #expect(result == formattedFixedDate("yyyy-MM-dd"))
    #expect(offset == -1)
}

@Test func datetimeTimeFormat() {
    let p = makeProcessor(date: fixedDate)
    let (result, offset) = p.process(text: "{datetime:HH:mm}")
    #expect(result == formattedFixedDate("HH:mm"))
    #expect(offset == -1)
}

@Test func datetimeFullFormat() {
    let p = makeProcessor(date: fixedDate)
    let (result, offset) = p.process(text: "{datetime:yyyy-MM-dd HH:mm:ss}")
    #expect(result == formattedFixedDate("yyyy-MM-dd HH:mm:ss"))
    #expect(offset == -1)
}

@Test func datetimeChineseFormat() {
    let p = makeProcessor(date: fixedDate)
    let (result, offset) = p.process(text: "{datetime:yyyy年M月d日}")
    #expect(result == formattedFixedDate("yyyy年M月d日"))
    #expect(offset == -1)
}

@Test func datetimeInSentence() {
    let p = makeProcessor(date: fixedDate)
    let (result, offset) = p.process(text: "今天是 {datetime:yyyy-MM-dd}")
    #expect(result == "今天是 \(formattedFixedDate("yyyy-MM-dd"))")
    #expect(offset == -1)
}

@Test func datetimeWithWhitespaceAroundColon() {
    let p = makeProcessor(date: fixedDate)
    let (result, offset) = p.process(text: "{datetime : yyyy}")
    #expect(result == formattedFixedDate("yyyy"))
    #expect(offset == -1)
}

@Test func diagnosticsWarnsForEmptyDateFormat() {
    let p = makeProcessor(date: fixedDate)

    #expect(p.diagnostics(for: "{datetime:}") == [.emptyDateTimeFormat])
}

@Test func diagnosticsIgnoresEscapedDateFormat() {
    let p = makeProcessor(date: fixedDate)

    #expect(p.diagnostics(for: "\\{datetime:}") == [])
}

// MARK: - {clipboard}

@Test func clipboardVariable() {
    let p = makeProcessor(clipboard: fixedClipboard)
    let (result, offset) = p.process(text: "{clipboard}")
    #expect(result == "剪贴板内容")
    #expect(offset == -1)
}

@Test func clipboardInSentence() {
    let p = makeProcessor(clipboard: fixedClipboard)
    let (result, offset) = p.process(text: "粘贴: {clipboard}")
    #expect(result == "粘贴: 剪贴板内容")
    #expect(offset == -1)
}

@Test func clipboardNil() {
    let p = makeProcessor(clipboard: { nil })
    let (result, offset) = p.process(text: "{clipboard}")
    #expect(result == "")
    #expect(offset == -1)
}

// MARK: - {enter}

@Test func enterVariable() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "{enter}")
    #expect(result == "\n")
    #expect(offset == -1)
}

@Test func enterInSentence() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "Line1{enter}Line2")
    #expect(result == "Line1\nLine2")
    #expect(offset == -1)
}

@Test func tabVariable() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "A{tab}B")
    #expect(result == "A\tB")
    #expect(offset == -1)
}

// MARK: - 转义

@Test func escapedBrace() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "\\{not a variable}")
    #expect(result == "{not a variable}")
    #expect(offset == -1)
}

@Test func escapedBackslash() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "\\\\{cursor}")
    #expect(result == "\\")
    #expect(offset == 1) // cursor 在 \ 之后
}

@Test func doubleEscapedBrace() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "\\\\\\{text}")
    // \\\\ → \\ + \\{ → \\{text} → \{text}
    // Wait: \\\\ → first pair: \\ and \\ → but actually:
    // \\\\\\{text} — let me trace: 
    // index 0: '\\' → next is '\\' → literal '\\', skip 2
    // index 2: '\\\\'? No...
    // Actually the string is: backslash, backslash, backslash, {, t, e, x, t, }
    // "\\\\\\{text}" = \\, \\, \\, {, t, e, x, t, }
    // i=0: '\\' → next='\\' → literal '\\' → skip to i=2
    // i=2: '\\' → next='{' → literal '{' → skip to i=4
    // i=4: 't' ... → literal text
    // result: "\\{text}"
    #expect(result == "\\{text}")
    #expect(offset == -1)
}

@Test func backslashAtEnd() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "end\\")
    #expect(result == "end\\")
    #expect(offset == -1)
}

// MARK: - 未知/无法解析的变量

@Test func unknownVariablePreserved() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "{unknown}")
    #expect(result == "{unknown}")
    #expect(offset == -1)
}

@Test func unclosedBracePreserved() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "Hello {world")
    #expect(result == "Hello {world")
    #expect(offset == -1)
}

@Test func orphanClosingBrace() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "Hello } world")
    #expect(result == "Hello } world")
    #expect(offset == -1)
}

// MARK: - 组合场景

@Test func allVariablesCombined() {
    let p = makeProcessor(clipboard: fixedClipboard, date: fixedDate)
    let (result, offset) = p.process(text: "{datetime:HH:mm} {clipboard}{enter}{cursor}done")
    #expect(result == "\(formattedFixedDate("HH:mm")) 剪贴板内容\ndone")
    #expect(offset == 12) // "14:30 剪贴板内容\n" = 5+1+5+1
}

@Test func cursorBeforeDatetime() {
    let p = makeProcessor(date: fixedDate)
    let (result, offset) = p.process(text: "{cursor}{datetime:yyyy}")
    #expect(result == formattedFixedDate("yyyy"))
    #expect(offset == 0)
}

@Test func nestedBracesInContent() {
    let p = makeProcessor()
    // {foo{bar}} — depth tracking: open { at 0 (depth 1), { at 4 (depth 2), } at 8 (depth 1), } at 9 (depth 0)
    // content = "foo{bar"
    let (result, offset) = p.process(text: "{foo{bar}}")
    #expect(result == "{foo{bar}}") // unknown variable → preserved
    #expect(offset == -1)
}

@Test func literalCurlyInText() {
    let p = makeProcessor()
    let (result, offset) = p.process(text: "Set = \\{1, 2, 3\\}")
    #expect(result == "Set = {1, 2, 3}")
    #expect(offset == -1)
}

@Test func complexTemplate() {
    let p = makeProcessor(clipboard: fixedClipboard, date: fixedDate)
    let text = """
    Dear {clipboard},
    
    Date: {datetime:yyyy-MM-dd}
    Time: {datetime:HH:mm:ss}
    
    Body starts here{cursor}
    Sincerely,
    Nekutai
    """
    let (result, offset) = p.process(text: text)
    let expected = """
    Dear 剪贴板内容,
    
    Date: \(formattedFixedDate("yyyy-MM-dd"))
    Time: \(formattedFixedDate("HH:mm:ss"))
    
    Body starts here
    Sincerely,
    Nekutai
    """
    #expect(result == expected)
    // cursor position is right before "\nSincerely" after "Body starts here"
    let cursorPos = (
        "Dear 剪贴板内容,\n\n" +
        "Date: \(formattedFixedDate("yyyy-MM-dd"))\n" +
        "Time: \(formattedFixedDate("HH:mm:ss"))\n\n" +
        "Body starts here"
    ).count
    #expect(offset == cursorPos)
}
