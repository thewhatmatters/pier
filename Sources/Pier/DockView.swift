import AppKit
import SwiftUI

struct DockView: View {
    let snapshot: DockSnapshot
    var metrics: Theme.Metrics = Theme.metrics(tileSize: Theme.defaultTileSize)
    var palette: Theme.Palette = Theme.palette(.dark)
    var appearance: Theme.Appearance = .dark
    var onLaunch: (PinnedApp) -> Void = { _ in }
    var onOpenCursor: () -> Void = {}
    var onOpenCalendar: () -> Void = {}
    var onOpenWeather: () -> Void = {}
    var stripOrder: [StripItem] = []
    @ObservedObject private var reorder = DockReorder.shared
    @Namespace private var stripSpace

    private var appsByID: [String: PinnedApp] {
        Dictionary(uniqueKeysWithValues: snapshot.apps.map { ($0.bundleID, $0) })
    }

    private var visibleStrip: [StripItem] {
        StripItem.foldingAppsCoveredByWidgets(stripOrder)
    }

    private func hostApp(for kind: WidgetKind) -> PinnedApp? {
        appsByID[kind.bundleID]
            ?? NativeDock.application(bundleID: kind.bundleID, fallbackName: kind.fallbackName)
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                ForEach(Array(visibleStrip.enumerated()), id: \.element.layoutID) { index, item in
                    stripItem(item)
                    if index + 1 < visibleStrip.count {
                        Color.clear.frame(
                            width: metrics.spacing(between: item, and: visibleStrip[index + 1])
                        )
                    }
                }
            }
            .animation(Theme.layoutAnimation, value: visibleStrip)
            .environment(\.stripNamespace, stripSpace)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)

            DockResizeHandle(height: metrics.resizeHandle)
        }
        .foregroundStyle(palette.textPrimary)
        .preferredColorScheme(appearance.colorScheme)
        .background { DockBackground(palette: palette) }
    }

    @ViewBuilder
    private func stripItem(_ item: StripItem) -> some View {
        switch item {
        case .app(let bundleID):
            if let app = appsByID[bundleID] {
                AppTile(
                    app: app,
                    running: snapshot.runningBundleIDs.contains(app.bundleID),
                    badge: snapshot.badges[app.bundleID],
                    metrics: metrics,
                    palette: palette,
                    action: { onLaunch(app) }
                )
                .opacity(reorder.draggingID == item.id ? 0.72 : 1)
                .frame(width: metrics.itemWidth(item), alignment: .leading)
            }
        case .widget(let kind):
            widget(for: kind)
                .frame(width: metrics.itemWidth(item), alignment: .leading)
                .opacity(reorder.draggingID == item.id ? 0.72 : 1)
        }
    }

    @ViewBuilder
    private func widget(for kind: WidgetKind) -> some View {
        switch kind {
        case .cursor:
            CursorWidget(
                snapshot: snapshot.cursor,
                agents: snapshot.agents,
                app: hostApp(for: .cursor),
                running: snapshot.runningBundleIDs.contains(WidgetKind.cursor.bundleID),
                metrics: metrics,
                palette: palette,
                action: onOpenCursor
            )
        case .calendar:
            CalendarWidget(
                snapshot: snapshot.calendar,
                app: hostApp(for: .calendar),
                running: snapshot.runningBundleIDs.contains(WidgetKind.calendar.bundleID),
                metrics: metrics,
                palette: palette,
                action: onOpenCalendar,
                onPrevious: { Store.shared.cycleCalendar(-1) },
                onNext: { Store.shared.cycleCalendar(1) }
            )
        case .weather:
            WeatherWidget(
                snapshot: snapshot.weather,
                app: hostApp(for: .weather),
                running: snapshot.runningBundleIDs.contains(WidgetKind.weather.bundleID),
                pageCount: snapshot.weatherCount,
                metrics: metrics,
                palette: palette,
                action: onOpenWeather,
                onPrevious: { Store.shared.cycleWeather(-1) },
                onNext: { Store.shared.cycleWeather(1) }
            )
        }
    }
}

