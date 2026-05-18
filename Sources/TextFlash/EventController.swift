import Cocoa
import CoreGraphics

// MARK: - Trie-based Snippet Matcher

/// 前缀树节点——用于快速缩写匹配
private final class TrieNode {
    var children: [Character: TrieNode] = [:]
    /// 叶节点存储展开文本，非叶节点为 nil
    var expansion: String?
}

/// 前缀树（Trie）——O(k) 匹配，k=缩写长度
private final class Trie {
    let root = TrieNode()

    /// 插入一条缩写→展开映射
    func insert(abbreviation: String, expansion: String) {
        var node = root
        for ch in abbreviation {
            if let next = node.children[ch] {
                node = next
            } else {
                let next = TrieNode()
                node.children[ch] = next
                node = next
            }
        }
        node.expansion = expansion
    }

    /// 查找前缀：返回 (是否可能匹配, 展开文本)
    /// - 如果前缀是完整缩写且匹配，返回 (true, expansion)
    /// - 如果前缀是某缩写的开头，返回 (true, nil) 表示可能匹配
    /// - 如果前缀不匹配任何缩写，返回 (false, nil)
    func search(_ prefix: String) -> (matched: Bool, expansion: String?) {
        var node = root
        for ch in prefix {
            guard let next = node.children[ch] else {
                return (false, nil)
            }
            node = next
        }
        return (true, node.expansion)
    }

    /// 移除一条缩写（如未使用则惰性清理节点）
    func remove(abbreviation: String) {
        var node = root
        var path: [(TrieNode, Character)] = []
        for ch in abbreviation {
            guard let next = node.children[ch] else { return }
            path.append((node, ch))
            node = next
        }
        node.expansion = nil
        // 从后向前清理无子节点的路径
        for (parent, ch) in path.reversed() {
            guard let child = parent.children[ch], child.children.isEmpty, child.expansion == nil else {
                break
            }
            parent.children.removeValue(forKey: ch)
        }
    }

    /// 清空所有条目
    func clear() {
        root.children.removeAll()
    }
}

// MARK: - EventController

/// 全系统文本展开控制器——单例模式，通过 CGEvent tap 全局监听键盘事件，
/// 匹配预设缩写并注入展开文本。
///
/// ## 使用方式
/// ```swift
/// // 注册缩写
/// EventController.shared.addSnippet("addr", expansion: "123 Main Street, Springfield, IL 62701")
/// EventController.shared.addSnippet("sig", expansion: "Best regards,\nNekutai")
///
/// // 启动监听
/// EventController.shared.start()
///
/// // 停止监听
/// EventController.shared.stop()
/// ```
///
/// ## 注入流程
/// 1. 用户输入缩写 + 触发字符（空格/回车/Tab/标点）
/// 2. `discardMarkedText()` 清除输入法组合缓冲区
/// 3. 延时 5ms 确保 discard 生效
/// 4. 发送退格事件删除已输入缩写
/// 5. 通过 `CGEventPost` + `keyboardSetUnicodeString` 注入展开文本
/// 6. 注入触发字符，保留后续输入的正常流程
public final class EventController {
    // MARK: - Singleton

    public static let shared = EventController()

    private init() {}

    // MARK: - Properties

    /// 事件 tap 引用
    private var eventTap: CFMachPort?
    /// RunLoop 事件源
    private var runLoopSource: CFRunLoopSource?
    /// 当前输入缓冲区（调试用）
    var inputBuffer = ""
    /// 是否正在运行（调试用）
    var isRunning = false
    /// 是否正在注入（调试用）
    var isInjecting = false
    /// 前缀树
    private let trie = Trie()
    /// 缩写→展开文本字典（用于快速查询完整展开）
    private var snippets: [String: String] = [:]
    /// 触发字符集——当这些字符出现时触发匹配检查
    public var triggerCharacters: Set<Character> = [
        " ", "\t", "\r", "\n",
        ")", "]", "}", ">",
    ]
    /// 注入时的事件源标记值（防止自触发）
    private static let injectionTag: Int64 = 0x53_4E_49_50  // "SNIP" in hex
    // MARK: - Public API

    /// 启动全局键盘事件监听。返回 false 表示权限不足（静默失败，不弹窗）。
    /// 权限提示在用户交互时懒加载触发（打开片段窗口/添加片段时）。
    @discardableResult
    public func start() -> Bool {
        guard !isRunning else { return true }
        guard checkPermission() else {
            return false
        }
        setupEventTap()
        isRunning = true
        return true
    }

    /// 尝试验证并启动——权限不足时弹出引导对话框
    @discardableResult
    public func startWithPrompt() -> Bool {
        if start() { return true }
        requestPermission()
        return false
    }

