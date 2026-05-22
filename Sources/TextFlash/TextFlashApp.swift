import SwiftUI
import AppKit

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var snippetWindow: NSWindow?
    private var debugWindow: NSWindow?
    private var exclusionsWindow: NSWindow?
    private var pauseMenuItem: NSMenuItem?
    private var permissionMenuItem: NSMenuItem?
    private var exclusionMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement：隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        setupMenuBar()
        loadSnippetsIntoController()
        EventController.shared.start()

        // 监听片段变更 → 实时重载匹配表
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(snippetsDidChange),
            name: .textFlashSnippetsDidChange,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        EventController.shared.stop()
    }

    // MARK: - 菜单栏

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "text.word.spacing",
                accessibilityDescription: "TextFlash"
            )
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开片段管理…", action: #selector(openSnippetWindow), keyEquivalent: ""))
        let pauseItem = NSMenuItem(title: "暂停展开", action: #selector(togglePaused), keyEquivalent: "")
        menu.addItem(pauseItem)
        pauseMenuItem = pauseItem

        let permissionItem = NSMenuItem(title: "检查辅助功能权限", action: #selector(checkAccessibilityPermission), keyEquivalent: "")
        menu.addItem(permissionItem)
        permissionMenuItem = permissionItem

        let exclusionItem = NSMenuItem(title: "排除当前应用", action: #selector(toggleFocusedAppExclusion), keyEquivalent: "")
        menu.addItem(exclusionItem)
        exclusionMenuItem = exclusionItem
        menu.addItem(NSMenuItem(title: "管理排除列表…", action: #selector(openExclusionsWindow), keyEquivalent: ""))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "调试面板…", action: #selector(openDebugWindow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "关于 TextFlash", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "退出 TextFlash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem?.menu = menu
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
        window.title = "TextFlash — 片段管理"
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

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func togglePaused() {
        EventController.shared.togglePaused()
        updateMenuState()
    }

    @objc private func checkAccessibilityPermission() {
        if EventController.shared.checkPermission() {
            let alert = NSAlert()
            alert.messageText = "辅助功能权限已启用"
            alert.informativeText = "TextFlash 可以监听键盘事件并展开文本。"
            alert.alertStyle = .informational
            alert.runModal()
        } else {
            EventController.shared.requestPermission()
        }
    }

    @objc private func toggleFocusedAppExclusion() {
        guard let app = EventController.shared.toggleExclusionForFocusedApplication() else {
            let alert = NSAlert()
            alert.messageText = "无法识别当前应用"
            alert.informativeText = "请切回目标应用后再从菜单栏切换排除状态。"
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
        window.title = "TextFlash — 排除列表"
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

    @MainActor @objc private func openDebugWindow() {
        if let existing = debugWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: DebugPanel())
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 420)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TextFlash — 调试面板"
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

    private func updateMenuState(focusedApp: FocusedApplicationInfo? = nil) {
        let controller = EventController.shared
        pauseMenuItem?.title = controller.isPaused ? "恢复展开" : "暂停展开"
        permissionMenuItem?.title = controller.checkPermission() ? "辅助功能权限：已启用" : "辅助功能权限：需要启用"

        if let app = focusedApp ?? controller.focusedApplicationInfo() {
            let excluded = controller.excludedBundleIDs.contains(app.bundleID)
            exclusionMenuItem?.title = excluded ? "取消排除 \(app.localizedName)" : "排除 \(app.localizedName)"
        } else {
            exclusionMenuItem?.title = "排除当前应用"
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateMenuState()
    }
}

struct ExclusionsView: View {
    @State private var excludedBundleIDs = Array(EventController.shared.excludedBundleIDs).sorted()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("排除列表")
                    .font(.headline)
                Spacer()
                Button {
                    addFocusedApplication()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("添加当前应用")

                Button {
                    clearAll()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(excludedBundleIDs.isEmpty)
                .help("清空排除列表")
            }
            .padding()

            Divider()

            if excludedBundleIDs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("没有被排除的应用")
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
                            .help("从排除列表移除")
                        }
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    private func remove(_ bundleID: String) {
        var exclusions = EventController.shared.excludedBundleIDs
        exclusions.remove(bundleID)
        EventController.shared.excludedBundleIDs = exclusions
        excludedBundleIDs = Array(exclusions).sorted()
    }

    private func addFocusedApplication() {
        guard let app = EventController.shared.focusedApplicationInfo() else { return }
        var exclusions = EventController.shared.excludedBundleIDs
        exclusions.insert(app.bundleID)
        EventController.shared.excludedBundleIDs = exclusions
        excludedBundleIDs = Array(exclusions).sorted()
    }

    private func clearAll() {
        EventController.shared.excludedBundleIDs = []
        excludedBundleIDs = []
    }
}

// MARK: - App 入口

@main
struct TextFlashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
