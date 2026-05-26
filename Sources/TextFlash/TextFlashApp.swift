import SwiftUI
import AppKit

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var snippetWindow: NSWindow?
    private var settingsWindow: NSWindow?
#if DEBUG
    private var debugWindow: NSWindow?
#endif
    private var exclusionsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var pauseMenuItem: NSMenuItem?
    private var permissionMenuItem: NSMenuItem?
    private var exclusionMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement：隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        setupMenuBar()
        loadSnippetsIntoController()
        EventController.shared.start()
        updateMenuState()  // start() 后才刷新状态栏图标，避免启动瞬间误显暂停图标

        // 监听片段变更 → 实时重载匹配表
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(snippetsDidChange),
            name: .textFlashSnippetsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(exclusionsDidChange),
            name: .textFlashExclusionsDidChange,
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

    // MARK: - 菜单栏

    private func setupMenuBar() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "text.word.spacing",
                accessibilityDescription: "TextFlash"
            )
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10n.t("menu.openSnippets"), action: #selector(openSnippetWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.t("menu.settings"), action: #selector(openSettingsWindow), keyEquivalent: ","))
        let pauseItem = NSMenuItem(title: L10n.t("menu.pause"), action: #selector(togglePaused), keyEquivalent: "")
        menu.addItem(pauseItem)
        pauseMenuItem = pauseItem

        let permissionItem = NSMenuItem(title: L10n.t("menu.permission.check"), action: #selector(checkAccessibilityPermission), keyEquivalent: "")
        menu.addItem(permissionItem)
        permissionMenuItem = permissionItem

        let exclusionItem = NSMenuItem(title: L10n.t("menu.exclude.current"), action: #selector(toggleFocusedAppExclusion), keyEquivalent: "")
        menu.addItem(exclusionItem)
        exclusionMenuItem = exclusionItem
        menu.addItem(NSMenuItem(title: L10n.t("menu.exclusions.manage"), action: #selector(openExclusionsWindow), keyEquivalent: ""))

#if DEBUG
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.t("menu.debug"), action: #selector(openDebugWindow), keyEquivalent: ""))
#endif
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.t("menu.about"), action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.t("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem?.menu = menu
        updateMenuState()
    }

    // MARK: - 片段窗口

    @MainActor @objc private func openSnippetWindow() {
        // 懒加载：打开片段窗口时检查并引导权限
        EventController.shared.startWithPrompt()

        if let existing = snippetWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let manager = SnippetManager()
        let hostingView = NSHostingView(rootView: SnippetManagerView(manager: manager))
        hostingView.frame = NSRect(x: 0, y: 0, width: 700, height: 500)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("window.snippets")
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isReleasedWhenClosed = false  // 关闭时不释放，手动管理生命周期
        window.contentView = hostingView
        window.center()
        window.setFrameAutosaveName("TextFlashSnippetWindow")

        // 监听窗口关闭 → 清空引用，防止下次点击访问悬垂指针
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.snippetWindow = nil
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        snippetWindow = window
    }

    @MainActor @objc private func openSettingsWindow() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 540, height: 520)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
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
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @MainActor @objc private func showAbout() {
        if let existing = aboutWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow = window
    }

    @objc private func togglePaused() {
        EventController.shared.togglePaused()
        updateMenuState()
    }

    @objc private func checkAccessibilityPermission() {
        EventController.shared.requestPermission()
    }

    @objc private func toggleFocusedAppExclusion() {
        guard let app = EventController.shared.toggleExclusionForFocusedApplication() else {
            let alert = NSAlert()
            alert.messageText = L10n.t("alert.focusedApp.missing.title")
            alert.informativeText = L10n.t("alert.focusedApp.missing.message")
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        updateMenuState(focusedApp: app)
    }

    @MainActor @objc private func openExclusionsWindow() {
        if let existing = exclusionsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: ExclusionsView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 320)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("window.exclusions")
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()
        window.setFrameAutosaveName("TextFlashExclusionsWindow")

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.exclusionsWindow = nil
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        exclusionsWindow = window
    }

#if DEBUG
    @MainActor @objc private func openDebugWindow() {
        if let existing = debugWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    @objc private func exclusionsDidChange(_ notification: Notification) {
        updateMenuState()
    }

    @objc private func languageDidChange(_ notification: Notification) {
        setupMenuBar()
        snippetWindow?.title = L10n.t("window.snippets")
        settingsWindow?.title = L10n.t("window.settings")
        exclusionsWindow?.title = L10n.t("window.exclusions")
        aboutWindow?.title = L10n.t("about.title")
#if DEBUG
        debugWindow?.title = L10n.t("window.debug")
#endif
    }

    private func updateMenuState(focusedApp: FocusedApplicationInfo? = nil) {
        let controller = EventController.shared
        pauseMenuItem?.title = controller.isPaused ? L10n.t("menu.resume") : L10n.t("menu.pause")
        permissionMenuItem?.title = controller.checkPermission() ? L10n.t("menu.permission.enabled") : L10n.t("menu.permission.required")
        updateStatusIcon()

        if let app = focusedApp ?? controller.exclusionTargetApplication() {
            let excluded = controller.excludedBundleIDs.contains(app.bundleID)
            let key = excluded ? "menu.unexclude.named" : "menu.exclude.named"
            exclusionMenuItem?.title = String(format: L10n.t(key), app.localizedName)
        } else {
            exclusionMenuItem?.title = L10n.t("menu.exclude.current")
        }
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let paused = EventController.shared.isPaused
        button.image = NSImage(
            systemSymbolName: paused ? "pause.circle" : "text.word.spacing",
            accessibilityDescription: paused ? "TextFlash 已暂停" : "TextFlash"
        )
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateMenuState()
    }
}

struct ExclusionsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var excludedBundleIDs = Array(EventController.shared.excludedBundleIDs).sorted()
    @State private var exclusionErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("exclusions.title"))
                    .font(.headline)
                Spacer()
                Button {
                    addFocusedApplication()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help(L10n.t("exclusions.addCurrent"))

                Button {
                    clearAll()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(excludedBundleIDs.isEmpty)
                .help(L10n.t("exclusions.clear"))
            }
            .padding()

            Divider()

            if excludedBundleIDs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(L10n.t("exclusions.empty"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(excludedBundleIDs, id: \.self) { bundleID in
                        HStack {
                            Text(bundleID)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                remove(bundleID)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .help(L10n.t("exclusions.remove"))
                        }
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .onReceive(NotificationCenter.default.publisher(for: .textFlashExclusionsDidChange)) { _ in
            refreshExclusions()
        }
        .alert(L10n.t("exclusions.addFailed.title"), isPresented: Binding(
            get: { exclusionErrorMessage != nil },
            set: { if !$0 { exclusionErrorMessage = nil } }
        )) {
            Button(L10n.t("common.confirm"), role: .cancel) { exclusionErrorMessage = nil }
        } message: {
            Text(exclusionErrorMessage ?? "")
        }
    }

    private func remove(_ bundleID: String) {
        var exclusions = EventController.shared.excludedBundleIDs
        exclusions.remove(bundleID)
        EventController.shared.excludedBundleIDs = exclusions
    }

    private func addFocusedApplication() {
        guard let app = EventController.shared.exclusionTargetApplication() else {
            exclusionErrorMessage = L10n.t("exclusions.addFailed.message")
            return
        }
        var exclusions = EventController.shared.excludedBundleIDs
        exclusions.insert(app.bundleID)
        EventController.shared.excludedBundleIDs = exclusions
    }

    private func clearAll() {
        EventController.shared.excludedBundleIDs = []
    }

    private func refreshExclusions() {
        excludedBundleIDs = Array(EventController.shared.excludedBundleIDs).sorted()
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
    }
}
