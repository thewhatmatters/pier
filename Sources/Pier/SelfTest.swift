import AppKit
import Foundation

enum SelfTest {
    static func run() -> Int32 {
        var failures = 0

        func check(_ name: String, _ ok: Bool) {
            print(ok ? "  PASS  \(name)" : "  FAIL  \(name)")
            if !ok { failures += 1 }
        }

        check("clear sky label", Weather.condition(for: 0) == "Clear")
        check("rain label", Weather.condition(for: 61) == "Rain")
        check("unknown weather", Weather.condition(for: 1234) == "Weather")
        check("clear symbol", Weather.symbol(for: 0) == "sun.max.fill")

        let forecast = """
        {"current":{"temperature_2m":72.4,"weather_code":2}}
        """.data(using: .utf8)!
        let weather = try? Weather.snapshot(from: forecast, city: "Austin")
        check("forecast decode", weather?.temperature == 72 && weather?.condition == "Partly cloudy" && weather?.source == "Open-Meteo")
        check("fill symbol", Weather.filledSymbol("sun.max") == "sun.max.fill")
        check("already filled symbol", Weather.filledSymbol("cloud.fill") == "cloud.fill")

        let ip = """
        {"success":true,"latitude":30.27,"longitude":-97.74,"city":"Austin"}
        """.data(using: .utf8)!
        let location = try? Weather.location(from: ip)
        check("ip location", location?.city == "Austin" && location?.latitude == 30.27)

        check("slug after Development", AgentActivity.projectName(fromSlug: "Users-digitalalchemist-Development-dock") == "dock")
        check("slug studio", AgentActivity.projectName(fromSlug: "Users-digitalalchemist-Development-whatmatters-studio") == "whatmatters-studio")
        check("slug without marker", AgentActivity.projectName(fromSlug: "empty-window") == "empty-window")

        check("window title project", CursorStatus.projectName(fromWindowTitle: "DockView.swift — dock") == "dock")
        check("plain window title", CursorStatus.projectName(fromWindowTitle: "dock") == "dock")

        let now = Date()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pier-selftest-\(UUID().uuidString)", isDirectory: true)
        let session = root
            .appendingPathComponent("Users-me-Development-dock/agent-transcripts/aaaa", isDirectory: true)
        try? FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let file = session.appendingPathComponent("aaaa.jsonl")
        try? """
        <user_query>
        Build the dock overlay
        </user_query>
        """.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)

        let working = AgentActivity.scan(now: now, projectsRoot: root, workingWindow: 120)
        check("working session detected", working.count == 1 && working[0].isWorking && working[0].project == "dock")
        check("working session has a title", working[0].title == "Build the dock overlay")
        check("cloud ids are marked cloud", AgentActivity.kind(fromID: "bc-abc123") == .cloud)
        check("uuid ids are local", AgentActivity.kind(fromID: "aaaa") == .local)
        check(
            "title from first prompt",
            AgentActivity.title(fromTranscriptPrefix: "<user_query>\nFold agents into Cursor\n</user_query>") == "Fold agents into Cursor"
        )
        check(
            "title skips a leading URL",
            AgentActivity.title(fromTranscriptPrefix: "<user_query>\\nhttps://dockset.app\\nWhat should Pier show?</user_query>") == "What should Pier show?"
        )
        check(
            "URL-only prompt has no title",
            AgentActivity.title(fromTranscriptPrefix: "<user_query>\nhttps://dockset.app\n</user_query>") == nil
        )
        check(
            "quiet caption",
            AgentSnapshot(sessions: []).caption == "Quiet"
        )

        let stale = AgentActivity.scan(
            now: now.addingTimeInterval(400),
            projectsRoot: root,
            workingWindow: 120
        )
        check("stale session is quiet", stale.count == 1 && stale[0].isWorking == false)
        try? FileManager.default.removeItem(at: root)

        if let screen = NSScreen.main {
            let hidden = NativeDock.origin(for: NSSize(width: 100, height: 72), on: screen, hidingSystemDock: true)
            let shown = NativeDock.origin(for: NSSize(width: 100, height: 72), on: screen, hidingSystemDock: false)
            check("hidden dock sits on screen edge", hidden.y == (screen.frame.minY + Theme.screenInset).rounded())
            check("visible dock sits above system dock", shown.y == (screen.visibleFrame.minY + Theme.aboveSystemDock).rounded())
            let expectedX = ((screen.frame.minX + screen.frame.maxX - 100) / 2).rounded()
            check("origin centers on that screen", hidden.x == expectedX)
            let metrics = Theme.metrics(tileSize: 36)
            let items = (0..<13).map { StripItem.app("app.\($0)") } + WidgetKind.standard.map(StripItem.widget)
            let widthA = metrics.stripWidth(items: items)
            let widthB = metrics.stripWidth(items: items)
            check("strip width is stable", widthA == widthB && widthA > 400)
            let window = metrics.windowSize(items: items, maxWidth: 10_000)
            check("window leaves room for the bar shadow", window.width > widthA && window.height > metrics.dockHeight)
            check("replacement delay is long", NativeDock.replacementAutohideDelay >= 1000)
            check("each screen has a display id", NativeDock.displayID(of: screen) != 0)
            let ids = NSScreen.screens.map(NativeDock.displayID(of:))
            check("display ids are unique", Set(ids).count == ids.count)
            check("Finder is a known pin", NativeDock.finderBundleID == "com.apple.finder")
            let withFinder = NativeDock.withFinder([])
            check("Finder is prepended when missing", withFinder.first?.bundleID == NativeDock.finderBundleID)
            let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            check(
                "fullscreen window fills its display",
                FullscreenDisplays.windowFills(display, display: display)
            )
            check(
                "windowed chrome is not fullscreen",
                FullscreenDisplays.windowFills(
                    CGRect(x: 0, y: 25, width: 1920, height: 1055),
                    display: display
                ) == false
            )
        } else {
            check("screen available for origin math", false)
        }

