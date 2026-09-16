import AppKit

enum PierStatusMenu {
    static let hideDock = "Hide macOS Dock"
    static let openAtLogin = "Open at Login"
    static let darkMode = "Dark Mode"
    static let badgeAccess = "Allow Messages Badges…"
    static let quit = "Quit Pier"

    static func populate(
        _ menu: NSMenu,
        hideDock: Bool,
        openAtLogin: Bool,
        darkMode: Bool,
        needsBadgeAccess: Bool,
        target: AnyObject
    ) {
        menu.removeAllItems()

        add(
            menu,
            title: Self.hideDock,
            action: #selector(AppDelegate.toggleSystemDock),
            target: target,
            state: hideDock ? .on : .off
        )
        add(
            menu,
            title: Self.openAtLogin,
            action: #selector(AppDelegate.toggleLoginItem),
            target: target,
            state: openAtLogin ? .on : .off
        )
        add(
            menu,
            title: Self.darkMode,
            action: #selector(AppDelegate.toggleAppearance),
            target: target,
            state: darkMode ? .on : .off
        )
        if needsBadgeAccess {
            add(
                menu,
                title: Self.badgeAccess,
                action: #selector(AppDelegate.allowBadgeAccess),
                target: target
            )
        }
        menu.addItem(.separator())
        add(menu, title: Self.quit, action: #selector(AppDelegate.quitPier), target: target, key: "q")
    }

    static func titles(
        hideDock: Bool = true,
        openAtLogin: Bool = false,
        darkMode: Bool = true,
        needsBadgeAccess: Bool = false
    ) -> [String] {
        let menu = NSMenu()
        let target = NSObject()
        populate(
            menu,
            hideDock: hideDock,
            openAtLogin: openAtLogin,
            darkMode: darkMode,
            needsBadgeAccess: needsBadgeAccess,
            target: target
        )
        return menu.items.map(\.title)
    }

    private static func add(
        _ menu: NSMenu,
        title: String,
        action: Selector,
        target: AnyObject,
        state: NSControl.StateValue = .off,
        key: String = ""
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        item.state = state
        menu.addItem(item)
    }
}
