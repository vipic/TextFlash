import SwiftUI
import AppKit

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    static weak var shared: AppDelegate?

    private var snippetWindow: NSWindow?
    private var settingsWindow: NSWindow?
#if DEBUG
    private var debugWindow: NSWindow?
#endif
    private var aboutWindow: NSWindow?
    private var updateWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        // LSUIElement：隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)
        setupApplicationMenu()

        MenuBarManager.shared.setup()
        loadSnippetsIntoController()
        EventController.shared.start()
        MenuBarManager.shared.updateMenuState()

        // 监听片段变更 → 实时重载匹配表
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(snippetsDidChange),
            name: .textFlashSnippetsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .textFlashLanguageDidChange,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        EventController.shared.stop()
    }

    // MARK: - 应用菜单

    private func setupApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "TextFlash")
        appMenu.addItem(self.appMenuItem(title: L10n.t("menu.openSnippets"), action: #selector(openSnippetWindow)))
        appMenu.addItem(self.appMenuItem(title: L10n.t("menu.settings"), action: #selector(openSettingsWindow), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(self.appMenuItem(title: L10n.t("menu.checkUpdates"), action: #selector(showUpdateWindow)))
        appMenu.addItem(self.appMenuItem(title: L10n.t("menu.about"), action: #selector(showAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: L10n.t("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: L10n.t("menu.window"))
        windowMenu.addItem(NSMenuItem(title: L10n.t("menu.closeWindow"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func appMenuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func presentWindow(_ window: NSWindow) {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreAccessoryModeIfNoManagedWindows() {
        var managedWindows: [NSWindow?] = [
            snippetWindow,
            settingsWindow,
            aboutWindow,
            updateWindow
        ]
#if DEBUG
        managedWindows.append(debugWindow)
#endif
        let hasOpenWindow = managedWindows.contains { window in
            guard let window else { return false }
            return window.isVisible || window.isMiniaturized
        }
        if !hasOpenWindow, NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - 片段窗口

    @objc func openSnippetWindow() {
        // 打开管理面板只做静默启动，不主动弹系统权限提示。
        EventController.shared.start()

        if let existing = snippetWindow {
            presentWindow(existing)
            return
        }

        let manager = SnippetManager()
        let defaultContentSize = NSSize(width: 1040, height: 640)
        let minimumContentSize = NSSize(width: 900, height: 560)
        let hostingView = NSHostingView(rootView: SnippetManagerView(manager: manager))
        hostingView.frame = NSRect(origin: .zero, size: defaultContentSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("window.snippets")
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isReleasedWhenClosed = false  // 关闭时不释放，手动管理生命周期
        window.contentView = hostingView
        window.contentMinSize = minimumContentSize
        window.center()
        window.setFrameAutosaveName("TextFlashSnippetWindow")
        enforceMinimumContentSize(minimumContentSize, for: window)

        // 监听窗口关闭 → 清空引用，防止下次点击访问悬垂指针
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.snippetWindow = nil
                self?.restoreAccessoryModeIfNoManagedWindows()
            }
        }

        presentWindow(window)
        snippetWindow = window
    }

    private func enforceMinimumContentSize(_ minimumSize: NSSize, for window: NSWindow) {
        let contentSize = window.contentLayoutRect.size
        guard contentSize.width < minimumSize.width || contentSize.height < minimumSize.height else { return }

        let clampedSize = NSSize(
            width: max(contentSize.width, minimumSize.width),
            height: max(contentSize.height, minimumSize.height)
        )
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: clampedSize))
        frame.origin = window.frame.origin
        window.setFrame(frame, display: false)
    }

    @objc func openSettingsWindow() {
        if let existing = settingsWindow {
            presentWindow(existing)
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView())
        let contentSize = NSSize(width: 620, height: 560)
        hostingView.frame = NSRect(origin: .zero, size: contentSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("window.settings")
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()
        window.setFrameAutosaveName("TextFlashSettingsWindow")

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.settingsWindow = nil
                self?.restoreAccessoryModeIfNoManagedWindows()
            }
        }

        presentWindow(window)
        settingsWindow = window
    }

    @objc func showAbout() {
        if let existing = aboutWindow {
            presentWindow(existing)
            return
        }

        let hostingView = NSHostingView(rootView: AboutView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 300)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("about.title")
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.aboutWindow = nil
                self?.restoreAccessoryModeIfNoManagedWindows()
            }
        }

        presentWindow(window)
        aboutWindow = window
    }

    @MainActor func showAboutFromApplicationMenu() {
        showAbout()
    }

    @objc func showUpdateWindow() {
        if let existing = updateWindow {
            presentWindow(existing)
            return
        }

        let hostingView = NSHostingView(rootView: UpdateView(
            state: .checking,
            releaseNotes: nil,
            currentVersion: nil,
            latestVersion: nil,
            onCancel: nil
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 360)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("update.title")
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateWindow = nil
                self?.restoreAccessoryModeIfNoManagedWindows()
            }
        }

        presentWindow(window)
        updateWindow = window

        Task { @MainActor in
            if let result = await UpdateChecker.shared.checkForUpdate(force: true) {
                let notes = result.releaseNotes
                hostingView.rootView = UpdateView(
                    state: .updateAvailable(result: result),
                    releaseNotes: notes,
                    currentVersion: result.currentVersion,
                    latestVersion: result.latestVersion,
                    onUpdate: { [weak self, weak hostingView, weak window] in
                        guard let self, let hostingView, let window else { return }
                        Task { @MainActor in
                            await self.performUpdateFlow(
                                result: result,
                                notes: notes,
                                currentVersion: result.currentVersion,
                                latestVersion: result.latestVersion,
                                hostingView: hostingView,
                                window: window
                            )
                        }
                    },
                    onCancel: { [weak window] in
                        window?.close()
                    }
                )
            } else {
                hostingView.rootView = UpdateView(
                    state: .upToDate(
                        version: AppVersion.displayCurrent,
                        build: AppVersion.displayBuild,
                        lastCheckDate: UpdateChecker.shared.lastCheckDate(),
                        lastReleaseNotes: UpdateChecker.shared.cachedReleaseNotes()
                    ),
                    releaseNotes: UpdateChecker.shared.cachedReleaseNotes(),
                    currentVersion: nil,
                    latestVersion: nil,
                    onCancel: { [weak window] in
                        window?.close()
                    }
                )
            }
        }
    }

    @MainActor
    private func performUpdateFlow(result: UpdateChecker.UpdateResult,
                                   notes: String,
                                   currentVersion: String,
                                   latestVersion: String,
                                   hostingView: NSHostingView<UpdateView>,
                                   window: NSWindow) async {
        hostingView.rootView = UpdateView(
            state: .downloading(progress: 0),
            releaseNotes: notes,
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            onCancel: { [weak window] in
                window?.close()
            }
        )

        do {
            let tempURL = try await UpdateChecker.shared.downloadBinary(
                from: result.downloadURL,
                expectedSize: result.downloadSize,
                onProgress: { [weak hostingView, notes, currentVersion, latestVersion, weak window] progress in
                    DispatchQueue.main.async {
                        hostingView?.rootView = UpdateView(
                            state: .downloading(progress: progress),
                            releaseNotes: notes,
                            currentVersion: currentVersion,
                            latestVersion: latestVersion,
                            onCancel: { [weak window] in window?.close() }
                        )
                    }
                }
            )

            hostingView.rootView = UpdateView(
                state: .installing,
                releaseNotes: notes,
                currentVersion: currentVersion,
                latestVersion: latestVersion,
                onCancel: nil
            )

            try UpdateChecker.shared.applyUpdate(dmgAt: tempURL, expectedVersion: result.latestVersion)
        } catch {
            hostingView.rootView = UpdateView(
                state: .error(error.localizedDescription),
                releaseNotes: nil,
                currentVersion: nil,
                latestVersion: nil,
                onCancel: { [weak window] in window?.close() }
            )
        }
    }

    @objc func addCurrentAppToUnicodeInput() {
        guard let app = EventController.shared.exclusionTargetApplication() else {
            showSimpleAlert(
                title: L10n.t("unicodeApps.addFailed.title"),
                message: L10n.t("unicodeApps.addFailed.message")
            )
            return
        }
        var bundleIDs = EventController.shared.unicodeBundleIDs
        bundleIDs.insert(app.bundleID)
        EventController.shared.unicodeBundleIDs = bundleIDs
    }

    private func showSimpleAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

#if DEBUG
    @objc func openDebugWindow() {
        if let existing = debugWindow {
            presentWindow(existing)
            return
        }

        let hostingView = NSHostingView(rootView: DebugPanel())
        hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 520)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("window.debug")
        window.isReleasedWhenClosed = false  // 关闭时不释放，手动管理生命周期
        window.contentView = hostingView
        window.center()
        window.setFrameAutosaveName("TextFlashDebugWindow")

        // 监听窗口关闭 → 清空引用，防止下次点击访问悬垂指针
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.debugWindow = nil
                self?.restoreAccessoryModeIfNoManagedWindows()
            }
        }

        presentWindow(window)
        debugWindow = window
    }
#endif

    // MARK: - EventController 同步

    private func loadSnippetsIntoController() {
        EventController.shared.removeAllSnippets()
        let groups = DatabaseManager.shared.fetchAllGroups()
        for group in groups {
            for snippet in group.snippets where !snippet.abbreviation.isEmpty {
                EventController.shared.addSnippet(
                    snippet.abbreviation,
                    expansion: snippet.expandedText
                )
            }
        }
    }

    @objc private func snippetsDidChange(_ notification: Notification) {
        loadSnippetsIntoController()
    }

    @objc private func languageDidChange(_ notification: Notification) {
        setupApplicationMenu()
        MenuBarManager.shared.languageDidChange()
        snippetWindow?.title = L10n.t("window.snippets")
        settingsWindow?.title = L10n.t("window.settings")
        aboutWindow?.title = L10n.t("about.title")
        updateWindow?.title = L10n.t("update.title")
#if DEBUG
        debugWindow?.title = L10n.t("window.debug")
#endif
    }
}

// MARK: - App 入口

@main
struct TextFlashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L10n.t("menu.about")) {
                    Task { @MainActor in
                        appDelegate.showAboutFromApplicationMenu()
                    }
                }
            }
        }
    }
}
