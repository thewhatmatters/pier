import AppKit
import SwiftUI

final class AppMenuController: NSObject {
    let app: PinnedApp

    init(app: PinnedApp) {
        self.app = app
    }

    @objc func open() { AppLaunch.open(app) }
    @objc func hide() { AppLaunch.hide(app) }
    @objc func quit() { AppLaunch.quit(app) }
    @objc func forceQuit() { AppLaunch.forceQuit(app) }
    @objc func reveal() { AppLaunch.reveal(app) }
    @objc func remove() { Settings.shared.removePinned(app) }
}

enum AppIconMenu {
    static func make(
        app: PinnedApp,
        running: Bool,
        controller: AppMenuController,
        includeRemove: Bool = true
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let open = NSMenuItem(title: "Open", action: #selector(AppMenuController.open), keyEquivalent: "")
        open.target = controller
        menu.addItem(open)

        menu.addItem(.separator())

        let hide = NSMenuItem(title: "Hide", action: #selector(AppMenuController.hide), keyEquivalent: "")
        hide.target = controller
        hide.isEnabled = running
        menu.addItem(hide)

        let optionHeld = NSEvent.modifierFlags.contains(.option)
        let quit = NSMenuItem(
            title: optionHeld ? "Force Quit" : "Quit",
            action: optionHeld ? #selector(AppMenuController.forceQuit) : #selector(AppMenuController.quit),
            keyEquivalent: ""
        )
        quit.target = controller
        quit.isEnabled = running
        menu.addItem(quit)

        menu.addItem(.separator())

        let reveal = NSMenuItem(title: "Show in Finder", action: #selector(AppMenuController.reveal), keyEquivalent: "")
        reveal.target = controller
        menu.addItem(reveal)

        if includeRemove {
            let remove = NSMenuItem(title: "Remove from Pier", action: #selector(AppMenuController.remove), keyEquivalent: "")
            remove.target = controller
            menu.addItem(remove)
        }

        return menu
    }
}

struct AppTileClickLayer: NSViewRepresentable {
    let app: PinnedApp
    let running: Bool
    let metrics: Theme.Metrics
    let onOpen: () -> Void

    func makeNSView(context: Context) -> TileClickCatcher {
        let view = TileClickCatcher(frame: .zero)
        apply(view)
        return view
    }

    func updateNSView(_ view: TileClickCatcher, context: Context) {
        apply(view)
    }

    private func apply(_ view: TileClickCatcher) {
        view.app = app
        view.running = running
        view.onOpen = onOpen
        view.onDragBegin = { DockReorder.shared.begin(item: .app(app.bundleID), metrics: metrics) }
        view.onDragChanged = { DockReorder.shared.update(translationX: $0) }
        view.onDragEnded = { DockReorder.shared.end() }
    }
}

struct WidgetClickLayer: NSViewRepresentable {
    let kind: WidgetKind
    var app: PinnedApp?
    var running: Bool = false
    let metrics: Theme.Metrics
    let onOpen: () -> Void

    func makeNSView(context: Context) -> TileClickCatcher {
        let view = TileClickCatcher(frame: .zero)
        apply(view)
        return view
    }

    func updateNSView(_ view: TileClickCatcher, context: Context) {
        apply(view)
    }

    private func apply(_ view: TileClickCatcher) {
        view.app = app
        view.kind = kind
        view.running = running
        view.onOpen = onOpen
        view.onDragBegin = { DockReorder.shared.begin(item: .widget(kind), metrics: metrics) }
        view.onDragChanged = { DockReorder.shared.update(translationX: $0) }
        view.onDragEnded = { DockReorder.shared.end() }
    }
}

struct CycleClickLayer: NSViewRepresentable {
    let onPrevious: () -> Void
    let onNext: () -> Void

    func makeNSView(context: Context) -> CycleClickCatcher {
        let view = CycleClickCatcher(frame: .zero)
        view.onPrevious = onPrevious
        view.onNext = onNext
        return view
    }

    func updateNSView(_ view: CycleClickCatcher, context: Context) {
        view.onPrevious = onPrevious
        view.onNext = onNext
    }
}

final class CycleClickCatcher: NSView {
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if local.y >= bounds.midY {
            onPrevious()
        } else {
            onNext()
        }
    }
}

@MainActor
final class WeatherMenuController: NSObject {
    @objc func addCity() { WeatherPlaces.promptAdd() }
    @objc func removeCity() { Store.shared.removeCurrentWeatherPlace() }
}

enum WeatherPlaces {
    @MainActor
    static func promptAdd() {
        let alert = NSAlert()
        alert.messageText = "Add a city"
        alert.informativeText = "Pier will fetch weather for this place so you can cycle it on the tile."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: "")
        field.placeholderString = "Austin, Tokyo, …"
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)
        guard response == .alertFirstButtonReturn else { return }
        let query = field.stringValue
        Task {
            if let place = await Weather.lookupCity(query) {
                Settings.shared.addWeatherPlace(place)
                Store.shared.refreshWeatherPages()
            }
        }
    }
}

final class TileClickCatcher: NSView {
    var app: PinnedApp?
    var kind: WidgetKind?
    var running = false
    private var weatherController: WeatherMenuController?
    var onOpen: () -> Void = {}
    var onDragBegin: () -> Void = {}
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}
    private var controller: AppMenuController?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            pop(event)
            return
        }
        track(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        pop(event)
    }

    /// Pull drag/up from the window-server click session. A local monitor
    /// never sees those events on a nonactivating panel that is not key.
    private func track(_ event: NSEvent) {
        let start = event.locationInWindow
        var dragging = false
        let deadline = Date().addingTimeInterval(30)
        while let next = window?.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: deadline,
            inMode: .eventTracking,
            dequeue: true
        ) {
            switch next.type {
            case .leftMouseDragged:
                let dx = next.locationInWindow.x - start.x
                let dy = next.locationInWindow.y - start.y
                if !dragging && hypot(dx, dy) > 8 {
                    dragging = true
                    onDragBegin()
                }
                if dragging {
                    onDragChanged(dx)
                }
            case .leftMouseUp:
                if dragging {
                    onDragEnded()
                } else {
                    onOpen()
                }
                return
            default:
                break
            }
        }
        if dragging { onDragEnded() }
    }

    func pop(_ event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let app {
            let controller = AppMenuController(app: app)
            self.controller = controller
            let menu = AppIconMenu.make(
                app: app,
                running: running,
                controller: controller,
                includeRemove: kind == nil
            )
            if kind == .weather {
                appendWeatherItems(to: menu)
            }
            menu.popUp(positioning: nil, at: location, in: self)
            return
        }
        if kind == .weather {
            let menu = NSMenu()
            menu.autoenablesItems = false
            appendWeatherItems(to: menu)
            menu.popUp(positioning: nil, at: location, in: self)
        }
    }

    private func appendWeatherItems(to menu: NSMenu) {
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        let controller = WeatherMenuController()
        weatherController = controller
        let add = NSMenuItem(title: "Add City…", action: #selector(WeatherMenuController.addCity), keyEquivalent: "")
        add.target = controller
        menu.addItem(add)
        let remove = NSMenuItem(title: "Remove City", action: #selector(WeatherMenuController.removeCity), keyEquivalent: "")
        remove.target = controller
        let city = Store.shared.snapshot.weather?.city
        remove.isEnabled = Settings.shared.weatherPlaces.contains { $0.name == city }
        menu.addItem(remove)
    }

    static func located(at windowPoint: NSPoint, in window: NSWindow?) -> TileClickCatcher? {
        guard let root = window?.contentView else { return nil }
        var match: TileClickCatcher?
        enumerate(root) { view in
            guard let catcher = view as? TileClickCatcher, catcher.bounds.width > 1 else { return }
            let local = catcher.convert(windowPoint, from: nil)
            if catcher.bounds.contains(local) {
                match = catcher
            }
        }
        return match
    }

    private static func enumerate(_ view: NSView, _ visit: (NSView) -> Void) {
        visit(view)
        for sub in view.subviews {
            enumerate(sub, visit)
        }
    }
}
