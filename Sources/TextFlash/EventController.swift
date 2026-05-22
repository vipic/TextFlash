import Cocoa
import CoreGraphics

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
    /// Event tap 自动恢复次数（调试用）
    var tapRecoveryCount = 0
    /// 前缀树
    private let matcher = SnippetMatcher()
    /// 缩写→展开文本字典（用于快速查询完整展开）
    private var snippets: [String: String] = [:]
    /// 触发字符集——当这些字符出现时触发匹配检查
    public var triggerCharacters: Set<Character> = [
        " ", "\t", "\r", "\n",
        ")", "]", "}", ">",
    ]
    /// 注入时的事件源标记值（防止自触发）
    private static let injectionTag: Int64 = 0x53_4E_49_50  // "SNIP" in hex
    private let excludedBundleIDsKey = "TextFlashExcludedBundleIDs"

    public var isPaused: Bool {
        !isRunning
    }

    public var excludedBundleIDs: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: excludedBundleIDsKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: excludedBundleIDsKey)
        }
    }

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

    public func setPaused(_ paused: Bool) {
        if paused {
            stop()
        } else {
            startWithPrompt()
        }
    }

    public func togglePaused() {
        setPaused(!isPaused)
    }

    public func toggleExclusionForFocusedApplication() -> FocusedApplicationInfo? {
        guard let app = focusedApplicationInfo() else { return nil }
        var exclusions = excludedBundleIDs
        if exclusions.contains(app.bundleID) {
            exclusions.remove(app.bundleID)
        } else {
            exclusions.insert(app.bundleID)
        }
        excludedBundleIDs = exclusions
        return app
    }

    /// 添加一条文本缩写
    public func addSnippet(_ abbreviation: String, expansion: String) {
        guard !abbreviation.isEmpty, !expansion.isEmpty else { return }
        snippets[abbreviation] = expansion
        matcher.insert(abbreviation: abbreviation, expansion: expansion)
    }

    /// 移除一条文本缩写
    public func removeSnippet(_ abbreviation: String) {
        snippets.removeValue(forKey: abbreviation)
        matcher.remove(abbreviation: abbreviation)
    }

    /// 清除所有缩写
    public func removeAllSnippets() {
        snippets.removeAll()
        matcher.clear()
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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handleDisabledEventTap()
            return Unmanaged.passUnretained(event)
        }

        // 过滤自身注入的事件
        let tag = event.getIntegerValueField(.eventSourceUserData)
        if tag == Self.injectionTag {
            return Unmanaged.passUnretained(event)
        }

        let shouldConsume: Bool
        if Thread.isMainThread {
            shouldConsume = processKeyboardEvent(event)
        } else {
            shouldConsume = DispatchQueue.main.sync {
                processKeyboardEvent(event)
            }
        }

        return shouldConsume ? nil : Unmanaged.passUnretained(event)
    }

    private func handleDisabledEventTap() {
        inputBuffer = ""
        guard let tap = eventTap else {
            isRunning = false
            return
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        tapRecoveryCount += 1
    }

    /// Updates the input buffer and returns true when the original keyDown event
    /// must be suppressed because TextFlash will re-inject the trigger itself.
    private func processKeyboardEvent(_ event: CGEvent) -> Bool {
        guard !isInjecting else { return false }
        guard !isFocusedApplicationExcluded() else {
            inputBuffer = ""
            return false
        }

        // 过滤修饰键组合（Cmd/Ctrl 快捷键不触发展开）
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            // 快捷键触发了，重置输入缓冲区
            inputBuffer = ""
            return false
        }

        let kc = event.getIntegerValueField(.keyboardEventKeycode)

        // 退格键：从缓冲区移除最后一个字符
        if kc == 51 { // kVK_Delete
            if !inputBuffer.isEmpty {
                inputBuffer.removeLast()
            }
            return false
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
            return false
        }

        // 非打印字符跳过（退格除外）
        guard unicodeLength == 1 else {
            return false
        }

        guard let scalar = UnicodeScalar(unicodeBuffer[0]) else {
            return false
        }
        let char = Character(scalar)

        // 触发字符检查
        if triggerCharacters.contains(char) {
            defer { inputBuffer = "" }
            guard let match = matcher.match(in: inputBuffer) else {
                return false
            }
            guard !isFocusedElementSecureOrUnknown() else {
                return false
            }
            inject(abbreviation: match.abbreviation, expansion: match.expansion, triggerChar: char)
            return true
        }

        // 非触发字符 → 一律加入 buffer，Trie 检查即时匹配
        inputBuffer.append(char)
        guard let match = matcher.match(in: inputBuffer) else {
            inputBuffer = matcher.trimToPossibleSuffix(inputBuffer)
            return false
        }

        // 即时触发时原始按键需要先进入目标应用，然后再回删完整缩写。
        if !isFocusedElementSecureOrUnknown() {
            inject(abbreviation: match.abbreviation, expansion: match.expansion, triggerChar: nil)
        }
        inputBuffer = ""
        return false
    }

    // MARK: - Trigger Handling

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

    /// 检查当前焦点元素是否为安全文本域（密码框）。无法确认时保守阻止展开。
    private func isFocusedElementSecureOrUnknown() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp
        ) == .success else { return true }
        guard let app = focusedApp else { return true }

        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            (app as! AXUIElement),
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success else { return true }
        guard let element = focusedElement else { return true }

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

    private func isFocusedApplicationExcluded() -> Bool {
        guard let app = focusedApplicationInfo() else { return false }
        return excludedBundleIDs.contains(app.bundleID)
    }

    public func focusedApplicationInfo() -> FocusedApplicationInfo? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp
        ) == .success else { return nil }
        guard let app = focusedApp else { return nil }

        var pidValue: pid_t = 0
        guard AXUIElementGetPid((app as! AXUIElement), &pidValue) == .success,
              let runningApp = NSRunningApplication(processIdentifier: pidValue),
              let bundleID = runningApp.bundleIdentifier
        else { return nil }

        return FocusedApplicationInfo(
            bundleID: bundleID,
            localizedName: runningApp.localizedName ?? bundleID
        )
    }
}

public struct FocusedApplicationInfo {
    public let bundleID: String
    public let localizedName: String
}