        let small = Theme.metrics(tileSize: 24)
        let large = Theme.metrics(tileSize: 72)
        check("larger tiles make a taller dock", large.dockHeight > small.dockHeight)
        check("larger tiles make larger icons", large.iconSize > small.iconSize)
        check("app icons match widget height", small.iconSize == small.widgetInnerHeight && large.iconSize == large.widgetInnerHeight)
        check("running mark is a 2pt bottom tab", small.runningMarkHeight == 2 && small.runningMarkRadius == 2)
        check("clamp high", Theme.clampedTile(400) == Theme.maxTileSize)
        check("clamp low", Theme.clampedTile(1) == Theme.minTileSize)
        check("corner radius is 16", Theme.cornerRadius == 16)
        check("widget type is at least 12pt", Theme.metrics(tileSize: 24).widgetFont >= 12)
        check("widget islands are squarish", Theme.widgetRadius == 14)
        check("dark and light palettes exist", Theme.Appearance.allCases.count == 2)
        check("halftone renders a symbol", Halftone.image(systemName: "cloud.fill", pointSize: 24).size.width > 0)
        check("calendar day is numeric", Int(AppMarks.calendarDay()) != nil)
        check("widget order fills missing", WidgetKind.normalized([.weather]) == [.weather, .cursor, .calendar])
        check("widget order drops dupes", WidgetKind.normalized([.cursor, .cursor, .weather]) == [.cursor, .weather, .calendar])
        let safari = PinnedApp(bundleID: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app")
        let mail = PinnedApp(bundleID: "com.apple.mail", name: "Mail", path: "/System/Applications/Mail.app")
        let mixed: [StripItem] = [.app(safari.bundleID), .widget(.cursor), .app(mail.bundleID), .widget(.weather)]
        check(
            "strip keeps interleave and fills widgets",
            StripItem.normalized(mixed, apps: [safari, mail]) == [
                .app(safari.bundleID), .widget(.cursor), .app(mail.bundleID), .widget(.weather), .widget(.calendar)
            ]
        )
        let metrics = Theme.metrics(tileSize: 36)
        let trio: [StripItem] = [.app(safari.bundleID), .app(mail.bundleID), .widget(.cursor)]
        check(
            "no drag keeps slot",
            StripLayout.destinationIndex(translationX: 0, startIndex: 2, items: trio, metrics: metrics) == 2
        )
        check(
            "widget can land between apps",
            StripLayout.destinationIndex(translationX: -120, startIndex: 2, items: trio, metrics: metrics) == 1
        )
        check(
            "app can land after a widget",
            StripLayout.destinationIndex(translationX: 400, startIndex: 0, items: trio, metrics: metrics) == 2
        )
        Typeface.register()
        check("Geist is registered", Typeface.isAvailable(Typeface.sansName))
        check("Geist Mono is registered", Typeface.isAvailable(Typeface.monoName))
        let sample = PinnedApp(bundleID: "com.apple.Safari", name: "Safari", path: "/System/Cryptexes/App/System/Applications/Safari.app")
        let controller = AppMenuController(app: sample)
        let runningMenu = AppIconMenu.make(app: sample, running: true, controller: controller)
        let titles = runningMenu.items.map(\.title)
        check("app menu can quit", titles.contains("Quit") || titles.contains("Force Quit"))
        check("app menu can hide", titles.contains("Hide"))
        check("app menu can reveal", titles.contains("Show in Finder"))
        let hideItem = runningMenu.items.first { $0.title == "Hide" }
        check("hide is enabled while running", hideItem?.isEnabled == true)
        let idleMenu = AppIconMenu.make(app: sample, running: false, controller: controller)
        let idleHide = idleMenu.items.first { $0.title == "Hide" }
        check("hide is disabled while idle", idleHide?.isEnabled == false)

        let tz = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let day = calendar.date(from: DateComponents(timeZone: tz, year: 2026, month: 9, day: 15, hour: 0))!
        let noon = calendar.date(byAdding: .hour, value: 14, to: day)!
        let review = CalendarEvent(
            title: "Design review",
            start: calendar.date(byAdding: .hour, value: 15, to: day)!,
            end: calendar.date(byAdding: .hour, value: 16, to: day)!,
            isAllDay: false
        )
        let standup = CalendarEvent(
            title: "Standup",
            start: calendar.date(byAdding: .hour, value: 13, to: day)!,
            end: calendar.date(byAdding: .hour, value: 15, to: day)!,
            isAllDay: false
        )
        let upcoming = Agenda.summarize(events: [review], now: noon, timeZone: tz)
        check("upcoming event is next", upcoming.headline == "Design review")
        let current = Agenda.summarize(events: [standup, review], now: noon, timeZone: tz)
        check("in-progress event is now", current.headline == "Standup" && current.caption.hasPrefix("Now"))
        let empty = Agenda.summarize(events: [], now: noon, timeZone: tz)
        check("empty day is free", empty.headline == "Free")
        check("cycle wraps forward", Agenda.cycleIndex(2, count: 3, by: 1) == 0)
        check("cycle wraps backward", Agenda.cycleIndex(0, count: 3, by: -1) == 2)
        check("cycled event is the next one", current.selecting(1).headline == "Design review")
        let range = Agenda.dayRange(containing: noon, calendar: calendar)
        check("day range is 24 hours", range.end.timeIntervalSince(range.start) == 86_400)

        print(failures == 0 ? "\nPASS" : "\nFAIL — \(failures) checks")
        return failures == 0 ? 0 : 1
    }
}
