import Foundation
import SwiftUI

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case cursor
    case grokBot
    case calendar
    case weather

    var id: String { rawValue }

    var bundleID: String {
        switch self {
        case .cursor: return NativeDock.cursorBundleID
        case .grokBot: return NativeDock.grokBotBundleID
        case .calendar: return AppMarks.calendarBundleID
        case .weather: return "com.apple.weather"
        }
    }

    var fallbackName: String {
        switch self {
        case .cursor: return "Cursor"
        case .grokBot: return "Grok Bot"
        case .calendar: return "Calendar"
        case .weather: return "Weather"
        }
    }

    static let standard: [WidgetKind] = [.cursor, .grokBot, .calendar, .weather]

    var isInstalled: Bool {
        NativeDock.application(bundleID: bundleID, fallbackName: fallbackName) != nil
    }

    static var installed: Set<WidgetKind> {
        Set(standard.filter(\.isInstalled))
    }

    static func hosting(bundleID: String) -> WidgetKind? {
        standard.first { $0.bundleID == bundleID }
    }

    static func normalized(_ order: [WidgetKind]) -> [WidgetKind] {
        var seen = Set<WidgetKind>()
        var result: [WidgetKind] = []
        for kind in order where seen.insert(kind).inserted {
            result.append(kind)
        }
        for kind in standard where seen.insert(kind).inserted {
            result.append(kind)
        }
        return result
    }
}

enum StripItem: Equatable, Identifiable, Codable {
    case app(String)
    case widget(WidgetKind)

    var id: String {
        switch self {
        case .app(let bundleID): return "app:\(bundleID)"
        case .widget(let kind): return "widget:\(kind.rawValue)"
        }
    }

    /// Stable across Icon Only ↔ widget so the slot can morph instead of popping.
    var layoutID: String {
        switch self {
        case .widget(let kind):
            return "host:\(kind.rawValue)"
        case .app(let bundleID):
            if let kind = WidgetKind.hosting(bundleID: bundleID) {
                return "host:\(kind.rawValue)"
            }
            return "app:\(bundleID)"
        }
    }

    static func normalized(
        _ items: [StripItem],
        apps: [PinnedApp],
        iconOnly: Set<WidgetKind> = [],
        installed: Set<WidgetKind> = WidgetKind.installed
    ) -> [StripItem] {
        let appIDs = Set(apps.map(\.bundleID))
        var seenApp = Set<String>()
        var seenWidget = Set<WidgetKind>()
        var result: [StripItem] = []
        for item in items {
            switch item {
            case .app(let bundleID):
                guard appIDs.contains(bundleID), seenApp.insert(bundleID).inserted else { continue }
                result.append(item)
            case .widget(let kind):
                guard installed.contains(kind) else { continue }
                if iconOnly.contains(kind) {
                    guard appIDs.contains(kind.bundleID), seenApp.insert(kind.bundleID).inserted else { continue }
                    result.append(.app(kind.bundleID))
                } else {
                    guard seenWidget.insert(kind).inserted else { continue }
                    result.append(item)
                }
            }
        }
        for app in apps where seenApp.insert(app.bundleID).inserted {
            result.append(.app(app.bundleID))
        }
        for kind in WidgetKind.standard
            where installed.contains(kind) && !iconOnly.contains(kind) && seenWidget.insert(kind).inserted
        {
            result.append(.widget(kind))
        }
        return foldingAppsCoveredByWidgets(result, iconOnly: iconOnly)
    }

    /// An expanded host pin is the widget, not a second icon.
    static func foldingAppsCoveredByWidgets(
        _ items: [StripItem],
        iconOnly: Set<WidgetKind> = []
    ) -> [StripItem] {
        let claimed = Set(items.compactMap { item -> String? in
            if case .widget(let kind) = item, !iconOnly.contains(kind) { return kind.bundleID }
            return nil
        })
        return items.filter { item in
            guard case .app(let bundleID) = item else { return true }
            return !claimed.contains(bundleID)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case id
    }

    enum ItemType: String, Codable {
        case app
        case widget
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)
        let id = try container.decode(String.self, forKey: .id)
        switch type {
        case .app:
            self = .app(id)
        case .widget:
            guard let kind = WidgetKind(rawValue: id) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .id,
                    in: container,
                    debugDescription: "Unknown widget \(id)"
                )
            }
            self = .widget(kind)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let bundleID):
            try container.encode(ItemType.app, forKey: .type)
            try container.encode(bundleID, forKey: .id)
        case .widget(let kind):
            try container.encode(ItemType.widget, forKey: .type)
            try container.encode(kind.rawValue, forKey: .id)
        }
    }
}

@MainActor
final class DockReorder: ObservableObject {
    static let shared = DockReorder()

    @Published private(set) var draggingID: String?

    private var origin: [StripItem] = []
    private var startIndex = 0
    private var metrics = Theme.metrics(tileSize: Theme.defaultTileSize)

    func begin(item: StripItem, metrics: Theme.Metrics) {
        origin = StripItem.foldingAppsCoveredByWidgets(Settings.shared.stripOrder)
        startIndex = origin.firstIndex(of: item) ?? 0
        self.metrics = metrics
        draggingID = item.id
    }

    func update(translationX: CGFloat) {
        guard !origin.isEmpty, origin.indices.contains(startIndex) else { return }
        var next = origin
        let item = next.remove(at: startIndex)
        next.insert(item, at: destinationIndex(translationX: translationX))
        if next != Settings.shared.stripOrder {
            Settings.shared.stripOrder = next
        }
    }

    func end() {
        draggingID = nil
        NotificationCenter.default.post(name: .pierNeedsLayout, object: nil)
    }

    private func destinationIndex(translationX: CGFloat) -> Int {
        StripLayout.destinationIndex(
            translationX: translationX,
            startIndex: startIndex,
            items: origin,
            metrics: metrics
        )
    }
}

enum StripLayout {
    static func destinationIndex(
        translationX: CGFloat,
        startIndex: Int,
        items: [StripItem],
        metrics: Theme.Metrics
    ) -> Int {
        guard items.indices.contains(startIndex) else { return 0 }
        let frames = itemFrames(items, metrics: metrics)
        let dragged = frames[startIndex]
        let newCenter = dragged.x + translationX + dragged.width / 2
        var destination = 0
        for (index, frame) in frames.enumerated() where index != startIndex {
            if frame.x + frame.width / 2 < newCenter {
                destination += 1
            }
        }
        return destination
    }

    private static func itemFrames(
        _ items: [StripItem],
        metrics: Theme.Metrics
    ) -> [(x: CGFloat, width: CGFloat)] {
        var x: CGFloat = 0
        var frames: [(x: CGFloat, width: CGFloat)] = []
        for (index, item) in items.enumerated() {
            let width = metrics.itemWidth(item)
            frames.append((x, width))
            if index + 1 < items.count {
                x += width + metrics.spacing(between: item, and: items[index + 1])
            }
        }
        return frames
    }
}
