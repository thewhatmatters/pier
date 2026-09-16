import Foundation

final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let pinnedApps = "pinnedApps"
        static let hideSystemDock = "hideSystemDock"
        static let launchAtLogin = "launchAtLogin"
        static let previousAutohide = "previousSystemDockAutohide"
        static let previousAutohideDelay = "previousSystemDockAutohideDelay"
        static let tileSize = "tileSize"
        static let appearance = "appearance"
        static let widgetOrder = "widgetOrder"
        static let stripOrder = "stripOrder"
        static let weatherPlaces = "weatherPlaces"
        static let iconOnlyWidgets = "iconOnlyWidgets"
    }

    @Published var pinnedApps: [PinnedApp] {
        didSet { save(pinnedApps, key: Key.pinnedApps) }
    }

    @Published var hideSystemDock: Bool {
        didSet { defaults.set(hideSystemDock, forKey: Key.hideSystemDock) }
    }

    @Published var tileSize: Double {
        didSet { defaults.set(tileSize, forKey: Key.tileSize) }
    }

    @Published var appearance: Theme.Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    @Published var widgetOrder: [WidgetKind] {
        didSet { save(widgetOrder, key: Key.widgetOrder) }
    }

    @Published var stripOrder: [StripItem] {
        didSet {
            save(stripOrder, key: Key.stripOrder)
            syncDerivedOrder()
        }
    }

    @Published var weatherPlaces: [WeatherPlace] {
        didSet { save(weatherPlaces, key: Key.weatherPlaces) }
    }

    @Published var iconOnlyWidgets: [WidgetKind] {
        didSet { save(iconOnlyWidgets, key: Key.iconOnlyWidgets) }
    }

    var metrics: Theme.Metrics { Theme.metrics(tileSize: tileSize) }
    var palette: Theme.Palette { Theme.palette(appearance) }

    func removePinned(_ app: PinnedApp) {
        stripOrder.removeAll { $0 == .app(app.bundleID) }
    }

    var previousSystemDockAutohide: Bool? {
        get {
            defaults.object(forKey: Key.previousAutohide) == nil
                ? nil
                : defaults.bool(forKey: Key.previousAutohide)
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.previousAutohide)
            } else {
                defaults.removeObject(forKey: Key.previousAutohide)
            }
        }
    }

    var previousSystemDockAutohideDelay: Double? {
        get { defaults.object(forKey: Key.previousAutohideDelay) as? Double }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.previousAutohideDelay)
            } else {
                defaults.removeObject(forKey: Key.previousAutohideDelay)
            }
        }
    }

    private init() {
        if defaults.object(forKey: Key.hideSystemDock) == nil {
            hideSystemDock = true
            defaults.set(true, forKey: Key.hideSystemDock)
        } else {
            hideSystemDock = defaults.bool(forKey: Key.hideSystemDock)
        }
        if defaults.object(forKey: Key.tileSize) != nil {
            tileSize = Theme.clampedTile(defaults.double(forKey: Key.tileSize))
        } else {
            tileSize = Theme.defaultTileSize
        }
        if let raw = defaults.string(forKey: Key.appearance),
           let stored = Theme.Appearance(rawValue: raw) {
            appearance = stored
        } else {
            appearance = .dark
            defaults.set(Theme.Appearance.dark.rawValue, forKey: Key.appearance)
        }
        let apps: [PinnedApp]
        if let data = defaults.data(forKey: Key.pinnedApps),
           let stored = try? JSONDecoder().decode([PinnedApp].self, from: data),
           !stored.isEmpty {
            apps = NativeDock.withFinder(stored)
        } else {
            apps = NativeDock.pinnedApps()
            if let data = try? JSONEncoder().encode(apps) {
                defaults.set(data, forKey: Key.pinnedApps)
            }
        }
        pinnedApps = apps

        let widgets: [WidgetKind]
        if let data = defaults.data(forKey: Key.widgetOrder),
           let order = try? JSONDecoder().decode([WidgetKind].self, from: data) {
            widgets = WidgetKind.normalized(order)
        } else {
            widgets = WidgetKind.standard
            defaults.set(try? JSONEncoder().encode(WidgetKind.standard), forKey: Key.widgetOrder)
        }
        widgetOrder = widgets

        let migrated: [StripItem]
        if let data = defaults.data(forKey: Key.stripOrder),
           let stored = try? JSONDecoder().decode([StripItem].self, from: data) {
            migrated = stored
        } else {
            migrated = apps.map { StripItem.app($0.bundleID) } + widgets.map { StripItem.widget($0) }
        }
        if let data = defaults.data(forKey: Key.weatherPlaces),
           let places = try? JSONDecoder().decode([WeatherPlace].self, from: data) {
            weatherPlaces = places
        } else {
            weatherPlaces = []
        }
        let iconOnly: [WidgetKind]
        if let data = defaults.data(forKey: Key.iconOnlyWidgets),
           let stored = try? JSONDecoder().decode([WidgetKind].self, from: data) {
            iconOnly = stored
        } else {
            iconOnly = []
        }
        iconOnlyWidgets = iconOnly
        var normalized = StripItem.normalized(migrated, apps: apps, iconOnly: Set(iconOnly))
        if apps.contains(where: { $0.bundleID == NativeDock.finderBundleID }),
           !normalized.contains(.app(NativeDock.finderBundleID)) {
            normalized.insert(.app(NativeDock.finderBundleID), at: 0)
        }
        stripOrder = normalized
        if migrated != normalized || defaults.data(forKey: Key.stripOrder) == nil {
            save(normalized, key: Key.stripOrder)
        }
    }

    func addWeatherPlace(_ place: WeatherPlace) {
        guard !weatherPlaces.contains(where: { $0.id == place.id }) else { return }
        weatherPlaces.append(place)
    }

    func removeWeatherPlace(at index: Int) {
        guard weatherPlaces.indices.contains(index) else { return }
        weatherPlaces.remove(at: index)
    }

    func syncAvailableWidgets() {
        let next = StripItem.normalized(stripOrder, apps: pinnedApps, iconOnly: Set(iconOnlyWidgets))
        if next != stripOrder {
            stripOrder = next
            NotificationCenter.default.post(name: .pierNeedsLayout, object: nil)
        }
    }

    func setIconOnly(_ kind: WidgetKind, _ iconOnly: Bool) {
        var only = Set(iconOnlyWidgets)
        if iconOnly {
            only.insert(kind)
            if let app = NativeDock.application(bundleID: kind.bundleID, fallbackName: kind.fallbackName),
               !pinnedApps.contains(where: { $0.bundleID == app.bundleID }) {
                pinnedApps.append(app)
            }
        } else {
            only.remove(kind)
        }
        var items = stripOrder
        if iconOnly {
            if let index = items.firstIndex(of: .widget(kind)) {
                items[index] = .app(kind.bundleID)
            } else if !items.contains(.app(kind.bundleID)) {
                items.append(.app(kind.bundleID))
            }
        } else if let index = items.firstIndex(of: .app(kind.bundleID)) {
            items[index] = .widget(kind)
        } else if !items.contains(.widget(kind)) {
            items.append(.widget(kind))
        }
        iconOnlyWidgets = WidgetKind.standard.filter(only.contains)
        stripOrder = StripItem.normalized(items, apps: pinnedApps, iconOnly: only)
        NotificationCenter.default.post(name: .pierNeedsLayout, object: nil)
    }

    private func syncDerivedOrder() {
        let ids = stripOrder.compactMap { item -> String? in
            if case .app(let bundleID) = item { return bundleID }
            return nil
        }
        let claimed = Set(WidgetKind.standard.map(\.bundleID))
        let byID = Dictionary(uniqueKeysWithValues: pinnedApps.map { ($0.bundleID, $0) })
        var nextApps = ids.compactMap { byID[$0] }
        for app in pinnedApps where claimed.contains(app.bundleID)
            && !nextApps.contains(where: { $0.bundleID == app.bundleID }) {
            nextApps.append(app)
        }
        if nextApps.map(\.bundleID) != pinnedApps.map(\.bundleID) {
            pinnedApps = nextApps
        }
        let nextWidgets = stripOrder.compactMap { item -> WidgetKind? in
            if case .widget(let kind) = item { return kind }
            return nil
        }
        if nextWidgets != widgetOrder {
            widgetOrder = WidgetKind.normalized(nextWidgets)
        }
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
