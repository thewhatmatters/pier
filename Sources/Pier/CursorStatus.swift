import AppKit
import CoreGraphics

enum CursorStatus {
    static func snapshot() -> CursorSnapshot {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: NativeDock.cursorBundleID
        )
        let app = running.first
        guard app != nil else {
            return CursorSnapshot(running: false, frontmost: false, windowTitle: nil)
        }
        return CursorSnapshot(
            running: true,
            frontmost: app?.isActive ?? false,
            windowTitle: frontWindowTitle()
        )
    }

    /// Cursor titles look like `DockView.swift — dock` or just `dock`.
    static func projectName(fromWindowTitle title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let emDash = trimmed.range(of: " — ") {
            return String(trimmed[emDash.upperBound...])
        }
        if let hyphen = trimmed.range(of: " - ") {
            return String(trimmed[hyphen.upperBound...])
        }
        return trimmed
    }

    private static func frontWindowTitle() -> String? {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        let titles: [String] = info.compactMap { window in
            let owner = window[kCGWindowOwnerName as String] as? String
            guard owner == "Cursor" else { return nil }
            let title = window[kCGWindowName as String] as? String
            guard let title, !title.isEmpty else { return nil }
            return title
        }
        return titles.first
    }
}
