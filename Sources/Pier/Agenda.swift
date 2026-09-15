import AppKit
import EventKit
import Foundation

struct CalendarEvent: Equatable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
}

struct CalendarSnapshot: Equatable {
    enum Status: Equatable {
        case authorized
        case denied
        case unknown
    }

    var status: Status
    var events: [CalendarEvent]
    var selectedIndex: Int
    var help: String
    var idleCaption: String?
    var now: Date = Date()
    var timeZone: TimeZone = .current

    var count: Int { events.count }
    var canCycle: Bool { events.count > 1 }
    var selected: CalendarEvent? {
        events.indices.contains(selectedIndex) ? events[selectedIndex] : nil
    }

    var headline: String {
        if status != .authorized { return "Calendar" }
        return selected?.title ?? "Free"
    }

    var caption: String {
        if let idleCaption { return idleCaption }
        guard let event = selected else { return "No events" }
        let page = canCycle ? " · \(selectedIndex + 1)/\(count)" : ""
        if event.isAllDay { return "All day\(page)" }
        if event.start <= now && now < event.end {
            return "Now · \(Agenda.format(event.end, timeZone: timeZone))\(page)"
        }
        return "\(Agenda.format(event.start, timeZone: timeZone))\(page)"
    }

    func selecting(_ index: Int) -> CalendarSnapshot {
        var next = self
        next.selectedIndex = events.isEmpty ? 0 : min(max(0, index), events.count - 1)
        return next
    }

    static let unknown = CalendarSnapshot(
        status: .unknown,
        events: [],
        selectedIndex: 0,
        help: "Checking calendars…",
        idleCaption: "…"
    )

    static let denied = CalendarSnapshot(
        status: .denied,
        events: [],
        selectedIndex: 0,
        help: "Click to open Calendar access in System Settings",
        idleCaption: "Off"
    )

    static let needsAccess = CalendarSnapshot(
        status: .unknown,
        events: [],
        selectedIndex: 0,
        help: "Click to allow Pier to read today’s events",
        idleCaption: "Allow"
    )
}

enum Agenda {
    private static var store = EKEventStore()

    static func summarize(
        events: [CalendarEvent],
        now: Date,
        timeZone: TimeZone = .current
    ) -> CalendarSnapshot {
        let visible = droppingElapsed(events, now: now)
        return CalendarSnapshot(
            status: .authorized,
            events: visible,
            selectedIndex: initialIndex(in: visible, now: now),
            help: visible.isEmpty ? "No events on the calendar today" : help(for: visible, timeZone: timeZone),
            idleCaption: nil,
            now: now,
            timeZone: timeZone
        )
    }

    static func authorizationDescription() -> String {
        let status = EKEventStore.authorizationStatus(for: .event)
        if isReadable(status) { return "authorized" }
        if isDenied(status) { return "denied" }
        return "not-determined"
    }

    @MainActor
    static func fetch(now: Date = Date()) async -> CalendarSnapshot {
        let status = EKEventStore.authorizationStatus(for: .event)
        if isDenied(status) { return .denied }
        guard isReadable(status) else { return .needsAccess }
        let range = dayRange(containing: now)
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        let mapped = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map { event in
                CalendarEvent(
                    title: (event.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Event",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay
                )
            }
            .sorted { $0.start < $1.start }
        return summarize(events: mapped, now: now)
    }

    /// Timed events drop once they end. All-day items stay until the day rolls over.
    static func droppingElapsed(_ events: [CalendarEvent], now: Date) -> [CalendarEvent] {
        events.filter { $0.isAllDay || $0.end > now }
    }

    static func initialIndex(in events: [CalendarEvent], now: Date) -> Int {
        if let index = events.firstIndex(where: { !$0.isAllDay && $0.start <= now && now < $0.end }) {
            return index
        }
        if let index = events.firstIndex(where: { !$0.isAllDay && $0.start > now }) {
            return index
        }
        if let index = events.firstIndex(where: \.isAllDay) {
            return index
        }
        return 0
    }

    static func cycleIndex(_ index: Int, count: Int, by delta: Int) -> Int {
        guard count > 0 else { return 0 }
        let step = delta % count
        return (index + step + count) % count
    }

    static func dayRange(containing now: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    static func format(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func help(for events: [CalendarEvent], timeZone: TimeZone) -> String {
        events.prefix(8).map { event in
            if event.isAllDay { return "\(event.title) · all day" }
            return "\(event.title) · \(format(event.start, timeZone: timeZone))"
        }.joined(separator: "\n")
    }

    static func isReadable(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    static func isDenied(_ status: EKAuthorizationStatus) -> Bool {
        status == .denied || status == .restricted
    }

    /// Must run from a click. Accessory apps do not get a calendar prompt
    /// from a background launch; macOS needs the app active.
    @MainActor
    static func requestAccessFromUser() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if isReadable(status) { return true }
        if isDenied(status) { return false }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            granted = false
        }
        NSApp.setActivationPolicy(.accessory)
        if granted {
            store = EKEventStore()
        }
        return granted
    }
}