    /// 停止监听并释放所有事件源
    public func stop() {
        guard isRunning else { return }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            self.eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            self.runLoopSource = nil
        }
        inputBuffer = ""
        isRunning = false
    }

    /// 重新启动（权限变更后调用）
    public func restart() {
        stop()
        start()
    }

    /// 添加一条文本缩写
    public func addSnippet(_ abbreviation: String, expansion: String) {
        guard !abbreviation.isEmpty, !expansion.isEmpty else { return }
        snippets[abbreviation] = expansion
        trie.insert(abbreviation: abbreviation, expansion: expansion)
    }

    /// 移除一条文本缩写
    public func removeSnippet(_ abbreviation: String) {
        snippets.removeValue(forKey: abbreviation)
        trie.remove(abbreviation: abbreviation)
    }

    /// 清除所有缩写
    public func removeAllSnippets() {
        snippets.removeAll()
        trie.clear()
    }

    /// 已加载的缩写列表（调试用）
    var loadedAbbreviations: [String] {
        Array(snippets.keys)
    }

    /// 查询缩写的展开文本（调试用）
    func expansionFor(_ abbreviation: String) -> String? {
        snippets[abbreviation]
    }

    // MARK: - Permission

    /// 检查辅助功能权限
    public func checkPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    /// 请求辅助功能权限——弹出系统授权对话框，或引导用户打开系统设置
    public func requestPermission() {
        // 只弹一次系统对话框
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        let alreadyTrusted = AXIsProcessTrustedWithOptions(options)

        if !alreadyTrusted, !AXIsProcessTrusted() {
            // 用户拒绝了系统弹窗 → 引导打开系统设置
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "需要辅助功能权限"
                alert.informativeText = """
                文本展开需要辅助功能权限来监听键盘事件并注入文本。

                请在「系统设置 → 隐私与安全性 → 辅助功能」中启用此应用。
                """
                alert.alertStyle = .informational
                alert.addButton(withTitle: "打开系统设置")
                alert.addButton(withTitle: "稍后")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                }
            }
        }
    }

    // MARK: - Event Tap Setup

    private func setupEventTap() {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        // 使用未管理指针传递 self，回调中还原
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<EventController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handleKeyboardEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            // tapCreate 返回 nil → 权限不足
            DispatchQueue.main.async { [weak self] in
                self?.requestPermission()
            }
            return
        }

        eventTap = tap

        // 附加到当前 RunLoop（common modes 保证右键菜单、拖拽时不丢事件）
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

        // 启用 tap
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Keyboard Event Handler

    /// 事件回调——运行在 CGEvent tap 的后台线程，必须极轻量
    private func handleKeyboardEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // 过滤自身注入的事件
        let tag = event.getIntegerValueField(.eventSourceUserData)
        if tag == Self.injectionTag {
            return Unmanaged.passUnretained(event)
        }

        // 过滤修饰键组合（Cmd/Ctrl 快捷键不触发展开）
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            // 快捷键触发了，重置输入缓冲区
            DispatchQueue.main.async { [weak self] in
                self?.inputBuffer = ""
            }
            return Unmanaged.passUnretained(event)
        }

        // 获取按键的 Unicode 字符
        var unicodeLength: Int = 0
        var unicodeBuffer = [UniChar](repeating: 0, count: 20)
        event.keyboardGetUnicodeString(
            maxStringLength: 20,
            actualStringLength: &unicodeLength,
            unicodeString: &unicodeBuffer
        )

        // 无 Unicode 字符（如功能键/方向键/输入法组合中）→ 忽略
        guard unicodeLength > 0 else {
            return Unmanaged.passUnretained(event)
        }

        let char = Character(UnicodeScalar(unicodeBuffer[0])!)
        let kc = event.getIntegerValueField(.keyboardEventKeycode)

        // 退格键：从缓冲区移除最后一个字符
        if kc == 51 { // kVK_Delete
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.inputBuffer.isEmpty else { return }
                self.inputBuffer.removeLast()
            }
            return Unmanaged.passUnretained(event)
        }

        // 非打印字符跳过（退格除外）
        guard unicodeLength == 1 else {
            return Unmanaged.passUnretained(event)
        }

        // 触发字符检查
        if triggerCharacters.contains(char) {
            DispatchQueue.main.async { [weak self] in
                self?.handleTrigger(char)
            }
            DispatchQueue.main.async { [weak self] in
                self?.inputBuffer = ""
            }
        } else {
            // 非触发字符 → 一律加入 buffer，Trie 检查即时匹配
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.inputBuffer.append(char)
                let buffer = self.inputBuffer

                // 从最长后缀开始尝试匹配
                for i in buffer.indices {
                    let suffix = String(buffer[i...])
                    let (matched, expansion) = self.trie.search(suffix)
                    if expansion != nil {
                        // 完整匹配 → 即时触发
                        self.handleTrigger(nil)
                        self.inputBuffer = ""
                        return
                    }
                    if matched {
                        // 部分前缀匹配 → 保留 buffer 等待更多输入
                        return
                    }
                    // matched==false → 这个后缀长度不可能匹配，试试更短的
                }
                // 所有后缀都不匹配 → 清空
                self.inputBuffer = ""
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Trigger Handling

    /// 触发字符到达时的匹配与注入逻辑（主线程调用）
    /// - Parameter triggerChar: 触发字符；nil 表示即时触发（无外部触发字符）
    private func handleTrigger(_ triggerChar: Character?) {
        guard !isInjecting else { return }
        let buffer = inputBuffer
        guard !buffer.isEmpty else { return }

        // 从最长后缀搜，找匹配的缩写（和即时触发使用相同的后缀扫描逻辑）
        for i in buffer.indices {
            let suffix = String(buffer[i...])
            let (matched, expansion) = trie.search(suffix)
            if let text = expansion {
                // 完整匹配找到
                guard !isSecureTextField() else { return }
                inject(abbreviation: suffix, expansion: text, triggerChar: triggerChar)
                return
            }
            if matched {
                // 部分前缀匹配（如 "d" 是 "ddm" 的前缀）→ 不继续扫更短后缀
                return
            }
        }
    }

    // MARK: - Text Injection

    /// 注入展开文本——核心序列：
    /// 1. 通过 VariableProcessor 处理变量占位符
    /// 2. discardMarkedText（清除输入法缓冲区）
    /// 3. 延时 5ms（等待 discard 生效）
    /// 4. 发送退格删除缩写字符
    /// 5. 通过 keyboardSetUnicodeString 注入展开文本
    /// 6. 注入触发字符
    /// 7. 移动光标到 {cursor} 位置
    private func inject(abbreviation: String, expansion: String, triggerChar: Character?) {
        isInjecting = true

        // Step 0: 处理变量占位符
        let processor = VariableProcessor()
        let (processedText, cursorOffset) = processor.process(text: expansion)

        // Step 1: 清除输入法组合缓冲区
        NSTextInputContext.current?.discardMarkedText()

        // Step 2: 延时 5ms 等待 discard 生效，然后注入
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(5)) { [weak self] in
            guard let self = self else { return }

            // Step 3: 发送退格事件删除缩写（每个字符一个退格）
            let backspaceCount = abbreviation.count
            for _ in 0..<backspaceCount {
                self.postKeyEvent(keyCode: 51, keyDown: true)  // kVK_Delete
                self.postKeyEvent(keyCode: 51, keyDown: false)
            }

            // Step 4: 注入展开文本（Unicode 方式，绕过键盘布局）
            self.postUnicodeString(processedText)

            // Step 5: 注入触发字符（即时触发时跳过）
            if let tc = triggerChar {
                self.postUnicodeString(String(tc))
            }

            // Step 6: 移动光标到 {cursor} 位置
            if cursorOffset >= 0 {
                let triggerLen = triggerChar != nil ? 1 : 0
                self.moveCursorLeft(by: processedText.count + triggerLen - cursorOffset)
            }

            self.isInjecting = false
        }
    }

    /// 发送一个按键事件（使用 privateState 源以避免自触发）
    private func postKeyEvent(keyCode: CGKeyCode, keyDown: Bool) {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.injectionTag)
        event.post(tap: .cghidEventTap)
    }

    /// 通过 Unicode 字符串注入文本——绕过键盘布局映射
    private func postUnicodeString(_ text: String) {
        guard let source = CGEventSource(stateID: .privateState) else { return }

        let utf16Chars = Array(text.utf16)
        guard !utf16Chars.isEmpty else { return }

        // 创建事件并设置 Unicode 字符串
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.injectionTag)

        utf16Chars.withUnsafeBufferPointer { ptr in
            event.keyboardSetUnicodeString(
                stringLength: utf16Chars.count,
                unicodeString: ptr.baseAddress
            )
        }

        event.post(tap: .cghidEventTap)

        // keyUp
        guard let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        keyUpEvent.post(tap: .cghidEventTap)
    }

    /// 向左移动光标 n 个字符（发送左箭头按键）
    private func moveCursorLeft(by count: Int) {
        guard count > 0, let source = CGEventSource(stateID: .privateState) else { return }
        for _ in 0..<count {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x7B, keyDown: true), // kVK_LeftArrow
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0x7B, keyDown: false)
            else { continue }
            down.setIntegerValueField(.eventSourceUserData, value: Self.injectionTag)
            up.setIntegerValueField(.eventSourceUserData, value: Self.injectionTag)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Secure Field Detection

    /// 检查当前焦点元素是否为安全文本域（密码框）
    private func isSecureTextField() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp
        ) == .success else { return false }
        guard let app = focusedApp else { return false }

        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            (app as! AXUIElement),
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success else { return false }
        guard let element = focusedElement else { return false }

        let axElement = element as! AXUIElement

        // 方法1：检查 AXIsSecureTextField 属性
        var isSecure: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            axElement, "AXIsSecureTextField" as CFString, &isSecure
        ) == .success {
            if let secure = isSecure as? Bool, secure {
                return true
            }
        }

        // 方法2：备选检查 subrole
        var subrole: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            axElement, kAXSubroleAttribute as CFString, &subrole
        ) == .success {
            if let subroleStr = subrole as? String, subroleStr == "AXSecureTextField" {
                return true
            }
        }

        return false
    }
}
