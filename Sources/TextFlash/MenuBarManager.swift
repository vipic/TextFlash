import Cocoa
import OSLog

/// 菜单栏管理器：左键打开片段窗口，右键弹出菜单。
@MainActor
final class MenuBarManager: NSObject {

    static let shared = MenuBarManager()
    private let log = Logger(subsystem: "com.nekutai.textflash", category: "menubar")

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var updateMenuItem: NSMenuItem?

    private override init() {
        super.init()
    }

    func setup() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }

        buildMenu()

        if let button = statusItem.button {
            button.image = textFlashStatusIcon()
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateMenuState()
        log.info("菜单栏已配置")
    }

    // MARK: - 点击处理

    @objc private func statusItemClicked() {
        if Self.shouldOpenMenu(for: NSApp.currentEvent?.type) {
            showMenu()
        } else {
            AppDelegate.shared?.openSnippetWindow()
        }
    }

    static func shouldOpenMenu(for eventType: NSEvent.EventType?) -> Bool {
        eventType == .rightMouseUp
    }

    // MARK: - 构建菜单

    private func buildMenu() {
#if DEBUG
        let includeDebug = true
#else
        let includeDebug = false
#endif
        let result = MenuBarMenuFactory.build(
            target: self,
            actions: MenuBarMenuActions(
                openSnippets: #selector(openSnippetsAction),
                checkUpdates: #selector(checkUpdatesAction),
                openSettings: #selector(openSettingsAction),
                addUnicodeCurrent: #selector(addUnicodeCurrentAction),
                quit: #selector(quitApp),
                openDebug: #selector(openDebugAction)
            ),
            includeDebug: includeDebug
        )
        menu = result.menu
        updateMenuItem = result.updateItem
        updateMenuState()
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        let previousMenu = statusItem.menu
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = previousMenu
    }

    func languageDidChange() {
        buildMenu()
        updateStatusIcon()
    }

    func updateMenuState() {
        updateMenuItem?.isEnabled = !UpdateChecker.shared.isDevBuild
        updateStatusIcon()
    }

    // MARK: - 图标

    private func updateStatusIcon() {
        statusItem?.button?.image = textFlashStatusIcon()
    }

    private func textFlashStatusIcon() -> NSImage {
        let resourceName = isDevBuild ? "MenuBarIconDev" : "MenuBarIcon"
        if let image = bundledStatusIcon(named: resourceName, extension: "svg")
            ?? bundledStatusIcon(named: "MenuBarIcon", extension: "svg") {
            return image
        }
        return fallbackStatusIcon()
    }

    private func bundledStatusIcon(named name: String, extension fileExtension: String) -> NSImage? {
        if let url = AppResourceBundle.main.url(forResource: name, withExtension: fileExtension),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            image.accessibilityDescription = "TextFlash"
            return image
        }
        return nil
    }

    private var isDevBuild: Bool {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        return version.contains("-dev") || bundleID.hasSuffix(".dev")
    }

    private func fallbackStatusIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setFill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        NSString(string: "T").draw(
            in: NSRect(x: 0, y: 0.5, width: size.width, height: size.height),
            withAttributes: attributes
        )

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "TextFlash"
        return image
    }

    // MARK: - 操作

    @objc private func openSnippetsAction() {
        DispatchQueue.main.async {
            AppDelegate.shared?.openSnippetWindow()
        }
    }

    @objc private func checkUpdatesAction() {
        DispatchQueue.main.async {
            AppDelegate.shared?.showUpdateWindow()
        }
    }

    @objc private func openSettingsAction() {
        // 延迟一帧：等菜单退出 tracking mode 后再创建设置窗口
        DispatchQueue.main.async {
            AppDelegate.shared?.openSettingsWindow()
        }
    }

    @objc private func addUnicodeCurrentAction() {
        AppDelegate.shared?.addCurrentAppToUnicodeInput()
    }

    @objc private func openDebugAction() {
#if DEBUG
        DispatchQueue.main.async {
            AppDelegate.shared?.openDebugWindow()
        }
#endif
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
