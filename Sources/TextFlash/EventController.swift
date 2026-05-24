import Cocoa
import CoreGraphics

extension Notification.Name {
    static let textFlashExclusionsDidChange = Notification.Name("TextFlashExclusionsDidChange")
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
/// 5. 通过 Accessibility 或 Unicode 事件注入展开文本
/// 6. 必要时注入触发字符，保留后续输入的正常流程
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
    private var lastNonTextFlashApplication: FocusedApplicationInfo?
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
            NotificationCenter.default.post(name: .textFlashExclusionsDidChange, object: self)
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
        guard setupEventTap() else {
            isRunning = false
            return false
        }
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
        guard let app = exclusionTargetApplication() else { return nil }
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
                alert.messageText = L10n.t("permission.request.title")
                alert.informativeText = L10n.t("permission.request.message")
                alert.alertStyle = .informational
                alert.addButton(withTitle: L10n.t("permission.request.open"))
                alert.addButton(withTitle: L10n.t("permission.request.later"))
                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: - Event Tap Setup

    @discardableResult
    private func setupEventTap() -> Bool {
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
            return false
        }

        eventTap = tap

        // 附加到当前 RunLoop（common modes 保证右键菜单、拖拽时不丢事件）
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            eventTap = nil
            return false
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

        // 启用 tap
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
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
        refreshLastNonTextFlashApplication()
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
        let matchingChar = normalizedMatchingCharacter(char)

        // 触发字符检查
        if triggerCharacters.contains(matchingChar) {
            defer { inputBuffer = "" }
            guard let match = matcher.match(in: inputBuffer) else {
                return false
            }
            guard !isFocusedElementSecure() else {
                return false
            }
            inject(
                abbreviation: match.abbreviation,
                expansion: match.expansion,
                triggerChar: char,
                deletionCount: match.abbreviation.count
            )
            return true
        }

        // 非触发字符 → 一律加入 buffer，Trie 检查即时匹配
        inputBuffer.append(matchingChar)
        guard let match = matcher.match(in: inputBuffer) else {
            inputBuffer = matcher.trimToPossibleSuffix(inputBuffer)
            return false
        }

