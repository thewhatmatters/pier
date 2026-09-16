import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
        button.toolTip = "Pier"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        PierStatusMenu.populate(
            menu,
            hideDock: Settings.shared.hideSystemDock,
            openAtLogin: LoginItem.isEnabled,
            darkMode: Settings.shared.appearance == .dark,
            needsBadgeAccess: !DockBadge.isAccessTrusted,
            target: self
        )
    }

    @objc func toggleSystemDock() {
        Settings.shared.hideSystemDock.toggle()
        applySystemDockPreference()
        panel.layout()
    }

    @objc func toggleLoginItem() {
        LoginItem.set(!LoginItem.isEnabled)
    }

    @objc func toggleAppearance() {
        Settings.shared.appearance = Settings.shared.appearance == .dark ? .light : .dark
        panel.applyAppearance()
    }

    @objc func allowBadgeAccess() {
        DockBadge.requestAccessFromUser()
        if !DockBadge.isAccessTrusted {
            DockBadge.openAccessSettings()
        }
        Store.shared.refresh()
    }

    @objc func quitPier() {
        restoreSystemDockIfNeeded()
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
        guard Settings.shared.previousSystemDockAutohide == nil else { return }
        let remembered = NativeDock.Chrome.remembered(from: .current)
        Settings.shared.previousSystemDockAutohide = remembered.autohide
        Settings.shared.previousSystemDockAutohideDelay = remembered.delay
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
