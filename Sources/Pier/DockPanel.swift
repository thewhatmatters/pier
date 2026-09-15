import AppKit
import Combine
import SwiftUI

final class DockWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: Theme.metrics(tileSize: Theme.defaultTileSize).dockHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        // Stay on every desktop, but not over fullscreen spaces — otherwise
        // the strip sits on video scrubbers and other bottom chrome.
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        appearance = Settings.shared.appearance.nsAppearance
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DockPanel {
    private struct Instance {
        var displayID: CGDirectDisplayID
        var window: DockWindow
        var hosting: NSHostingView<DockRoot>
    }

    private var instances: [Instance] = []
    private var observers: [NSObjectProtocol] = []
    private var clickMonitor: Any?
    private var fullscreenTimer: Timer?

    func show() {
        syncScreens()
        observeScreenChanges()
        observeFullscreen()
        observeRightClicks()
    }

    func layout() {
        syncScreens()
        applyAppearance()
    }

    func applyAppearance() {
        let appearance = Settings.shared.appearance.nsAppearance
        for instance in instances {
            instance.window.appearance = appearance
        }
    }

    /// One window per connected display. Adding or removing a monitor
    /// creates or tears down that display's strip.
    private func syncScreens() {
        let screens = NSScreen.screens
        let wanted = Set(screens.map(NativeDock.displayID(of:)))

        instances.removeAll { instance in
            guard !wanted.contains(instance.displayID) else { return false }
            instance.window.orderOut(nil)
            return true
        }

        for screen in screens {
            let id = NativeDock.displayID(of: screen)
            if let existing = instances.first(where: { $0.displayID == id }) {
                layout(existing, on: screen)
            } else {
                let created = makeInstance(displayID: id)
                instances.append(created)
                layout(created, on: screen)
            }
        }
        applyFullscreenVisibility()
    }

    private func layout(_ instance: Instance, on screen: NSScreen) {
        let metrics = Settings.shared.metrics
        let size = metrics.windowSize(
            items: Settings.shared.stripOrder,
            maxWidth: screen.frame.width - 40
        )
        var origin = NativeDock.origin(
            for: size,
            on: screen,
            hidingSystemDock: Settings.shared.hideSystemDock
        )
        origin.y -= metrics.shadowBleed
        let frame = NSRect(origin: origin, size: size)
        let current = instance.window.frame
        guard abs(current.origin.x - frame.origin.x) > 0.5
            || abs(current.origin.y - frame.origin.y) > 0.5
            || abs(current.size.width - frame.size.width) > 0.5
            || abs(current.size.height - frame.size.height) > 0.5
        else { return }
        let sizeChanged = abs(current.size.width - frame.size.width) > 2
            || abs(current.size.height - frame.size.height) > 2
        if sizeChanged, current.width > 40 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Theme.layoutDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                instance.window.animator().setFrame(frame, display: true)
            }
        } else {
            instance.window.setFrame(frame, display: true)
        }
    }

    private func makeInstance(displayID: CGDirectDisplayID) -> Instance {
        let window = DockWindow()
        let hosting = NSHostingView(rootView: DockRoot())
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = .clear
        window.contentView = hosting
        return Instance(displayID: displayID, window: window, hosting: hosting)
    }

    private func observeRightClicks() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { event in
            guard event.window is DockWindow else { return event }
            guard let catcher = TileClickCatcher.located(at: event.locationInWindow, in: event.window)
            else { return event }
            catcher.pop(event)
            return nil
        }
    }

    private func observeScreenChanges() {
        guard observers.isEmpty else { return }
        observers = [
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncScreens() }
            }
        ]
    }

    private func observeFullscreen() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(contentsOf: [
            workspace.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyFullscreenVisibility() }
            },
            workspace.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyFullscreenVisibility() }
            }
        ])
        guard fullscreenTimer == nil else { return }
        fullscreenTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyFullscreenVisibility() }
        }
        fullscreenTimer?.tolerance = 0.2
    }

    private func applyFullscreenVisibility() {
        let occupied = FullscreenDisplays.occupiedIDs()
        for instance in instances {
            if occupied.contains(instance.displayID) {
                if instance.window.isVisible {
                    instance.window.orderOut(nil)
                }
            } else if !instance.window.isVisible {
                instance.window.orderFrontRegardless()
            }
        }
    }
}

struct DockRoot: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var settings = Settings.shared

    private var liveSnapshot: DockSnapshot {
        var snapshot = store.snapshot
        snapshot.apps = settings.pinnedApps
        return snapshot
    }

    var body: some View {
        DockView(
            snapshot: liveSnapshot,
            metrics: settings.metrics,
            palette: settings.palette,
            appearance: settings.appearance,
            onLaunch: AppLaunch.open,
            onOpenCursor: AppLaunch.openCursor,
            onOpenCalendar: AppLaunch.handleCalendarTile,
            onOpenWeather: AppLaunch.openWeather,
            stripOrder: settings.stripOrder
        )
        .frame(
            width: settings.metrics.stripWidth(items: StripItem.foldingAppsCoveredByWidgets(settings.stripOrder)),
            height: settings.metrics.dockHeight
        )
        .animation(Theme.layoutAnimation, value: settings.stripOrder)
        .animation(Theme.layoutAnimation, value: settings.iconOnlyWidgets)
        .padding(settings.metrics.shadowBleed)
        .onChange(of: settings.hideSystemDock) {
            NotificationCenter.default.post(name: .pierNeedsLayout, object: nil)
        }
        .onChange(of: settings.tileSize) {
            NotificationCenter.default.post(name: .pierNeedsLayout, object: nil)
        }
        .onChange(of: settings.stripOrder.map(\.id)) {
            if DockReorder.shared.draggingID == nil {
                NotificationCenter.default.post(name: .pierNeedsLayout, object: nil)
            }
        }
        .onChange(of: settings.appearance) {
            NotificationCenter.default.post(name: .pierNeedsLayout, object: nil)
        }
        .onChange(of: settings.iconOnlyWidgets.map(\.rawValue)) {
            NotificationCenter.default.post(name: .pierNeedsLayout, object: nil)
        }
    }
}

extension Notification.Name {
    static let pierNeedsLayout = Notification.Name("pierNeedsLayout")
}