        // 即时触发时拦截最后一个按键，只删除已经进入目标应用的前缀。
        guard !isFocusedElementSecure() else {
            inputBuffer = ""
            return false
        }
        inject(
            abbreviation: match.abbreviation,
            expansion: match.expansion,
            triggerChar: nil,
            deletionCount: max(0, match.abbreviation.count - 1)
        )
        inputBuffer = ""
        return true
    }

    // MARK: - Trigger Handling

    // MARK: - Text Injection

    /// 注入展开文本——核心序列：
    /// 1. 通过 VariableProcessor 处理变量占位符
    /// 2. discardMarkedText（清除输入法缓冲区）
    /// 3. 延时 5ms（等待 discard 生效）
    /// 4. 发送退格删除已经进入目标应用的缩写字符
    /// 5. 优先通过 Accessibility 写入展开文本
    /// 6. 失败时回退到 Unicode 事件注入
    /// 7. 移动光标到 {cursor} 位置
    private func inject(
        abbreviation: String,
        expansion: String,
        triggerChar: Character?,
        deletionCount: Int
    ) {
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
            let backspaceCount = deletionCount
            for _ in 0..<backspaceCount {
                self.postKeyEvent(keyCode: 51, keyDown: true)  // kVK_Delete
                self.postKeyEvent(keyCode: 51, keyDown: false)
            }

            // Telegram 等应用会延迟处理退格事件；等待缩写删除落地后再写入，避免尾部被后续退格误删。
            let delayPerCharacter = MainActor.assumeIsolated {
                AppSettings.shared.deletionSettleDelayPerCharacter
            }
            let deleteSettleDelay = max(20, Int(Double(backspaceCount) * delayPerCharacter))
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(deleteSettleDelay)) { [weak self] in
                guard let self = self else { return }
                // Step 4: 写入展开文本。部分 Electron/终端应用会 AX 返回成功但实际未写入，直接走 Unicode 注入。
                let insertionText = processedText + (triggerChar.map(String.init) ?? "")
                if self.shouldPreferUnicodeInsertionForFocusedApplication() {
                    self.postUnicodeString(insertionText)
                } else if !self.replaceFocusedSelection(with: insertionText) {
                    self.postUnicodeString(insertionText)
                }

                // Step 6: 移动光标到 {cursor} 位置
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
                    guard let self = self else { return }
                    if cursorOffset >= 0 {
                        let triggerLen = triggerChar != nil ? 1 : 0
                        self.moveCursorLeft(by: processedText.count + triggerLen - cursorOffset)
                    }
                    self.isInjecting = false
                }
            }
        }
    }

    /// 发送一个按键事件（使用 privateState 源以避免自触发）
    private func postKeyEvent(keyCode: CGKeyCode, keyDown: Bool) {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.injectionTag)
        event.post(tap: .cghidEventTap)
    }

    private func replaceFocusedSelection(with text: String) -> Bool {
        guard !text.isEmpty else { return true }
        guard let element = focusedTextElement() else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    private func normalizedMatchingCharacter(_ character: Character) -> Character {
        switch character {
        case "，":
            return ","
        case "。":
            return "."
        case "？":
            return "?"
        case "、":
            return "\\"
        default:
            return character
        }
    }

    private func shouldPreferUnicodeInsertionForFocusedApplication() -> Bool {
        guard let app = focusedApplicationInfo() ?? lastNonTextFlashApplication else { return false }
        let bundleID = app.bundleID.lowercased()
        let name = app.localizedName.lowercased()

        // 终端 / Electron / Ghostty 等已知不支持 AXSelectedText 的应用
        if bundleID.contains("codex")
            || bundleID.contains("iterm")
            || bundleID.contains("terminal")
            || bundleID.contains("electron")
            || bundleID.contains("ghostty")
            || name.contains("codex")
            || name.contains("iterm")
            || name.contains("terminal")
            || name.contains("ghostty") {
            return true
        }

        // 浏览器：AXSelectedText 写入不可靠（React/框架控制的 input 不响应 AX 值变更）
        if bundleID == "com.apple.safari"
            || bundleID == "com.google.chrome"
            || bundleID == "com.microsoft.edgemac"
            || bundleID.hasPrefix("org.mozilla.firefox")
            || bundleID == "com.brave.browser"
            || bundleID.hasPrefix("company.thebrowser") // Arc
            || bundleID == "com.operasoftware.opera" {
            return true
        }

        // 通用兜底：focused element 在 WebView（AXWebArea）内 → 走 Unicode
        if isFocusedElementInWebView() {
            return true
        }

        return false
    }

    /// 检查当前 focused element 是否在浏览器 WebView（AXWebArea）内。
    /// WebView 内的元素通过 AXSelectedText 写入不可靠，应走 Unicode 事件注入。
    private func isFocusedElementInWebView() -> Bool {
        guard let element = focusedTextElement() else { return false }
        var current: AXUIElement? = element
        for _ in 0..<10 {
            guard let el = current else { break }
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role) == .success,
                  let roleStr = role as? String else { break }
            if roleStr == "AXWebArea" {
                return true
            }
            // 到达 application 层仍未找到 → 不是 WebView
            if roleStr == "AXApplication" { break }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parent) == .success,
                  let parentElement = parent,
                  CFGetTypeID(parentElement) == AXUIElementGetTypeID() else { break }
            current = (parentElement as! AXUIElement)
        }
        return false
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

    /// 检查当前焦点元素是否为安全文本域（密码框）。
    /// 某些 Electron/WebView 应用无法稳定暴露 focused UI element；这种情况只在能明确识别安全输入框时才阻止展开。
    private func isFocusedElementSecure() -> Bool {
        guard let axElement = focusedTextElement() else { return false }

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

    private func focusedTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp
        ) == .success else { return nil }
        guard let app = focusedApp else { return nil }
        guard CFGetTypeID(app) == AXUIElementGetTypeID() else { return nil }
        let axApp = app as! AXUIElement

        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success else { return nil }
        guard let element = focusedElement else { return nil }
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        return (element as! AXUIElement)
    }

    private func isFocusedApplicationExcluded() -> Bool {
        guard let app = focusedApplicationInfo() else { return false }
        return excludedBundleIDs.contains(app.bundleID)
    }

    public func exclusionTargetApplication() -> FocusedApplicationInfo? {
        if let app = focusedApplicationInfo(), !app.isTextFlash {
            lastNonTextFlashApplication = app
            return app
        }
        return lastNonTextFlashApplication
    }

    private func refreshLastNonTextFlashApplication() {
        guard let app = focusedApplicationInfo(), !app.isTextFlash else { return }
        lastNonTextFlashApplication = app
    }

    public func focusedApplicationInfo() -> FocusedApplicationInfo? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp
        ) == .success else { return nil }
        guard let app = focusedApp else { return nil }
        guard CFGetTypeID(app) == AXUIElementGetTypeID() else { return nil }
        let axApp = app as! AXUIElement

        var pidValue: pid_t = 0
        guard AXUIElementGetPid(axApp, &pidValue) == .success,
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

    var isTextFlash: Bool {
        bundleID.hasPrefix("com.nekutai.textflash")
    }
}
