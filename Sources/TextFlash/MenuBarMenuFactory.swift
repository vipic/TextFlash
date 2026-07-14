import Cocoa

struct MenuBarMenuActions {
    let openSnippets: Selector
    let checkUpdates: Selector
    let openSettings: Selector
    let addUnicodeCurrent: Selector
    let quit: Selector
    let openDebug: Selector?
}

struct MenuBarMenuBuildResult {
    let menu: NSMenu
    let updateItem: NSMenuItem
}

enum MenuBarMenuFactory {
    static func build(
        target: AnyObject,
        actions: MenuBarMenuActions,
        includeDebug: Bool = false
    ) -> MenuBarMenuBuildResult {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(item(
            title: L10n.t("menu.openSnippets"),
            action: actions.openSnippets,
            target: target,
            symbolName: "text.alignleft"
        ))
        menu.addItem(.separator())

        let updatesItem = item(
            title: L10n.t("menu.checkUpdates"),
            action: actions.checkUpdates,
            target: target,
            symbolName: "arrow.triangle.2.circlepath"
        )
        menu.addItem(updatesItem)

        menu.addItem(item(
            title: L10n.t("menu.settings"),
            action: actions.openSettings,
            target: target,
            symbolName: "gearshape",
            keyEquivalent: ",",
            keyEquivalentModifierMask: .command
        ))

        menu.addItem(item(
            title: L10n.t("menu.unicode.addCurrent"),
            action: actions.addUnicodeCurrent,
            target: target,
            symbolName: "character.textbox"
        ))

        menu.addItem(.separator())

#if DEBUG
        if includeDebug, let openDebug = actions.openDebug {
            menu.addItem(item(
                title: L10n.t("menu.debug"),
                action: openDebug,
                target: target,
                symbolName: "ladybug"
            ))
            menu.addItem(.separator())
        }
#else
        _ = includeDebug
#endif

        menu.addItem(item(
            title: L10n.t("menu.quit"),
            action: actions.quit,
            target: target,
            symbolName: "power",
            keyEquivalent: "q",
            keyEquivalentModifierMask: .command
        ))

        return MenuBarMenuBuildResult(menu: menu, updateItem: updatesItem)
    }

    private static func item(
        title: String,
        action: Selector?,
        target: AnyObject,
        symbolName: String,
        keyEquivalent: String = "",
        keyEquivalentModifierMask: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        menuItem.keyEquivalentModifierMask = keyEquivalentModifierMask
        menuItem.target = target
        menuItem.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        return menuItem
    }
}