private struct DockBackground: View {
    let palette: Theme.Palette
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
    }

    var body: some View {
        shape
            .fill(palette.barFill)
            .shadow(color: palette.barShadow, radius: Theme.barShadowRadius, y: Theme.barShadowY)
            .overlay {
                if #available(macOS 26.0, *) {
                    shape
                        .fill(.clear)
                        .glassEffect(.regular.tint(palette.glassTint), in: shape)
                } else {
                    shape.fill(.ultraThinMaterial.opacity(0.55))
                }
            }
            .overlay { shape.stroke(palette.barStroke, lineWidth: 0.8) }
    }
}

private struct WidgetBackground: View {
    let palette: Theme.Palette
    let shape: RoundedRectangle

    var body: some View {
        shape
            .fill(palette.widgetFill)
            .overlay {
                if #available(macOS 26.0, *) {
                    shape
                        .fill(.clear)
                        .glassEffect(.regular.tint(palette.widgetGlassTint), in: shape)
                } else {
                    shape.fill(.ultraThinMaterial.opacity(0.7))
                }
            }
            .overlay { shape.stroke(palette.widgetStroke, lineWidth: 0.8) }
    }
}

private struct AppTile: View {
    let app: PinnedApp
    let running: Bool
    var badge: String?
    let metrics: Theme.Metrics
    let palette: Theme.Palette
    let action: () -> Void

    var body: some View {
        AppIcon(app: app, metrics: metrics, fillsTile: true)
            .frame(width: metrics.tileWidth, height: metrics.iconSize)
            .contentShape(Rectangle())
            .overlay {
                AppTileClickLayer(app: app, running: running, metrics: metrics, onOpen: action)
            }
            .overlay(alignment: .topTrailing) {
                if let mark = DockBadge.mark(from: badge) {
                    IconBadge(mark: mark, metrics: metrics, palette: palette)
                        .offset(x: 3, y: -2)
                }
            }
            .overlay(alignment: .bottom) {
                if running {
                    ZStack(alignment: .bottom) {
                        RunningSpotlight(metrics: metrics, color: palette.runningDot)
                        RunningTick(metrics: metrics, color: palette.runningDot)
                    }
                    .frame(width: metrics.tileWidth, height: 0, alignment: .bottom)
                    .allowsHitTesting(false)
                }
            }
            .help(DockBadge.help(appName: app.name, raw: badge))
    }
}

private struct IconBadge: View {
    let mark: DockBadge.Mark
    let metrics: Theme.Metrics
    let palette: Theme.Palette

    var body: some View {
        let height = metrics.badgeSize
        Group {
            switch mark {
            case .dot:
                Circle()
                    .fill(palette.badgeFill)
                    .frame(width: (height * 0.55).rounded(), height: (height * 0.55).rounded())
            case .count(let text):
                Text(text)
                    .font(Typeface.sans(metrics.badgeFont, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, text.count > 1 ? 3.5 : 0)
                    .frame(minWidth: height, minHeight: height)
                    .background(palette.badgeFill, in: Capsule())
            }
        }
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.92), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

private struct RunningTick: View {
    let metrics: Theme.Metrics
    let color: Color
    var width: CGFloat? = nil

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: metrics.runningMarkRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: metrics.runningMarkRadius,
            style: .circular
        )
        .fill(color)
        .frame(width: (width ?? metrics.tileWidth / 2).rounded(), height: metrics.runningMarkHeight)
        .offset(y: metrics.dockBottomPadding)
        .allowsHitTesting(false)
    }
}

private struct RunningSpotlight: View {
    let metrics: Theme.Metrics
    let color: Color
    var width: CGFloat? = nil

