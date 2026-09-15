import SwiftUI

enum Theme {
    static let cornerRadius: CGFloat = 16
    static let widgetRadius: CGFloat = 14
    static let screenInset: CGFloat = 10
    static let aboveSystemDock: CGFloat = 8
    static let barShadowRadius: CGFloat = 18
    static let barShadowY: CGFloat = 6
    static let minTileSize: Double = 24
    static let maxTileSize: Double = 96
    static let defaultTileSize: Double = 36

    enum Appearance: String, CaseIterable {
        case dark
        case light

        var colorScheme: ColorScheme { self == .dark ? .dark : .light }

        var nsAppearance: NSAppearance? {
            NSAppearance(named: self == .dark ? .darkAqua : .aqua)
        }
    }

    struct Palette {
        var barFill: Color
        var barStroke: Color
        var barShadow: Color
        var glassTint: Color
        var textPrimary: Color
        var textSecondary: Color
        var runningDot: Color
        var divider: Color
        var widgetFill: Color
        var widgetGlassTint: Color
        var widgetStroke: Color
        var widgetText: Color
        var widgetMuted: Color
        var widgetLive: Color
    }

    static func palette(_ appearance: Appearance) -> Palette {
        switch appearance {
        case .dark:
            return Palette(
                barFill: Color.black.opacity(0.38),
                barStroke: Color.white.opacity(0.16),
                barShadow: Color.black.opacity(0.5),
                glassTint: Color.black.opacity(0.55),
                textPrimary: .white,
                textSecondary: Color.white.opacity(0.58),
                runningDot: Color.white.opacity(0.55),
                divider: Color.white.opacity(0.22),
                widgetFill: Color.white.opacity(0.06),
                widgetGlassTint: Color.white.opacity(0.16),
                widgetStroke: Color.white.opacity(0.22),
                widgetText: .white,
                widgetMuted: Color.white.opacity(0.55),
                widgetLive: Color(hex: 0x7DFF9A)
            )
        case .light:
            return Palette(
                barFill: Color.white.opacity(0.86),
                barStroke: Color.black.opacity(0.10),
                barShadow: Color.black.opacity(0.16),
                glassTint: Color.white.opacity(0.35),
                textPrimary: Color(hex: 0x1C1C1E),
                textSecondary: Color(hex: 0x636366),
                runningDot: Color(hex: 0x3A3A3C),
                divider: Color(hex: 0x636366).opacity(0.35),
                widgetFill: Color.white.opacity(0.22),
                widgetGlassTint: Color.white.opacity(0.40),
                widgetStroke: Color.black.opacity(0.12),
                widgetText: Color(hex: 0x1C1C1E),
                widgetMuted: Color(hex: 0x636366),
                widgetLive: Color(hex: 0x1A7F37)
            )
        }
    }

    struct Metrics: Equatable {
        var tileSize: CGFloat

        var iconSize: CGFloat { widgetInnerHeight }
        /// Workspace icons include canvas margin; scale so the mark matches the widget card.
        var iconOpticalScale: CGFloat { 1.18 }
        var tileWidth: CGFloat { iconSize }
        var gap: CGFloat { max(4, (tileSize * 0.04).rounded()) }
        var widgetGap: CGFloat { gap }
        var verticalPadding: CGFloat { max(6, (tileSize * 0.2).rounded()) }
        var horizontalPadding: CGFloat { max(10, (tileSize * 0.35).rounded()) }
        var runningMarkHeight: CGFloat { 2 }
        var runningMarkRadius: CGFloat { 2 }
        var dockBottomPadding: CGFloat { max(verticalPadding, runningMarkHeight) }
        var widgetInset: CGFloat { 4 }
        var widgetCycleWidth: CGFloat { 16 }
        var widgetInnerHeight: CGFloat {
            (widgetGlyph + widgetInset * 2).rounded()
        }
        var dockHeight: CGFloat {
            (widgetInnerHeight + verticalPadding * 2).rounded()
        }
        var shadowBleed: CGFloat {
            (Theme.barShadowRadius + abs(Theme.barShadowY) + 2).rounded()
        }

        func windowSize(items: [StripItem], maxWidth: CGFloat) -> NSSize {
            let visible = StripItem.foldingAppsCoveredByWidgets(items)
            let width = min(stripWidth(items: visible) + shadowBleed * 2, maxWidth)
            return NSSize(width: width, height: dockHeight + shadowBleed * 2)
        }
        var widgetHeight: CGFloat { widgetInnerHeight }
        var widgetFont: CGFloat { max(13, (tileSize * 0.38).rounded()) }
        var widgetTemp: CGFloat { max(16, (tileSize * 0.48).rounded()) }
        var widgetCaption: CGFloat { max(9, (tileSize * 0.24).rounded()) }
        var widgetIcon: CGFloat { max(18, (tileSize * 0.72).rounded()) }
        var widgetGlyph: CGFloat { max(22, tileSize.rounded()) }
        var widgetSlotWidth: CGFloat { max(148, (tileSize * 3.6).rounded()) }
        var dividerWidth: CGFloat { 12 }
        var dividerHeight: CGFloat { max(16, (tileSize * 0.72).rounded()) }
        var resizeHandle: CGFloat { 10 }

        func itemWidth(_ item: StripItem) -> CGFloat {
            switch item {
            case .app: return tileWidth
            case .widget: return widgetSlotWidth
            }
        }

        func spacing(between _: StripItem, and _: StripItem) -> CGFloat {
            gap
        }

        /// Width of the whole strip. Kept in one place so the window can
        /// center on a number that does not move when a label changes.
        func stripWidth(items: [StripItem]) -> CGFloat {
            guard !items.isEmpty else {
                return (horizontalPadding * 2).rounded()
            }
            var width = horizontalPadding * 2
            for (index, item) in items.enumerated() {
                width += itemWidth(item)
                if index + 1 < items.count {
                    width += spacing(between: item, and: items[index + 1])
                }
            }
            return width.rounded()
        }
    }

    static func metrics(tileSize: Double) -> Metrics {
        Metrics(tileSize: CGFloat(clampedTile(tileSize)))
    }

    static func clampedTile(_ value: Double) -> Double {
        min(maxTileSize, max(minTileSize, value.rounded()))
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
