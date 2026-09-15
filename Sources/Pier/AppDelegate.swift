import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let panel = DockPanel()
    private var layoutObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Store.shared.start()
        LoginItem.refreshIfMoved()
        applySystemDockPreference()
        setUpStatusItem()
        panel.show()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            DockBadge.promptAccessIfNeeded()
        }

        layoutObserver = NotificationCenter.default.addObserver(
            forName: .pierNeedsLayout,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.layout() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Store.shared.stop()
        restoreSystemDockIfNeeded()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "rectangle.bottomhalf.inset.filled",
                            accessibilityDescription: "Pier")
        image?.isTemplate = true
        button.image = image
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        showMenu(from: sender)
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()

        let hide = NSMenuItem(
            title: "Hide macOS Dock",
            action: #selector(toggleSystemDock),
            keyEquivalent: ""
        )
        hide.target = self
        hide.state = Settings.shared.hideSystemDock ? .on : .off
        menu.addItem(hide)

        let login = NSMenuItem(
            title: "Open at Login",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        let dark = NSMenuItem(
            title: "Dark Mode",
            action: #selector(toggleAppearance),
            keyEquivalent: ""
        )
        dark.target = self
        dark.state = Settings.shared.appearance == .dark ? .on : .off
        menu.addItem(dark)

        if !DockBadge.isAccessTrusted {
            let badges = NSMenuItem(
                title: "Allow Messages Badges…",
                action: #selector(allowBadgeAccess),
                keyEquivalent: ""
            )
            badges.target = self
            menu.addItem(badges)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Pier", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleSystemDock() {
        Settings.shared.hideSystemDock.toggle()
        applySystemDockPreference()
        panel.layout()
    }

    @objc private func toggleLoginItem() {
        LoginItem.set(!LoginItem.isEnabled)
    }

    @objc private func toggleAppearance() {
        Settings.shared.appearance = Settings.shared.appearance == .dark ? .light : .dark
        panel.applyAppearance()
    }

    @objc private func allowBadgeAccess() {
        DockBadge.requestAccessFromUser()
        if !DockBadge.isAccessTrusted {
            DockBadge.openAccessSettings()
        }
        Store.shared.refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func applySystemDockPreference() {
        if Settings.shared.hideSystemDock {
            rememberSystemDock()
            NativeDock.applyReplacement(
                hidden: true,
                restoreAutohide: false,
                restoreDelay: nil
            )
        } else {
            restoreSystemDockIfNeeded()
        }
    }

    private func rememberSystemDock() {
        if Settings.shared.previousSystemDockAutohide == nil {
            Settings.shared.previousSystemDockAutohide = NativeDock.isAutoHidden
        }
        if Settings.shared.previousSystemDockAutohideDelay == nil {
            Settings.shared.previousSystemDockAutohideDelay = NativeDock.autohideDelay
        }
    }

    private func restoreSystemDockIfNeeded() {
        guard Settings.shared.hideSystemDock || Settings.shared.previousSystemDockAutohide != nil else { return }
        NativeDock.applyReplacement(
            hidden: false,
            restoreAutohide: Settings.shared.previousSystemDockAutohide ?? false,
            restoreDelay: Settings.shared.previousSystemDockAutohideDelay
        )
        if !Settings.shared.hideSystemDock {
            Settings.shared.previousSystemDockAutohide = nil
            Settings.shared.previousSystemDockAutohideDelay = nil
        }
    }
}
