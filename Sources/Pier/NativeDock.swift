import AppKit
import Foundation

/// Reads Apple's Dock pins and can hide or restore the system Dock.
/// The interface is "give me the user's apps" and "get the system Dock out
/// of the way" — plist keys and `killall Dock` stay in here.
enum NativeDock {
    static let cursorBundleID = "com.todesktop.230313mzl4w4u92"
    static let grokBotBundleID = GrokBot.bundleID
    static let finderBundleID = "com.apple.finder"

    private static var dockDefaults: UserDefaults? {
        UserDefaults(suiteName: "com.apple.dock")
    }

    static var isAutoHidden: Bool {
        dockDefaults?.bool(forKey: "autohide") ?? false
    }

    /// Seconds before Apple's Dock reveals on a bottom-edge hover.
    /// A large value (set while we are replacing it) keeps the native Dock away.
    static var autohideDelay: Double {
        (dockDefaults?.object(forKey: "autohide-delay") as? NSNumber)?.doubleValue ?? 0
    }

    static let replacementAutohideDelay: Double = 1000

    static func pinnedApps() -> [PinnedApp] {
        let tiles = dockDefaults?.array(forKey: "persistent-apps") ?? []
        var apps: [PinnedApp] = []
        var seen = Set<String>()

        for tile in tiles {
            guard let tile = tile as? [String: Any],
                  let data = tile["tile-data"] as? [String: Any],
                  let bundleID = data["bundle-identifier"] as? String,
                  seen.insert(bundleID).inserted
            else { continue }

            let name = data["file-label"] as? String ?? bundleID
            let path = applicationPath(bundleID: bundleID, tileData: data)
            apps.append(PinnedApp(bundleID: bundleID, name: name, path: path))
        }

        if !seen.contains(cursorBundleID),
           let cursor = application(bundleID: cursorBundleID, fallbackName: "Cursor") {
            apps.insert(cursor, at: min(3, apps.count))
        }
        if !seen.contains(grokBotBundleID),
           let grok = application(bundleID: grokBotBundleID, fallbackName: "Grok Bot") {
            apps.insert(grok, at: min(4, apps.count))
        }

        return withFinder(apps)
    }

    /// Finder is a special Dock item, not a `persistent-apps` pin.
    static func withFinder(_ apps: [PinnedApp]) -> [PinnedApp] {
        if apps.contains(where: { $0.bundleID == finderBundleID }) { return apps }
        guard let finder = application(bundleID: finderBundleID, fallbackName: "Finder") else {
            return apps
        }
        return [finder] + apps
    }

    static func application(bundleID: String, fallbackName: String) -> PinnedApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return PinnedApp(bundleID: bundleID, name: fallbackName, path: url.path)
    }

    /// Physical screen edge that currently hosts Apple's Dock, if any.
    static func hostScreen() -> NSScreen? {
        NSScreen.screens
            .map { ($0, reservedSpace(on: $0)) }
            .filter { $0.1 > 2 }
            .max { $0.1 < $1.1 }?.0
            ?? NSScreen.main
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    static func reservedSpace(on screen: NSScreen) -> CGFloat {
        screen.visibleFrame.minY - screen.frame.minY
    }

    /// Bottom-left origin for a dock of `size` on `screen`.
    /// Floats `screenInset` above the display edge when we have hidden
    /// Apple's Dock; otherwise stacks just above the space macOS reserved.
    static func origin(for size: NSSize, on screen: NSScreen, hidingSystemDock: Bool) -> NSPoint {
        let y: CGFloat
        if hidingSystemDock {
            y = screen.frame.minY + Theme.screenInset
        } else {
            y = screen.visibleFrame.minY + Theme.aboveSystemDock
        }
        let x = (screen.frame.minX + screen.frame.maxX - size.width) / 2
        return NSPoint(x: x.rounded(), y: y.rounded())
    }

    static func setAutoHidden(_ hidden: Bool) {
        applyReplacement(hidden: hidden, restoreAutohide: false, restoreDelay: nil)
    }

    /// Hide Apple's Dock for the life of our overlay, or put it back.
    /// Autohide alone still reveals on a bottom-edge hover, which fights our
    /// tiles — so while replacing we also push the reveal delay far away.
    static func applyReplacement(hidden: Bool, restoreAutohide: Bool, restoreDelay: Double?) {
        if hidden {
            dockDefaults?.set(true, forKey: "autohide")
            dockDefaults?.set(replacementAutohideDelay, forKey: "autohide-delay")
        } else {
            dockDefaults?.set(restoreAutohide, forKey: "autohide")
            if let restoreDelay {
                dockDefaults?.set(restoreDelay, forKey: "autohide-delay")
            } else {
                dockDefaults?.removeObject(forKey: "autohide-delay")
            }
        }
        dockDefaults?.synchronize()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        try? task.run()
    }

    private static func applicationPath(bundleID: String, tileData: [String: Any]) -> String {
        if let file = tileData["file-data"] as? [String: Any],
           let string = file["_CFURLString"] as? String,
           let url = URL(string: string) {
            return url.path
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
            ?? "/Applications/\(tileData["file-label"] as? String ?? "Unknown").app"
    }
}
