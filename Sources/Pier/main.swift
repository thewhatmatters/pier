import AppKit
import SwiftUI

Typeface.register()

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run())
}

if CommandLine.arguments.contains("--status") {
    let cursor = CursorStatus.snapshot()
    let agents = AgentActivity.snapshot()
    print("Cursor: \(cursor.running ? "running" : "off")  \(cursor.label)")
    print("Agents: \(agents.caption)  \(agents.working.count) working / \(agents.sessions.count) recent")
    for session in agents.sessions.prefix(8) {
        let age = Int(Date().timeIntervalSince(session.updatedAt))
        let kind = session.kind == .cloud ? "cloud" : "local"
        print("  - \(session.name)  \(session.project)  \(kind)  \(session.isWorking ? "working" : "quiet")  \(age)s ago")
    }
    print("Pinned apps: \(Settings.shared.pinnedApps.map(\.name).joined(separator: ", "))")
    print("Hide macOS Dock: \(Settings.shared.hideSystemDock)")
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
            cursor: CursorSnapshot(running: true, frontmost: true, windowTitle: "DockView.swift — dock"),
            agents: AgentSnapshot(sessions: [
                AgentSession(
                    id: "1",
                    project: "dock",
                    title: "Fold agents into Cursor",
                    kind: .local,
                    updatedAt: Date(),
                    isWorking: true
                )
            ]),
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
            weather: WeatherSnapshot(temperature: 72, condition: "Clear", symbol: "sun.max.fill", city: "Austin", source: "Apple Weather")
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
