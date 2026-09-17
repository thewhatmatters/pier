import Foundation

struct PinnedApp: Codable, Equatable, Identifiable {
    var bundleID: String
    var name: String
    var path: String

    var id: String { bundleID }
    var url: URL { URL(fileURLWithPath: path) }
}

struct WeatherSnapshot: Equatable {
    var temperature: Int
    var high: Int? = nil
    var low: Int? = nil
    var condition: String
    var symbol: String
    var city: String
    var source: String

    var label: String { "\(temperature)°" }
    var highLabel: String? { high.map { "\($0)°" } }
    var lowLabel: String? { low.map { "\($0)°" } }
    var hasRange: Bool { high != nil && low != nil }
}

struct DockSnapshot: Equatable {
    var apps: [PinnedApp]
    var runningBundleIDs: Set<String>
    var badges: [String: String] = [:]
    var cursor: CursorSnapshot
    var calendar: CalendarSnapshot?
    var weather: WeatherSnapshot?
    var weatherCount: Int = 1
    var grokBot: GrokBotSnapshot?
    var docker: DockerSnapshot? = nil
    var cpu: CPULoadSnapshot? = nil

    static let empty = DockSnapshot(
        apps: [],
        runningBundleIDs: [],
        badges: [:],
        cursor: CursorSnapshot(running: false, project: nil, sessions: []),
        calendar: nil,
        weather: nil,
        grokBot: nil,
        docker: nil,
        cpu: nil
    )
}
