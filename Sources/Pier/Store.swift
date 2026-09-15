import AppKit
import Combine
import EventKit

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var snapshot = DockSnapshot.empty

    private var timer: Timer?
    private var weatherTask: Task<Void, Never>?
    private var agentTask: Task<Void, Never>?
    private var calendarTask: Task<Void, Never>?
    private var lastWeatherFetch = Date.distantPast
    private var lastAgentScan = Date.distantPast
    private var lastCalendarFetch = Date.distantPast
    private var agents = AgentSnapshot(sessions: [])
    private var calendar: CalendarSnapshot?
    private var calendarIndex = 0
    private var weatherPages: [WeatherSnapshot] = []
    private var weatherIndex = 0
    private var grokBot = GrokBotSnapshot(seats: [], selectedIndex: 0, signedIn: false)
    private var grokBotIndex = 0
    private var grokAttentionIDs: Set<String> = []

    private enum Pulse {
        static let dock: TimeInterval = 3
        static let weather: TimeInterval = 15 * 60
        static let agents: TimeInterval = 8
        static let calendar: TimeInterval = 120
    }

    private init() {}

    func start() {
        refresh()
        weatherTask = Task { await refreshWeather() }
        calendarTask = Task { await refreshCalendar() }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarsChanged),
            name: .EKEventStoreChanged,
            object: nil
        )
        timer = Timer.scheduledTimer(withTimeInterval: Pulse.dock, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appsChanged),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appsChanged),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appsChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        weatherTask?.cancel()
        agentTask?.cancel()
        calendarTask?.cancel()
    }

    @objc private func appsChanged() {
        refresh()
    }

    @objc private func calendarsChanged() {
        lastCalendarFetch = .distantPast
        calendarTask = Task { await refreshCalendar() }
    }

    func refresh() {
        if Date().timeIntervalSince(lastWeatherFetch) > Pulse.weather {
            weatherTask = Task { await refreshWeather() }
        }
        if Date().timeIntervalSince(lastAgentScan) > Pulse.agents {
            scanAgents()
        }
        refreshGrokBot()
        if Date().timeIntervalSince(lastCalendarFetch) > Pulse.calendar {
            calendarTask = Task { await refreshCalendar() }
        }
        publish()
    }

    private func scanAgents() {
        lastAgentScan = Date()
        agentTask?.cancel()
        agentTask = Task.detached(priority: .utility) {
            let next = AgentActivity.snapshot()
            await MainActor.run {
                guard !Task.isCancelled else { return }
                Store.shared.applyAgents(next)
            }
        }
    }

    private func applyAgents(_ next: AgentSnapshot) {
        agents = next
        publish()
    }

    private func refreshGrokBot() {
        let next = GrokBot.snapshot()
        let visible = next.visible
        let needingIDs = Set(visible.filter(\.needsAttention).map(\.id))
        let keep = grokBot.selected.flatMap { current in
            visible.firstIndex(where: { $0.id == current.id })
        }
        if needingIDs != grokAttentionIDs, let firstNeed = visible.firstIndex(where: \.needsAttention) {
            grokBot = next.selecting(firstNeed)
        } else if let keep {
            grokBot = next.selecting(keep)
        } else {
            grokBot = next.selecting(next.selectedIndex)
        }
        grokBotIndex = grokBot.selectedIndex
        grokAttentionIDs = needingIDs
    }

    func cycleCalendar(_ delta: Int) {
        let count = calendar?.events.count ?? 0
        guard count > 1 else { return }
        calendarIndex = Agenda.cycleIndex(calendarIndex, count: count, by: delta)
        calendar = calendar?.selecting(calendarIndex)
        publish()
    }

    func cycleWeather(_ delta: Int) {
        guard weatherPages.count > 1 else { return }
        weatherIndex = Agenda.cycleIndex(weatherIndex, count: weatherPages.count, by: delta)
        publish()
    }

    func cycleGrokBot(_ delta: Int) {
        let count = grokBot.visible.count
        guard count > 1 else { return }
        grokBotIndex = GrokBot.cycleIndex(grokBotIndex, count: count, by: delta)
        grokBot = grokBot.selecting(grokBotIndex)
        publish()
    }

    func removeCurrentWeatherPlace() {
        guard weatherPages.indices.contains(weatherIndex) else { return }
        let city = weatherPages[weatherIndex].city
        guard let extra = Settings.shared.weatherPlaces.firstIndex(where: { $0.name == city }) else { return }
        Settings.shared.removeWeatherPlace(at: extra)
        weatherIndex = min(weatherIndex, Settings.shared.weatherPlaces.count)
        lastWeatherFetch = .distantPast
        weatherTask = Task { await refreshWeather() }
    }

    func refreshWeatherPages() {
        lastWeatherFetch = .distantPast
        weatherTask = Task { await refreshWeather() }
    }

    private func publish() {
        let weather = weatherPages.indices.contains(weatherIndex)
            ? weatherPages[weatherIndex]
            : snapshot.weather
        if let snap = calendar, snap.status == .authorized {
            let previous = snap.selected
            let nextCal = Agenda.summarize(events: snap.events, now: Date(), timeZone: snap.timeZone)
            if let previous, let keep = nextCal.events.firstIndex(where: { $0 == previous }) {
                calendar = nextCal.selecting(keep)
                calendarIndex = keep
            } else {
                calendar = nextCal
                calendarIndex = nextCal.selectedIndex
            }
        }
        let pinned = Settings.shared.pinnedApps
        let next = DockSnapshot(
            apps: pinned,
            runningBundleIDs: AppLaunch.runningBundleIDs(),
            badges: DockBadge.labels(for: Set(pinned.map(\.bundleID))),
            cursor: CursorStatus.snapshot(),
            agents: agents,
            calendar: calendar,
            weather: weather,
            weatherCount: weatherPages.count,
            grokBot: grokBot
        )
        if next != snapshot {
            snapshot = next
        }
    }

    private func refreshWeather() async {
        lastWeatherFetch = Date()
        var pages: [WeatherSnapshot] = []
        if let here = await Weather.fetch(target: .here) {
            pages.append(here)
        }
        for place in Settings.shared.weatherPlaces {
            if let page = await Weather.fetch(target: .place(place)) {
                pages.append(page)
            }
        }
        weatherPages = pages
        weatherIndex = pages.isEmpty ? 0 : min(weatherIndex, pages.count - 1)
        publish()
    }

    func refreshCalendarAccess() async {
        lastCalendarFetch = .distantPast
        await refreshCalendar()
    }

    private func refreshCalendar() async {
        lastCalendarFetch = Date()
        let next = await Agenda.fetch()
        calendarIndex = next.events.isEmpty ? 0 : min(calendarIndex, next.events.count - 1)
        calendar = next.selecting(calendarIndex)
        publish()
    }
}
