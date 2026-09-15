import Foundation

/// Cursor agent sessions, inferred from transcript files.
/// A session is "working" when a transcript was written inside
/// `workingWindow` and the last event is not `turn_ended` — the same
/// idle point Cursor uses. Cloud agents show up when they write locally
/// (`bc-` ids); ones that never touch disk will not appear here.
enum AgentActivity {
    static let workingWindow: TimeInterval = 120
    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cursor/projects", isDirectory: true)

    private static var titleCache: [String: (Date, String)] = [:]

    static func snapshot(
        now: Date = Date(),
        projectsRoot: URL = defaultRoot,
        workingWindow: TimeInterval = workingWindow
    ) -> AgentSnapshot {
        AgentSnapshot(sessions: scan(now: now, projectsRoot: projectsRoot, workingWindow: workingWindow))
    }

    static func scan(
        now: Date = Date(),
        projectsRoot: URL = defaultRoot,
        workingWindow: TimeInterval = workingWindow
    ) -> [AgentSession] {
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
                let working = isLive(
                    lastEvent: lastEvent(in: latest.url),
                    written: latest.date,
                    now: now,
                    workingWindow: workingWindow
                )
                sessions.append(AgentSession(
                    id: id,
                    project: project,
                    title: working ? title(for: group, fallback: project, written: latest.date) : project,
                    kind: kind(fromID: id),
                    updatedAt: latest.date,
                    isWorking: working
                ))
            }
        }

        return sessions
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func projectName(fromSlug slug: String) -> String {
        let marker = "-Development-"
        if let range = slug.range(of: marker, options: .backwards) {
            return String(slug[range.upperBound...])
        }
        return slug
    }

    static func kind(fromID id: String) -> AgentKind {
        id.hasPrefix("bc-") ? .cloud : .local
    }

    static func isLive(
        lastEvent: [String: Any]?,
        written: Date,
        now: Date = Date(),
        workingWindow: TimeInterval = workingWindow
    ) -> Bool {
        guard now.timeIntervalSince(written) <= workingWindow else { return false }
        if lastEvent?["type"] as? String == "turn_ended" { return false }
        return true
    }

    static func title(fromTranscriptPrefix text: String) -> String? {
        guard
            let start = text.range(of: "<user_query>"),
            let end = text.range(of: "</user_query>", range: start.upperBound..<text.endIndex)
        else { return nil }

        let query = unescape(String(text[start.upperBound..<end.lowerBound]))
        let line = query
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !isNoise($0) }
        guard let line, !line.isEmpty else { return nil }
        return shorten(line)
    }

    static func unescape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\r")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    static func isNoise(_ line: String) -> Bool {
        if line.isEmpty { return true }
        if line == "[Image]" { return true }
        if line.hasPrefix("<timestamp") { return true }
        if line.hasPrefix("<image_files>") { return true }
        if line.hasPrefix("http://") || line.hasPrefix("https://") || line.hasPrefix("www.") {
            return true
        }
        return false
    }

    static func shorten(_ text: String, limit: Int = 36) -> String {
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if collapsed.count <= limit { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: limit - 1)
        return String(collapsed[..<end]) + "…"
    }

    private static func title(for group: URL, fallback: String, written: Date) -> String {
        let id = group.lastPathComponent
        if let cached = titleCache[id], cached.0 == written {
            return cached.1
        }
        let file = group.appendingPathComponent("\(id).jsonl")
        let resolved = title(from: file) ?? fallback
        titleCache[id] = (written, resolved)
        return resolved
    }

    private static func title(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 12_000)
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return title(fromTranscriptPrefix: text)
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
