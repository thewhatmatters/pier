import AppKit
import CoreGraphics

/// Displays that currently have a fullscreen (or fill-the-screen) window.
/// Used so Pier can step aside for video scrubbers and other chrome.
enum FullscreenDisplays {
    static let slop: CGFloat = 8

    private static let ignoredOwners: Set<String> = [
        "Pier",
        "Dock",
        "Window Server",
        "SystemUIServer",
        "Control Center",
        "Notification Center",
        "Notification Centre",
        "Wallpaper",
        "loginwindow",
        "Spotlight"
    ]

    static func occupiedIDs() -> Set<CGDirectDisplayID> {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ours = pid_t(ProcessInfo.processInfo.processIdentifier)
        var occupied = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            let id = NativeDock.displayID(of: screen)
            let display = CGDisplayBounds(id)
            if info.contains(where: { fills($0, display: display, ignoringPID: ours) }) {
                occupied.insert(id)
            }
        }
        return occupied
    }

    static func windowFills(_ window: CGRect, display: CGRect) -> Bool {
        abs(window.minX - display.minX) <= slop
            && abs(window.minY - display.minY) <= slop
            && abs(window.width - display.width) <= slop
            && abs(window.height - display.height) <= slop
    }

    private static func fills(
        _ window: [String: Any],
        display: CGRect,
        ignoringPID: pid_t
    ) -> Bool {
        if let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid == ignoringPID {
            return false
        }
        if let owner = window[kCGWindowOwnerName as String] as? String,
           ignoredOwners.contains(owner) {
            return false
        }
        let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        guard layer == 0 else { return false }
        let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0.9 else { return false }
        guard let rect = rect(from: window[kCGWindowBounds as String]) else { return false }
        return windowFills(rect, display: display)
    }

    private static func rect(from raw: Any?) -> CGRect? {
        guard let dict = raw as? [String: Any] else { return nil }
        func number(_ key: String) -> CGFloat? {
            if let value = dict[key] as? CGFloat { return value }
            if let value = dict[key] as? NSNumber { return CGFloat(truncating: value) }
            return nil
        }
        guard let x = number("X"), let y = number("Y"),
              let width = number("Width"), let height = number("Height")
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
