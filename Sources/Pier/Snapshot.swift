import Foundation

struct PinnedApp: Codable, Equatable, Identifiable {
    var bundleID: String
    var name: String
    var path: String

    var id: String { bundleID }
    var url: URL { URL(fileURLWithPath: path) }
}

struct CursorSnapshot: Equatable {
    var running: Bool
    var frontmost: Bool
    var windowTitle: String?

    var project: String? {
        guard let windowTitle, !windowTitle.isEmpty else { return nil }
        return CursorStatus.projectName(fromWindowTitle: windowTitle)
    }

    var label: String {
        if !running { return "Off" }
        if let project { return project }
        return "Cursor"
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

    var name: String { title.isEmpty ? project : title }
}

struct AgentSnapshot: Equatable {
    var sessions: [AgentSession]

    var working: [AgentSession] { sessions.filter(\.isWorking) }

    var caption: String {
        switch working.count {
        case 0: return "Quiet"
        case 1: return working[0].name
        default:
            let joined = working.map(\.name).joined(separator: ", ")
            return joined.count <= 28 ? joined : "\(working.count) agents"
        }
    }

    var help: String {
        if working.isEmpty { return "No agents writing right now" }
        return working.map { session in
            let kind = session.kind == .cloud ? "cloud" : "local"
            return "\(session.name) · \(session.project) · \(kind)"
        }.joined(separator: "\n")
    }
}

struct WeatherSnapshot: Equatable {
    var temperature: Int
    var condition: String
    var symbol: String
    var city: String
    var source: String

    var label: String { "\(temperature)°" }
}

struct DockSnapshot: Equatable {
    var apps: [PinnedApp]
    var runningBundleIDs: Set<String>
    var cursor: CursorSnapshot
    var agents: AgentSnapshot
    var calendar: CalendarSnapshot?
    var weather: WeatherSnapshot?
    var weatherCount: Int = 1

    static let empty = DockSnapshot(
        apps: [],
        runningBundleIDs: [],
        cursor: CursorSnapshot(running: false, frontmost: false, windowTitle: nil),
        agents: AgentSnapshot(sessions: []),
        calendar: nil,
        weather: nil
    )
}
