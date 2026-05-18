import SwiftUI
import AppKit

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var snippetWindow: NSWindow?
    private var debugWindow: NSWindow?

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
        menu.addItem(NSMenuItem(title: "调试面板…", action: #selector(openDebugWindow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "关于 TextFlash", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "退出 TextFlash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    // MARK: - 片段窗口

    @objc private func openSnippetWindow() {
        // 懒加载：打开片段窗口时检查并引导权限
        EventController.shared.startWithPrompt()

        Task { @MainActor in
            if let existing = snippetWindow, existing.isVisible {
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
            window.contentView = hostingView
            window.center()
            window.setFrameAutosaveName("TextFlashSnippetWindow")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            snippetWindow = window
        }
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openDebugWindow() {
        Task { @MainActor in
            if let existing = debugWindow, existing.isVisible {
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
            window.contentView = hostingView
            window.center()
            window.setFrameAutosaveName("TextFlashDebugWindow")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            debugWindow = window
        }
    }

    // MARK: - EventController 同步

    private func loadSnippetsIntoController() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Luigi/TextFlash/data/snippets.json")
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(SnippetStore.self, from: data)
        else { return }

        EventController.shared.removeAllSnippets()
        for group in store.groups {
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
