import Foundation

/// Grok Bot seats from the desktop app's last roster cache.
/// Live `isRunning` is not stored there, so a seat is working when its
/// `lastActivityAt` is inside `workingWindow`, or when a gateway-shaped
/// row already carries `isRunning` / `isComposingMessage`.
enum GrokBot {
    static let bundleID = "com.anysphere.sand"
    static let workingWindow: TimeInterval = 120

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Grok Bot", isDirectory: true)
    }

    static var persistenceDirectory: URL {
        supportDirectory.appendingPathComponent("sand-client-persistence", isDirectory: true)
    }

    static func snapshot(
        now: Date = Date(),
        persistence: URL = persistenceDirectory,
        support: URL = supportDirectory,
        workingWindow: TimeInterval = workingWindow
    ) -> GrokBotSnapshot {
        let files = rosterFiles(in: persistence)
        let preferred = lastAgentID(in: persistence)
        var seats: [GrokBotSeat] = []
        if let newest = files.max(by: { $0.mtime < $1.mtime }),
           let data = try? Data(contentsOf: newest.url) {
            seats = parseRoster(data, now: now, workingWindow: workingWindow)
        }
        let visible = seats.filter(\.isListed)
        let selected = preferredIndex(in: visible, lastID: preferred)
        return GrokBotSnapshot(
            seats: seats,
            selectedIndex: visible.isEmpty ? 0 : min(selected, visible.count - 1),
            signedIn: isSignedIn(support: support)
        )
    }

    static func parseRoster(
        _ data: Data,
        now: Date = Date(),
        workingWindow: TimeInterval = workingWindow
    ) -> [GrokBotSeat] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let rows = rosterRows(in: root)
        return rows.compactMap { seat(from: $0, now: now, workingWindow: workingWindow) }
    }

    static func isWorking(
        lastActivityAt: Date?,
        isRunning: Bool,
        isComposing: Bool,
        now: Date = Date(),
        workingWindow: TimeInterval = workingWindow
    ) -> Bool {
        if isRunning || isComposing { return true }
        guard let lastActivityAt else { return false }
        return now.timeIntervalSince(lastActivityAt) <= workingWindow
    }

    static func faceShape(from raw: String?) -> GrokBotFace.Shape {
        GrokBotFace.Shape.parse(raw)
    }

    static func faceTint(from raw: String?, name: String) -> GrokBotFace.Tint {
        GrokBotFace.Tint.parse(raw, name: name)
    }

    static func fallbackTintIndex(for name: String, modulo: Int) -> Int {
        guard modulo > 0 else { return 0 }
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return sum % modulo
    }

    static func cycleIndex(_ index: Int, count: Int, by delta: Int) -> Int {
        Agenda.cycleIndex(index, count: count, by: delta)
    }

    static func preferredIndex(in seats: [GrokBotSeat], lastID: String?) -> Int {
        if let index = seats.firstIndex(where: \.needsAttention) { return index }
        if let index = seats.firstIndex(where: \.isWorking) { return index }
        if let index = index(of: lastID, in: seats) { return index }
        return 0
    }

    private static func rosterRows(in root: Any) -> [[String: Any]] {
        if let array = root as? [[String: Any]] { return array }
        guard let object = root as? [String: Any] else { return [] }
        if let rows = object["rows"] as? [[String: Any]] { return rows }
        if let agents = object["agents"] as? [[String: Any]] { return agents }
        if let value = object["value"] {
            return rosterRows(in: value)
        }
        return []
    }

    private static func seat(
        from row: [String: Any],
        now: Date,
        workingWindow: TimeInterval
    ) -> GrokBotSeat? {
        let id = string(row["id"])
        let name = string(row["name"])
        guard !id.isEmpty, !name.isEmpty else { return nil }
        let lastActivity = date(row["lastActivityAt"]) ?? date(row["updatedAt"])
        let running = bool(row["isRunning"]) || bool(row["isRunningTurn"])
        let composing = bool(row["isComposingMessage"])
        let awaiting = row["awaitingUserResponse"] != nil && !(row["awaitingUserResponse"] is NSNull)
        return GrokBotSeat(
            id: id,
            name: name,
            title: string(row["title"]),
            shape: faceShape(from: string(row["avatarShape"])),
            tint: faceTint(from: string(row["avatarColor"]), name: name),
            isWorking: isWorking(
                lastActivityAt: lastActivity,
                isRunning: running,
                isComposing: composing,
                now: now,
                workingWindow: workingWindow
            ),
            needsAttention: awaiting || bool(row["hasUnread"]) || int(row["unreadCount"]) > 0,
            unreadCount: int(row["unreadCount"]),
            isHidden: bool(row["isHiddenFromSidebar"]),
            isGroup: bool(row["isGroup"]),
            lastActivityAt: lastActivity
        )
    }

    private static func rosterFiles(in directory: URL) -> [(url: URL, mtime: Date)] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items.compactMap { url in
            let size = fileSize(url)
            guard url.pathExtension == "blob",
                  size > 800, size < 80_000,
                  let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  isRoster(data)
            else { return nil }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
                .flatMap(\.contentModificationDate) ?? .distantPast
            return (url, mtime)
        }
    }

    private static func isRoster(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return false }
        return !rosterRows(in: root).isEmpty
    }

    private static func lastAgentID(in directory: URL) -> String? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var newest: (Date, String)?
        for url in items where url.pathExtension == "blob" {
            guard fileSize(url) < 400,
                  let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let value = root["value"] as? [String: Any],
                  value["draft"] == nil, value["rows"] == nil, value["entries"] == nil,
                  let id = string(value["agentId"]).nilIfEmpty
            else { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
                .flatMap(\.contentModificationDate) ?? .distantPast
            if newest == nil || mtime > newest!.0 {
                newest = (mtime, id)
            }
        }
        return newest?.1
    }

    private static func index(of id: String?, in seats: [GrokBotSeat]) -> Int? {
        guard let id else { return nil }
        return seats.firstIndex { $0.id == id }
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    private static func isSignedIn(support: URL) -> Bool {
        let url = support.appendingPathComponent("desktop-status.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return bool(root["signedIn"])
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

    private static func int(_ value: Any?) -> Int {
        switch value {
        case let number as Int: return number
        case let number as NSNumber: return number.intValue
        default: return 0
        }
    }

    private static func date(_ value: Any?) -> Date? {
        let millis: Double
        switch value {
        case let number as Double: millis = number
        case let number as Int: millis = Double(number)
        case let number as NSNumber: millis = number.doubleValue
        default: return nil
        }
        guard millis > 1_000_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct GrokBotSeat: Equatable, Identifiable {
    var id: String
    var name: String
    var title: String
    var shape: GrokBotFace.Shape
    var tint: GrokBotFace.Tint
    var isWorking: Bool
    var needsAttention: Bool
    var unreadCount: Int
    var isHidden: Bool
    var isGroup: Bool
    var lastActivityAt: Date?

    var isListed: Bool { !isHidden && !isGroup }
    var headline: String { name }

    var caption: String {
        if needsAttention { return "Needs you" }
        if isWorking { return title.isEmpty ? "Working" : title }
        return title.isEmpty ? "Quiet" : title
    }
}

struct GrokBotSnapshot: Equatable {
    var seats: [GrokBotSeat]
    var selectedIndex: Int
    var signedIn: Bool

    var visible: [GrokBotSeat] { seats.filter(\.isListed) }

    var selected: GrokBotSeat? {
        let pages = visible
        guard pages.indices.contains(selectedIndex) else { return pages.first }
        return pages[selectedIndex]
    }

    var pageCount: Int { visible.count }
    var canCycle: Bool { visible.count > 1 }
    var working: [GrokBotSeat] { visible.filter(\.isWorking) }
    var needingAttention: [GrokBotSeat] { visible.filter(\.needsAttention) }
    var needsAttention: Bool { !needingAttention.isEmpty }

    var help: String {
        let pages = visible
        if pages.isEmpty {
            return signedIn ? "No Grok Bots in the roster" : "Open Grok Bot and sign in"
        }
        return pages.map { seat in
            var line = seat.name
            if !seat.title.isEmpty { line += " · \(seat.title)" }
            if seat.isWorking { line += " · working" }
            else if seat.needsAttention { line += " · needs you" }
            return line
        }.joined(separator: "\n")
    }

    func selecting(_ index: Int) -> GrokBotSnapshot {
        var next = self
        let count = visible.count
        next.selectedIndex = count == 0 ? 0 : ((index % count) + count) % count
        return next
    }
}

enum GrokBotFace {
    enum Shape: String, Equatable {
        case circle
        case oval
        case pill
        case hex
        case cloud
        case teardrop
        case pebble
        case triangle
        case square

        static func parse(_ raw: String?) -> Shape {
            switch (raw ?? "").lowercased() {
            case "hex", "hexagon": return .hex
            case "cloud": return .cloud
            case "teardrop", "drop": return .teardrop
            case "pebble", "blob": return .pebble
            case "oval", "ellipse": return .oval
            case "pill", "capsule": return .pill
            case "triangle": return .triangle
            case "square", "rounded-square", "squircle": return .square
            case "circle", "": return .circle
            default: return .circle
            }
        }
    }

    enum Tint: Equatable {
        case named(String)
        case fallback(Int)

        static let names = ["black", "violet", "red", "orange", "yellow", "green", "blue", "pink", "white"]

        static func parse(_ raw: String?, name: String) -> Tint {
            let key = (raw ?? "").lowercased()
            if names.contains(key) { return .named(key) }
            return .fallback(GrokBot.fallbackTintIndex(for: name, modulo: names.count))
        }
    }
}
