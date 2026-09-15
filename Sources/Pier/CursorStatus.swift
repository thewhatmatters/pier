import AppKit
import ApplicationServices
import CoreGraphics

enum CursorStatus {
    static var workspaceStorage: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage", isDirectory: true)
    }

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
            windowTitle: frontWindowTitle(pid: app?.processIdentifier)
        )
    }

    /// Cursor titles look like `DockView.swift — pier-app` or `pier-app`.
    static func projectName(fromWindowTitle title: String) -> String? {
        var trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("●") {
            trimmed = trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for suffix in [" — Cursor", " - Cursor"] where trimmed.hasSuffix(suffix) {
            trimmed = String(trimmed.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let emDash = trimmed.range(of: " — ", options: .backwards) {
            trimmed = String(trimmed[emDash.upperBound...])
        } else if let hyphen = trimmed.range(of: " - ", options: .backwards) {
            trimmed = String(trimmed[hyphen.upperBound...])
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || genericTitles.contains(trimmed) { return nil }
        return trimmed
    }

    static func lastWorkspaceName(in directory: URL = workspaceStorage) -> String? {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (Date, String)?
        for child in children {
            let file = child.appendingPathComponent("workspace.json")
            guard let data = try? Data(contentsOf: file),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = workspaceName(from: root)
            else { continue }
            let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))
                .flatMap(\.contentModificationDate) ?? .distantPast
            if newest == nil || mtime > newest!.0 {
                newest = (mtime, name)
            }
        }
        return newest?.1
    }

    private static let genericTitles: Set<String> = ["Cursor", "Welcome", "Untitled"]

    private static func frontWindowTitle(pid: pid_t?) -> String? {
        if let title = cgWindowTitle(), projectName(fromWindowTitle: title) != nil {
            return title
        }
        if let title = axWindowTitle(pid: pid), projectName(fromWindowTitle: title) != nil {
            return title
        }
        if let title = cgWindowTitle(), !title.isEmpty { return title }
        if let title = axWindowTitle(pid: pid), !title.isEmpty { return title }
        return lastWorkspaceName()
    }

    private static func cgWindowTitle() -> String? {
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

    private static func axWindowTitle(pid: pid_t?) -> String? {
        guard AXIsProcessTrusted(), let pid else { return nil }
        let app = AXUIElementCreateApplication(pid)
        if let window = copyElement(app, kAXFocusedWindowAttribute as CFString),
           let title = windowTitle(from: window) {
            return title
        }
        guard let windows = copyArray(app, kAXWindowsAttribute as CFString) else { return nil }
        for window in windows {
            if let title = windowTitle(from: window) { return title }
        }
        return nil
    }

    private static func windowTitle(from window: AXUIElement) -> String? {
        if let title = copyString(window, kAXTitleAttribute as CFString),
           projectName(fromWindowTitle: title) != nil {
            return title
        }
        if let document = copyString(window, kAXDocumentAttribute as CFString),
           let name = folderName(fromPath: document) {
            return name
        }
        if let title = copyString(window, kAXTitleAttribute as CFString), !title.isEmpty {
            return title
        }
        return nil
    }

    private static func workspaceName(from root: [String: Any]) -> String? {
        if let folder = root["folder"] as? String { return folderName(fromPath: folder) }
        if let workspace = root["workspace"] as? String { return folderName(fromPath: workspace) }
        return nil
    }

    private static func folderName(fromPath raw: String) -> String? {
        let path: String
        if raw.hasPrefix("file:") {
            path = URL(string: raw)?.path ?? raw
        } else {
            path = raw
        }
        var name = URL(fileURLWithPath: path).lastPathComponent
        if name.hasSuffix(".code-workspace") {
            name = String(name.dropLast(".code-workspace".count))
        }
        if name.isEmpty || genericTitles.contains(name) { return nil }
        return name
    }

    private static func copyString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return (value as! AXUIElement)
    }

    private static func copyArray(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement]? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }
}
