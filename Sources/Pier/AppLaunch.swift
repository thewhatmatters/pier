import AppKit
import EventKit

enum AppLaunch {
    static func open(_ app: PinnedApp) {
        let url = app.url
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        if let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            NSWorkspace.shared.openApplication(at: resolved, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func openCursor() {
        if let cursor = NativeDock.application(bundleID: NativeDock.cursorBundleID, fallbackName: "Cursor") {
            open(cursor)
        }
    }

    static func openCalendar() {
        if let calendar = NativeDock.application(bundleID: AppMarks.calendarBundleID, fallbackName: "Calendar") {
            open(calendar)
            return
        }
        if let url = URL(string: "ical://") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    static func handleCalendarTile() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if Agenda.isReadable(status) {
            openCalendar()
            return
        }
        openCalendarSettings()
        Task {
            _ = await Agenda.requestAccessFromUser()
            await Store.shared.refreshCalendarAccess()
        }
    }

    static func openCalendarSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    static func openWeather() {
        if let weather = NativeDock.application(bundleID: "com.apple.weather", fallbackName: "Weather") {
            open(weather)
            return
        }
        if let url = URL(string: "weather://") {
            NSWorkspace.shared.open(url)
        }
    }

    static func icon(for app: PinnedApp) -> NSImage {
        if FileManager.default.fileExists(atPath: app.path) {
            return NSWorkspace.shared.icon(forFile: app.path)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: app.name)
            ?? NSImage()
    }

    static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    static func runningApplication(for app: PinnedApp) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first
    }

    static func hide(_ app: PinnedApp) {
        runningApplication(for: app)?.hide()
    }

    static func quit(_ app: PinnedApp) {
        runningApplication(for: app)?.terminate()
    }

    static func forceQuit(_ app: PinnedApp) {
        runningApplication(for: app)?.forceTerminate()
    }

    static func reveal(_ app: PinnedApp) {
        let url = FileManager.default.fileExists(atPath: app.path)
            ? app.url
            : NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
