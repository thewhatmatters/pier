import Foundation

/// Containers from `docker ps -a --format '{{json .}}'`.
/// Headline is the container name. Caption is how long a running
/// container has been up (`RunningFor` / `Status`), not CreatedAt.
enum Docker {
    static let desktopBundleID = "com.docker.docker"
    static let hostBundleIDs: Set<String> = [
        "com.docker.docker",
        "com.docker.docker-desktop",
        "com.electron.dockerdesktop"
    ]

    static func isHost(_ app: PinnedApp) -> Bool {
        if hostBundleIDs.contains(app.bundleID) { return true }
        let name = app.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.compare("Docker", options: .caseInsensitive) == .orderedSame
            || name.compare("Docker Desktop", options: .caseInsensitive) == .orderedSame
    }

    static func cliURL(
        fileManager: FileManager = .default,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/usr/local/bin/docker"),
            URL(fileURLWithPath: "/opt/homebrew/bin/docker"),
            home.appendingPathComponent(".docker/bin/docker"),
            URL(fileURLWithPath: "/Applications/Docker.app/Contents/Resources/bin/docker")
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    static func snapshot(
        from data: Data,
        now: Date = Date(),
        available: Bool = true
    ) -> DockerSnapshot {
        DockerSnapshot(
            containers: parse(data, now: now),
            selectedIndex: 0,
            available: available
        )
    }

    static func snapshot(now: Date = Date()) -> DockerSnapshot {
        guard cliURL() != nil else {
            return DockerSnapshot(containers: [], selectedIndex: 0, available: false)
        }
        guard let data = listJSON() else {
            return DockerSnapshot(containers: [], selectedIndex: 0, available: false)
        }
        return snapshot(from: data, now: now, available: true)
    }

    static func parse(_ data: Data, now: Date = Date()) -> [DockerContainer] {
        let rows = decodeRows(data)
        let containers = rows.compactMap { container(from: $0, now: now) }
        return containers.sorted { lhs, rhs in
            if lhs.running != rhs.running { return lhs.running && !rhs.running }
            switch (lhs.startedAt, rhs.startedAt) {
            case let (left?, right?):
                if left != right { return left > right }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func displayName(_ raw: String) -> String {
        let first = raw.split(separator: ",").first.map(String.init) ?? raw
        return first.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

    static func caption(
        running: Bool,
        startedAt: Date?,
        runningFor: String?,
        status: String? = nil,
        now: Date
    ) -> String {
        guard running else { return "Stopped" }
        if let uptime = uptime(runningFor: runningFor, status: status) {
            return uptime
        }
        if let startedAt {
            return "Up \(relative(startedAt, now: now))"
        }
        return "Running"
    }

    static func uptime(runningFor: String?, status: String?) -> String? {
        if let status {
            let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("up ") {
                let rest = trimmed.dropFirst(3)
                let bare = rest.split(separator: "(").first.map(String.init) ?? String(rest)
                return "Up \(compactDuration(bare))"
            }
        }
        if let runningFor {
            let trimmed = runningFor.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return "Up \(compactDuration(trimmed))"
            }
        }
        return nil
    }

    static func compactDuration(_ raw: String) -> String {
        let lower = raw
            .lowercased()
            .replacingOccurrences(of: " ago", with: "")
            .replacingOccurrences(of: "about ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("second") { return "just now" }
        if let number = firstNumber(in: lower) {
            if lower.contains("month") { return "\(number)mo" }
            if lower.contains("week") { return "\(number)w" }
            if lower.contains("day") { return "\(number)d" }
            if lower.contains("hour") { return "\(number)h" }
            if lower.contains("minute") { return "\(number)m" }
        }
        if lower.contains("minute") { return "1m" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstNumber(in text: String) -> Int? {
        var digits = ""
        for character in text where character.isNumber {
            digits.append(character)
        }
        return digits.isEmpty ? nil : Int(digits)
    }

    static func relative(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86_400))d ago"
    }

    static func cycleIndex(_ index: Int, count: Int, by delta: Int) -> Int {
        Agenda.cycleIndex(index, count: count, by: delta)
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let iso = ISO8601DateFormatter.docker.date(from: raw)
            ?? ISO8601DateFormatter().date(from: raw)
        {
            return iso
        }
        for format in createdAtFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        return nil
    }

    private static let createdAtFormats = [
        "yyyy-MM-dd HH:mm:ss ZZZZ",
        "yyyy-MM-dd HH:mm:ss Z",
        "yyyy-MM-dd HH:mm:ss ZZZ",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    ]

    private static func decodeRows(_ data: Data) -> [[String: Any]] {
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let row = trimmed.data(using: .utf8) else { return nil }
                return (try? JSONSerialization.jsonObject(with: row)) as? [String: Any]
            }
    }

    private static func container(from row: [String: Any], now: Date) -> DockerContainer? {
        let id = string(row["ID"]).nilIfEmpty ?? string(row["Id"]).nilIfEmpty
        guard let id else { return nil }
        let name = displayName(string(row["Names"]).nilIfEmpty ?? string(row["Name"]).nilIfEmpty ?? id)
        let state = string(row["State"]).lowercased()
        let running = state == "running" || bool(row["Running"])
        let startedAt = parseDate(string(row["StartedAt"]).nilIfEmpty)
        let runningFor = string(row["RunningFor"]).nilIfEmpty
        let status = string(row["Status"]).nilIfEmpty
        return DockerContainer(
            id: id,
            name: name,
            running: running,
            startedAt: startedAt,
            caption: caption(
                running: running,
                startedAt: startedAt,
                runningFor: runningFor,
                status: status,
                now: now
            )
        )
    }

    private static func listJSON() -> Data? {
        guard let url = cliURL() else { return nil }
        let process = Process()
        process.executableURL = url
        process.arguments = ["ps", "-a", "--format", "{{json .}}"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return data.isEmpty ? Data("[]".utf8) : data
    }

    private static func string(_ value: Any?) -> String {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        default: return ""
        }
    }

    private static func bool(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.boolValue
        default: return false
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension ISO8601DateFormatter {
    static let docker: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct DockerContainer: Equatable, Identifiable {
    var id: String
    var name: String
    var running: Bool
    var startedAt: Date?
    var caption: String

    var headline: String { name }
}

struct DockerSnapshot: Equatable {
    var containers: [DockerContainer]
    var selectedIndex: Int
    var available: Bool

    static let empty = DockerSnapshot(containers: [], selectedIndex: 0, available: false)

    var selected: DockerContainer? {
        guard containers.indices.contains(selectedIndex) else { return containers.first }
        return containers[selectedIndex]
    }

    var pageCount: Int { containers.count }
    var canCycle: Bool { containers.count > 1 }
    var running: [DockerContainer] { containers.filter(\.running) }

    var headline: String { selected?.headline ?? "Docker" }

    var caption: String {
        if let selected { return selected.caption }
        return available ? "No containers" : "Engine off"
    }

    var help: String {
        if containers.isEmpty {
            return available ? "No containers" : "Open Docker Desktop and start the engine"
        }
        return containers.map { item in
            "\(item.name) · \(item.caption)"
        }.joined(separator: "\n")
    }

    func selecting(_ index: Int) -> DockerSnapshot {
        var next = self
        let count = containers.count
        next.selectedIndex = count == 0 ? 0 : ((index % count) + count) % count
        return next
    }
}
