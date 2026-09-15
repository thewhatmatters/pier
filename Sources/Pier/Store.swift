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
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
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
        if Date().timeIntervalSince(lastWeatherFetch) > 600 {
            weatherTask = Task { await refreshWeather() }
        }
        if Date().timeIntervalSince(lastAgentScan) > 8 {
            scanAgents()
        }
        if Date().timeIntervalSince(lastCalendarFetch) > 120 {
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
            weatherCount: weatherPages.count
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
