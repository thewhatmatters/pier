import AppKit
import SwiftUI

Typeface.register()

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run())
}

if CommandLine.arguments.contains("--status") {
    let cursor = CursorTile.snapshot()
    print("Cursor: \(cursor.running ? "running" : "off")  \(cursor.label)")
    print("Agents: \(cursor.caption)  \(cursor.working.count) working / \(cursor.sessions.count) recent")
    for session in cursor.sessions.prefix(8) {
        let age = Int(Date().timeIntervalSince(session.updatedAt))
        let kind = session.kind == .cloud ? "cloud" : "local"
        print("  - \(session.name)  \(session.project)  \(kind)  \(session.isWorking ? "working" : "quiet")  \(age)s ago")
    }
    let grok = GrokBot.snapshot()
    print("Grok Bot: \(grok.signedIn ? "signed in" : "signed out")  \(grok.working.count) working / \(grok.visible.count) seats")
    for seat in grok.visible.prefix(8) {
        let age = seat.lastActivityAt.map { Int(Date().timeIntervalSince($0)) }
        let state = seat.isWorking ? "working" : (seat.needsAttention ? "needs you" : "quiet")
        let ageLabel = age.map { "\($0)s ago" } ?? "unknown"
        print("  - \(seat.name)  \(state)  \(ageLabel)")
    }
    print("Pinned apps: \(Settings.shared.pinnedApps.map(\.name).joined(separator: ", "))")
    let badges = DockBadge.labels(for: Set(Settings.shared.pinnedApps.map(\.bundleID)))
    if badges.isEmpty {
        print("Badges: none")
    } else {
        print("Badges:")
        for app in Settings.shared.pinnedApps {
            guard let raw = badges[app.bundleID], let mark = DockBadge.mark(from: raw) else { continue }
            print("  - \(app.name)  \(raw)  \(String(describing: mark))")
        }
    }
    print("Hide macOS Dock: \(Settings.shared.hideSystemDock)")
    print("Badge access: \(DockBadge.isAccessTrusted ? "trusted" : "needs Accessibility")")
    print("Calendar access: \(Agenda.authorizationDescription())")
    _ = NSApplication.shared
    print("Displays: \(NSScreen.screens.count)")
    for screen in NSScreen.screens {
        print("  - \(screen.localizedName)  id=\(NativeDock.displayID(of: screen))")
    }
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--render"),
   let directory = CommandLine.arguments.dropFirst(index + 1).first {
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let snapshot = DockSnapshot(
            apps: [
                PinnedApp(bundleID: "com.apple.mail", name: "Mail", path: "/System/Applications/Mail.app"),
                PinnedApp(bundleID: "com.apple.iCal", name: "Calendar", path: "/System/Applications/Calendar.app"),
                PinnedApp(bundleID: "com.apple.Safari", name: "Safari", path: "/System/Cryptexes/App/System/Applications/Safari.app"),
                PinnedApp(bundleID: NativeDock.cursorBundleID, name: "Cursor", path: "/Applications/Cursor.app")
            ],
            runningBundleIDs: [NativeDock.cursorBundleID],
            cursor: CursorSnapshot(
                running: true,
                project: "dock",
                sessions: [
                    AgentSession(
                        id: "1",
                        project: "dock",
                        title: "Fold agents into Cursor",
                        kind: .local,
                        updatedAt: Date(),
                        isWorking: true
                    )
                ]
            ),
            calendar: Agenda.summarize(
                events: [
                    CalendarEvent(
                        title: "Design review",
                        start: Date().addingTimeInterval(3600),
                        end: Date().addingTimeInterval(7200),
                        isAllDay: false
                    )
                ],
                now: Date()
            ),
            weather: WeatherSnapshot(temperature: 72, high: 81, low: 65, condition: "Clear", symbol: "sun.max.fill", city: "Austin", source: "Apple Weather"),
            grokBot: GrokBotSnapshot(
                seats: [
                    GrokBotSeat(
                        id: "1",
                        name: "Design Engineer",
                        title: "",
                        shape: .hex,
                        tint: .named("black"),
                        isWorking: true,
                        needsAttention: false,
                        unreadCount: 0,
                        isHidden: false,
                        isGroup: false,
                        lastActivityAt: Date()
                    )
                ],
                selectedIndex: 0,
                signedIn: true
            )
        )
        let renderer = ImageRenderer(content: DockView(snapshot: snapshot).padding(24))
        renderer.scale = 2
        if let image = renderer.nsImage,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("dock.png")
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: directory), withIntermediateDirectories: true)
            try? data.write(to: url)
            print("wrote \(url.path)  \(Int(image.size.width))x\(Int(image.size.height))")
        } else {
            print("render failed")
        }
    }
    exit(0)
}

let bundleID = Bundle.main.bundleIdentifier ?? "so.whatmatters.pier"
if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    NSLog("Pier: another instance is already running.")
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
