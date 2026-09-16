import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Finished Cursor tile: running/off, project label, and working agents.
/// Process/title probing and transcript scanning stay inside.
enum CursorTile {
    fileprivate static let workingWindow: TimeInterval = 120
    fileprivate static let scanInterval: TimeInterval = 8

    fileprivate static var defaultProjectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/projects", isDirectory: true)
    }

    fileprivate static var defaultWorkspaceStorage: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage", isDirectory: true)
    }

    private static var lastScan = Date.distantPast
    private static var cachedSessions: [AgentSession] = []

    /// Live tile for Store and `--status`. Transcripts may be reused for `scanInterval`.
    static func snapshot() -> CursorSnapshot {
        let now = Date()
        return makeSnapshot(
            now: now,
            running: Host.isRunning(),
            windowTitle: Host.frontWindowTitle(),
            projectsRoot: defaultProjectsRoot,
            workspaceStorage: defaultWorkspaceStorage,
            throttle: true
        )
    }

    /// Fixture entry for SelfTest. Always rescans `projectsRoot`.
    static func snapshot(
        now: Date,
        running: Bool,
        windowTitle: String?,
        projectsRoot: URL,
        workspaceStorage: URL? = nil
    ) -> CursorSnapshot {
        makeSnapshot(
            now: now,
            running: running,
            windowTitle: windowTitle,
            projectsRoot: projectsRoot,
            workspaceStorage: workspaceStorage,
            throttle: false
        )
    }

    private static func makeSnapshot(
        now: Date,
        running: Bool,
        windowTitle: String?,
        projectsRoot: URL,
        workspaceStorage: URL?,
        throttle: Bool
    ) -> CursorSnapshot {
        let sessions: [AgentSession]
        if throttle, now.timeIntervalSince(lastScan) <= scanInterval {
            sessions = cachedSessions
        } else {
            sessions = Transcripts.scan(now: now, projectsRoot: projectsRoot)
            if throttle {
                cachedSessions = sessions
                lastScan = now
            }
        }
        let project = Host.projectName(fromWindowTitle: windowTitle)
            ?? workspaceStorage.flatMap { Host.lastWorkspaceName(in: $0) }
        return CursorSnapshot(running: running, project: project, sessions: sessions)
    }
}

struct CursorSnapshot: Equatable {
    var running: Bool
    var project: String?
    var sessions: [AgentSession]

    var label: String {
        if !running { return "Off" }
        if let project { return project }
        return "Cursor"
    }

    var working: [AgentSession] { sessions.filter(\.isWorking) }
    var attention: Bool { !working.isEmpty }

    /// Repos with a live turn, first seen first. Never a leftover prompt.
    var workingProjects: [String] {
        var seen = Set<String>()
        return working.compactMap { session in
            seen.insert(session.project).inserted ? session.project : nil
        }
    }

    var caption: String {
        let repos = workingProjects
        switch repos.count {
        case 0: return "Quiet"
        case 1: return repos[0]
        default:
            let joined = repos.joined(separator: ", ")
            return joined.count <= 28 ? joined : "\(repos.count) repos"
        }
    }

    var help: String {
        var lines: [String] = []
        if running, let project {
            lines.append("In \(project)")
        } else if running {
            lines.append("Cursor is running")
        } else {
            lines.append("Cursor is off")
        }
        if working.isEmpty {
            lines.append("No agents writing right now")
        } else {
            lines.append(contentsOf: working.map { session in
                let kind = session.kind == .cloud ? "cloud" : "local"
                return "\(session.project) · \(kind)"
            })
        }
        return lines.joined(separator: "\n")
    }
}

enum AgentKind: String, Equatable {
    case local
    case cloud
}

struct AgentSession: Equatable, Identifiable {
    var id: String
    var project: String
    var title: String
    var kind: AgentKind
    var updatedAt: Date
    var isWorking: Bool

    var name: String { project }
}

// MARK: - Host app / title

private enum Host {
    private static let genericTitles: Set<String> = ["Cursor", "Welcome", "Untitled"]

    static func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: NativeDock.cursorBundleID
        ).isEmpty
    }

    static func frontWindowTitle() -> String? {
        let pid = NSRunningApplication.runningApplications(
            withBundleIdentifier: NativeDock.cursorBundleID
        ).first?.processIdentifier
        if let title = cgWindowTitle(), projectName(fromWindowTitle: title) != nil {
            return title
        }
        if let title = axWindowTitle(pid: pid), projectName(fromWindowTitle: title) != nil {
            return title
        }
        if let title = cgWindowTitle(), !title.isEmpty { return title }
        if let title = axWindowTitle(pid: pid), !title.isEmpty { return title }
        return nil
    }

    /// Cursor titles look like `DockView.swift — pier-app` or `pier-app`.
    static func projectName(fromWindowTitle title: String?) -> String? {
        guard let title else { return nil }
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

    static func lastWorkspaceName(in directory: URL) -> String? {
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

// MARK: - Transcripts

private enum Transcripts {
    static func scan(now: Date, projectsRoot: URL) -> [AgentSession] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var sessions: [AgentSession] = []
        for projectURL in projects {
            let transcripts = projectURL.appendingPathComponent("agent-transcripts", isDirectory: true)
            guard let groups = try? fm.contentsOfDirectory(
                at: transcripts,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let project = projectName(fromSlug: projectURL.lastPathComponent)
            for group in groups where group.hasDirectoryPath {
                guard let latest = latestWrite(in: group, fm: fm) else { continue }
                let id = group.lastPathComponent
                let working = isLive(lastEvent: lastEvent(in: latest.url), written: latest.date, now: now)
                sessions.append(AgentSession(
                    id: id,
                    project: project,
                    title: project,
                    kind: id.hasPrefix("bc-") ? .cloud : .local,
                    updatedAt: latest.date,
                    isWorking: working
                ))
            }
        }

        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func projectName(fromSlug slug: String) -> String {
        let marker = "-Development-"
        if let range = slug.range(of: marker, options: .backwards) {
            return String(slug[range.upperBound...])
        }
        return slug
    }

    private static func isLive(lastEvent: [String: Any]?, written: Date, now: Date) -> Bool {
        guard now.timeIntervalSince(written) <= CursorTile.workingWindow else { return false }
        if lastEvent?["type"] as? String == "turn_ended" { return false }
        return true
    }

    private static func lastEvent(in url: URL) -> [String: Any]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let tail = min(size, 16_384)
        if size > tail {
            try? handle.seek(toOffset: UInt64(size - tail))
        }
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let payload = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
            else { continue }
            return object
        }
        return nil
    }

    private static func latestWrite(in directory: URL, fm: FileManager) -> (date: Date, url: URL)? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey, .isDirectoryKey]
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var latest: (date: Date, url: URL)?
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: keys)
            if values?.isRegularFile == true, entry.pathExtension == "jsonl" {
                if let date = values?.contentModificationDate, date > (latest?.date ?? .distantPast) {
                    latest = (date, entry)
                }
                continue
            }
            guard entry.lastPathComponent == "subagents", values?.isDirectory == true else { continue }
            let subs = (try? fm.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for sub in subs where sub.pathExtension == "jsonl" {
                let written = try? sub.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                if let written, written > (latest?.date ?? .distantPast) {
                    latest = (written, sub)
                }
            }
        }
        return latest
    }
}