    var body: some View {
        let height = metrics.iconSize + metrics.dockBottomPadding
        SpotlightCone()
            .fill(
                LinearGradient(
                    colors: [
                        color.opacity(0.34),
                        color.opacity(0.12),
                        color.opacity(0)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .mask(
                LinearGradient(
                    colors: [.white, .white.opacity(0.35), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .blur(radius: 8)
            .frame(width: width ?? metrics.tileWidth, height: height)
            .offset(y: metrics.dockBottomPadding)
            .allowsHitTesting(false)
    }
}

private struct SpotlightCone: Shape {
    func path(in rect: CGRect) -> Path {
        let source = rect.width * 0.5
        let inset = (rect.width - source) / 2
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: inset + source, y: rect.height))
        path.addLine(to: CGPoint(x: inset, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private struct AppIcon: View {
    let app: PinnedApp
    let metrics: Theme.Metrics
    var size: CGFloat?
    var fillsTile: Bool = false

    var body: some View {
        let side = size ?? metrics.iconSize
        Image(nsImage: AppLaunch.icon(for: app))
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .scaleEffect(fillsTile ? metrics.iconOpticalScale : 1)
            .frame(width: side, height: side)
            .clipped()
            .stripMatchedIcon(app.bundleID)
    }
}

private struct CursorWidget: View {
    let snapshot: CursorSnapshot
    let agents: AgentSnapshot
    let app: PinnedApp?
    let running: Bool
    let metrics: Theme.Metrics
    let palette: Theme.Palette
    let action: () -> Void

    var body: some View {
        WidgetTile(
            kind: .cursor,
            app: app,
            running: running,
            metrics: metrics,
            palette: palette,
            action: action
        ) {
            HStack(spacing: 8) {
                WidgetAppMark(app: app, systemName: agents.working.isEmpty
                    ? "chevron.left.forwardslash.chevron.right"
                    : "sparkle", metrics: metrics, palette: palette)
                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot.label)
                        .font(Typeface.sans(metrics.widgetTemp, weight: .light))
                        .foregroundStyle(palette.widgetText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(agents.caption)
                        .font(Typeface.sans(metrics.widgetCaption))
                        .foregroundStyle(agents.working.isEmpty ? palette.widgetMuted : palette.widgetLive)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.top, -3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .help(agents.help)
    }
}

private struct CalendarWidget: View {
    let snapshot: CalendarSnapshot?
    let app: PinnedApp?
    let running: Bool
    let metrics: Theme.Metrics
    let palette: Theme.Palette
    let action: () -> Void
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}

    var body: some View {
        WidgetTile(
            kind: .calendar,
            app: app,
            running: running,
            metrics: metrics,
            palette: palette,
            action: action,
            pageCount: snapshot?.count ?? 0,
            onPrevious: onPrevious,
            onNext: onNext
        ) {
            HStack(spacing: 8) {
                WidgetAppMark(app: app, systemName: "calendar", metrics: metrics, palette: palette)
                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot?.headline ?? "—")
                        .font(Typeface.sans(metrics.widgetTemp, weight: .light))
                        .foregroundStyle(palette.widgetText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(snapshot?.caption ?? " ")
                        .font(Typeface.sans(metrics.widgetCaption))
                        .foregroundStyle(snapshot?.status == .authorized && snapshot?.count ?? 0 > 0
                                         ? palette.widgetLive
                                         : palette.widgetMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.top, -3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .help(cycleHelp(snapshot?.help))
    }

    private func cycleHelp(_ help: String?) -> String {
        let base = help ?? "Checking calendars…"
        if (snapshot?.canCycle ?? false) {
            return base + "\nClick the arrows to cycle today’s events."
        }
        return base
    }
}

private struct WeatherWidget: View {
    let snapshot: WeatherSnapshot?
    let app: PinnedApp?
    let running: Bool
    let pageCount: Int
    let metrics: Theme.Metrics
    let palette: Theme.Palette
    let action: () -> Void
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}

    var body: some View {
        WidgetTile(
            kind: .weather,
            app: app,
            running: running,
            metrics: metrics,
            palette: palette,
            action: action,
            pageCount: pageCount,
            onPrevious: onPrevious,
            onNext: onNext
        ) {
            HStack(spacing: 8) {
                WidgetAppMark(
                    app: app,
                    systemName: snapshot?.symbol ?? "cloud.fill",
                    metrics: metrics,
                    palette: palette
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot?.label ?? "—")
                        .font(Typeface.mono(metrics.widgetTemp, weight: .light))
                        .foregroundStyle(palette.widgetText)
                        .lineLimit(1)
                    Text(snapshot?.city ?? " ")
                        .font(Typeface.sans(metrics.widgetCaption))
                        .foregroundStyle(palette.widgetMuted)
                        .lineLimit(1)
                        .padding(.top, -3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let high = snapshot?.highLabel, let low = snapshot?.lowLabel {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(high)
                            .font(Typeface.mono(metrics.widgetCaption, weight: .medium))
                            .foregroundStyle(palette.widgetText)
                        Text(low)
                            .font(Typeface.mono(metrics.widgetCaption, weight: .medium))
                            .foregroundStyle(palette.widgetMuted)
                            .padding(.top, -1)
                    }
                    .monospacedDigit()
                }
            }
        }
        .help(weatherHelp)
    }

    private var weatherHelp: String {
        let base = snapshot.map { snap in
            var line = "\(snap.city) · \(snap.condition) · \(snap.label)"
            if let high = snap.highLabel, let low = snap.lowLabel {
                line += " · H \(high) · L \(low)"
            }
            return line + " · \(snap.source)"
        }
            ?? "Fetching weather…"
        if pageCount > 1 {
            return base + "\nClick the arrows to cycle cities. Right-click to add or remove one."
        }
        return base + "\nRight-click to add another city."
    }
}

private struct WidgetAppMark: View {
    let app: PinnedApp?
    let systemName: String
    let metrics: Theme.Metrics
    let palette: Theme.Palette

    var body: some View {
        if let app {
            AppIcon(app: app, metrics: metrics, size: metrics.widgetGlyph)
        } else {
            HalftoneSymbol(systemName: systemName, size: metrics.widgetGlyph, color: palette.widgetText)
        }
    }
}

private struct WidgetTile<Content: View>: View {
    let kind: WidgetKind
    var app: PinnedApp?
    var running: Bool = false
    let metrics: Theme.Metrics
    let palette: Theme.Palette
    let action: () -> Void
    var pageCount: Int = 1
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.widgetRadius, style: .continuous)
        content()
            .padding(metrics.widgetInset)
            .padding(.trailing, pageCount > 1 ? metrics.widgetCycleWidth : 0)
            .frame(maxWidth: .infinity)
            .frame(height: metrics.widgetInnerHeight)
            .background { WidgetBackground(palette: palette, shape: shape) }
            .overlay {
                WidgetClickLayer(kind: kind, app: app, running: running, metrics: metrics, onOpen: action)
            }
            .overlay(alignment: .bottom) {
                if running {
                    let tickWidth = metrics.widgetSlotWidth - metrics.widgetInset * 2
                    ZStack(alignment: .bottom) {
                        RunningSpotlight(
                            metrics: metrics,
                            color: palette.runningDot,
                            width: metrics.widgetSlotWidth
                        )
                        RunningTick(metrics: metrics, color: palette.runningDot, width: tickWidth)
                    }
                    .frame(width: metrics.widgetSlotWidth, height: 0, alignment: .bottom)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .trailing) {
                if pageCount > 1 {
                    WidgetCycleControl(
                        metrics: metrics,
                        palette: palette,
                        onPrevious: onPrevious,
                        onNext: onNext
                    )
                    .padding(.trailing, metrics.widgetInset)
                }
            }
    }
}

private struct WidgetCycleControl: View {
    let metrics: Theme.Metrics
    let palette: Theme.Palette
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            cycleButton("chevron.up")
            cycleButton("chevron.down")
        }
        .frame(width: metrics.widgetCycleWidth)
        .contentShape(Rectangle())
        .overlay {
            CycleClickLayer(onPrevious: onPrevious, onNext: onNext)
        }
        .allowsHitTesting(true)
    }

    private func cycleButton(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 6, weight: .semibold))
            .foregroundStyle(palette.widgetMuted)
            .frame(width: metrics.widgetCycleButton, height: metrics.widgetCycleButton)
            .background {
                Circle()
                    .fill(palette.widgetFill)
                    .overlay { Circle().stroke(palette.widgetStroke, lineWidth: 0.8) }
            }
    }
}

private struct DockResizeHandle: View {
    var width: CGFloat?
    var height: CGFloat = 10
    @ObservedObject private var settings = Settings.shared
    @State private var originTile: Double?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : width)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if originTile == nil { originTile = settings.tileSize }
                        let next = (originTile ?? settings.tileSize) - Double(value.translation.height)
                        settings.tileSize = Theme.clampedTile(next)
                    }
                    .onEnded { _ in
                        originTile = nil
                    }
            )
    }
}

private struct StripNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var stripNamespace: Namespace.ID? {
        get { self[StripNamespaceKey.self] }
        set { self[StripNamespaceKey.self] = newValue }
    }
}

private extension View {
    func stripMatchedIcon(_ id: String) -> some View {
        modifier(StripMatchedIcon(id: id))
    }
}

private struct StripMatchedIcon: ViewModifier {
    let id: String
    @Environment(\.stripNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}
