import Cocoa
import Testing
@testable import TextFlash

@MainActor
@Suite struct MenuBarMenuFactoryTests {
    @Test func buildCreatesExpectedMenuItems() {
        let result = makeMenu()

        let titles = result.menu.items
            .filter { !$0.isSeparatorItem }
            .map(\.title)

        #expect(titles == [
            L10n.t("menu.openSnippets"),
            L10n.t("menu.checkUpdates"),
            L10n.t("menu.settings"),
            L10n.t("menu.unicode.addCurrent"),
            L10n.t("menu.quit"),
        ])
    }

    @Test func keyboardShortcutsAreConfigured() {
        let result = makeMenu()
        let settingsItem = item(titled: L10n.t("menu.settings"), in: result.menu)
        let quitItem = item(titled: L10n.t("menu.quit"), in: result.menu)

        #expect(settingsItem?.keyEquivalent == ",")
        #expect(settingsItem?.keyEquivalentModifierMask == .command)
        #expect(quitItem?.keyEquivalent == "q")
        #expect(quitItem?.keyEquivalentModifierMask == .command)
    }

    @Test func statusItemClickRouting() {
        #expect(MenuBarManager.shouldOpenMenu(for: .rightMouseUp))
        #expect(!MenuBarManager.shouldOpenMenu(for: .leftMouseUp))
        #expect(!MenuBarManager.shouldOpenMenu(for: nil))
    }

    @Test func menuHasTwoSeparatorsAndFiveActions() {
        let menu = makeMenu().menu
        let separators = menu.items.filter(\.isSeparatorItem)
        let actions = menu.items.filter { !$0.isSeparatorItem }
        #expect(separators.count == 2)
        #expect(actions.count == 5)
        #expect(menu.items.count == 7)
    }

    @Test func menuItemsHaveTargetsAndSymbols() {
        let target = DummyMenuTarget()
        let menu = MenuBarMenuFactory.build(
            target: target,
            actions: MenuBarMenuActions(
                openSnippets: #selector(DummyMenuTarget.openSnippets),
                checkUpdates: #selector(DummyMenuTarget.checkUpdates),
                openSettings: #selector(DummyMenuTarget.openSettings),
                addUnicodeCurrent: #selector(DummyMenuTarget.addUnicode),
                quit: #selector(DummyMenuTarget.quit),
                openDebug: nil
            )
        ).menu

        for item in menu.items where !item.isSeparatorItem {
            #expect(item.target === target)
            #expect(item.action != nil)
            #expect(item.image != nil, "菜单项应有 SF Symbol 图标: \(item.title)")
        }
    }

    @Test func menuAutoenablesItemsIsDisabled() {
        #expect(!makeMenu().menu.autoenablesItems)
    }

    private func makeMenu() -> MenuBarMenuBuildResult {
        MenuBarMenuFactory.build(
            target: DummyMenuTarget(),
            actions: MenuBarMenuActions(
                openSnippets: #selector(DummyMenuTarget.openSnippets),
                checkUpdates: #selector(DummyMenuTarget.checkUpdates),
                openSettings: #selector(DummyMenuTarget.openSettings),
                addUnicodeCurrent: #selector(DummyMenuTarget.addUnicode),
                quit: #selector(DummyMenuTarget.quit),
                openDebug: nil
            )
        )
    }

    private func item(titled title: String, in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.title == title }
    }
}

private final class DummyMenuTarget: NSObject {
    @objc func openSnippets() {}
    @objc func checkUpdates() {}
    @objc func openSettings() {}
    @objc func addUnicode() {}
    @objc func quit() {}
}
