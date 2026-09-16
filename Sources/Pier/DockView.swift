import AppKit
import SwiftUI

struct DockView: View {
    let snapshot: DockSnapshot
    var metrics: Theme.Metrics = Theme.metrics(tileSize: Theme.defaultTileSize)
    var palette: Theme.Palette = Theme.palette(.dark)
    var appearance: Theme.Appearance = .dark
    var onLaunch: (PinnedApp) -> Void = { _ in }
    var onOpenCursor: () -> Void = {}
    var onOpenGrokBot: () -> Void = {}
    var onOpenDocker: () -> Void = {}
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
                app: hostApp(for: .cursor),
                running: snapshot.runningBundleIDs.contains(WidgetKind.cursor.bundleID),
                metrics: metrics,
                palette: palette,
                action: onOpenCursor
            )
        case .grokBot:
            GrokBotWidget(
                snapshot: snapshot.grokBot,
                app: hostApp(for: .grokBot),
                running: snapshot.runningBundleIDs.contains(WidgetKind.grokBot.bundleID),
                metrics: metrics,
                palette: palette,
                action: onOpenGrokBot,
                onPrevious: { Store.shared.cycleGrokBot(-1) },
                onNext: { Store.shared.cycleGrokBot(1) }
            )
        case .docker:
            DockerWidget(
                snapshot: snapshot.docker,
                app: hostApp(for: .docker),
                running: snapshot.runningBundleIDs.contains(WidgetKind.docker.bundleID),
                metrics: metrics,
                palette: palette,
                action: onOpenDocker,
                onPrevious: { Store.shared.cycleDocker(-1) },
                onNext: { Store.shared.cycleDocker(1) }
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
    var app: PinnedApp?
    let palette: Theme.Palette
    let shape: RoundedRectangle

    var body: some View {
        shape
            .fill(palette.widgetFill)
            .overlay {
                if let app {
                    WidgetIconWash(app: app)
                        .clipShape(shape)
                }
            }
            .overlay {
                if app == nil {
                    if #available(macOS 26.0, *) {
                        shape
                            .fill(.clear)
                            .glassEffect(.regular.tint(palette.widgetGlassTint), in: shape)
                    } else {
                        shape.fill(.ultraThinMaterial.opacity(0.7))
                    }
                }
            }
            .overlay { shape.stroke(palette.widgetStroke, lineWidth: 0.8) }
    }
}

private struct WidgetIconWash: View {
    let app: PinnedApp
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let swatch = WidgetGlass.swatch(for: app)
        let dark = colorScheme == .dark
        GeometryReader { geo in
            let reach = max(geo.size.width, geo.size.height)
            ZStack {
                (dark ? Color.black : Color(hex: 0xE8E8ED))
                RadialGradient(
                    colors: [swatch.core.opacity(dark ? 0.88 : 0.55), swatch.core.opacity(0.2), .clear],
                    center: UnitPoint(x: 0.58, y: 0.42),
                    startRadius: 2,
                    endRadius: reach * 0.92
                )
                RadialGradient(
                    colors: [swatch.halo.opacity(dark ? 0.55 : 0.32), .clear],
                    center: UnitPoint(x: 0.08, y: 0.85),
                    startRadius: 0,
                    endRadius: reach * 0.7
                )
                RadialGradient(
                    colors: [swatch.halo.opacity(dark ? 0.4 : 0.22), .clear],
                    center: UnitPoint(x: 0.95, y: 0.12),
                    startRadius: 0,
                    endRadius: reach * 0.55
                )
                LinearGradient(
                    colors: [
                        (dark ? Color.black : Color.white).opacity(dark ? 0.62 : 0.7),
                        (dark ? Color.black : Color.white).opacity(0.18),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: UnitPoint(x: 0.62, y: 0.5)
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
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
            action: action,
            attention: snapshot.attention
        ) {
            HStack(spacing: 8) {
                WidgetAppMark(app: app, systemName: snapshot.attention
                    ? "sparkle"
                    : "chevron.left.forwardslash.chevron.right", metrics: metrics, palette: palette)
                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot.label)
                        .font(Typeface.sans(metrics.widgetTemp, weight: .light))
                        .foregroundStyle(palette.widgetText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(snapshot.caption)
                        .font(Typeface.sans(metrics.widgetCaption))
                        .foregroundStyle(snapshot.attention ? palette.widgetLive : palette.widgetMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.top, -3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .help(snapshot.help)
    }
}

private struct GrokBotWidget: View {
    let snapshot: GrokBotSnapshot?
    let app: PinnedApp?
    let running: Bool
    let metrics: Theme.Metrics
    let palette: Theme.Palette
    let action: () -> Void
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}

    var body: some View {
        WidgetTile(
            kind: .grokBot,
            app: app,
            running: running,
            metrics: metrics,
            palette: palette,
            action: action,
            pageCount: snapshot?.pageCount ?? 0,
            attention: snapshot?.needsAttention == true,
            onPrevious: onPrevious,
            onNext: onNext
        ) {
            HStack(spacing: 8) {
                if let seat = snapshot?.selected {
                    GrokBotAvatar(seat: seat, size: metrics.widgetGlyph)
                } else {
                    WidgetAppMark(app: app, systemName: "face.smiling", metrics: metrics, palette: palette)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot?.selected?.headline ?? "Grok Bot")
                        .font(Typeface.sans(metrics.widgetTemp, weight: .light))
                        .foregroundStyle(palette.widgetText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(subtitle)
                        .font(Typeface.sans(metrics.widgetCaption))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.top, -3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .help(cycleHelp)
    }

    private var subtitle: String {
        snapshot?.selected?.caption
            ?? (snapshot?.signedIn == true ? "Quiet" : "Sign in")
    }

    private var subtitleColor: Color {
        if snapshot?.selected?.isWorking == true || snapshot?.selected?.needsAttention == true {
            return palette.widgetLive
        }
        return palette.widgetMuted
    }

    private var cycleHelp: String {
        let base = snapshot?.help ?? "Open Grok Bot and sign in"
        if snapshot?.canCycle == true {
            return base + "\nClick the arrows to cycle Grok Bots."
        }
        return base
    }
}

private struct DockerWidget: View {
    let snapshot: DockerSnapshot?
    let app: PinnedApp?
    let running: Bool
    let metrics: Theme.Metrics
    let palette: Theme.Palette
    let action: () -> Void
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}

    var body: some View {
        WidgetTile(
            kind: .docker,
            app: app,
            running: running,
            metrics: metrics,
            palette: palette,
            action: action,
            pageCount: snapshot?.pageCount ?? 0,
            onPrevious: onPrevious,
            onNext: onNext
        ) {
            HStack(spacing: 8) {
                WidgetAppMark(app: app, systemName: "shippingbox.fill", metrics: metrics, palette: palette)
                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot?.headline ?? "Docker")
                        .font(Typeface.sans(metrics.widgetTemp, weight: .light))
                        .foregroundStyle(palette.widgetText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(snapshot?.caption ?? "Engine off")
                        .font(Typeface.sans(metrics.widgetCaption))
                        .foregroundStyle(snapshot?.selected?.running == true
                                         ? palette.widgetLive
                                         : palette.widgetMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.top, -3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .help(cycleHelp)
    }

    private var cycleHelp: String {
        let base = snapshot?.help ?? "Open Docker Desktop"
        if snapshot?.canCycle == true {
            return base + "\nClick the arrows to cycle containers."
        }
        return base
    }
}

private struct GrokBotAvatar: View {
    let seat: GrokBotSeat
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: seat.isWorking ? 1 / 24 : 1 / 8, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GrokBotFaceView(seat: seat, size: size, time: t)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct GrokBotFaceView: View {
    let seat: GrokBotSeat
    let size: CGFloat
    let time: TimeInterval

    var body: some View {
        let bounce = seat.isWorking ? sin(time * 9) * size * 0.06 : 0
        let sway = seat.needsAttention && !seat.isWorking ? sin(time * 2.2) * size * 0.04 : 0
        let pulse = seat.isWorking ? 1 + sin(time * 6) * 0.05 : 1
        ZStack {
            GrokBotBody(shape: seat.shape)
                .fill(seat.tint.color)
            GrokBotEyes(time: time, working: seat.isWorking, size: size)
        }
        .frame(width: size, height: size)
        .scaleEffect(pulse)
        .offset(x: sway, y: bounce)
    }
}

private struct GrokBotBody: Shape {
    let shape: GrokBotFace.Shape

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)
        switch shape {
        case .circle:
            return Path(ellipseIn: inset)
        case .oval:
            return Path(ellipseIn: inset.insetBy(dx: inset.width * 0.08, dy: 0))
        case .pill:
            return Path(roundedRect: inset.insetBy(dx: 0, dy: inset.height * 0.18), cornerRadius: inset.height)
        case .pebble:
            return Path(roundedRect: inset, cornerRadius: inset.width * 0.38)
        case .square:
            return Path(roundedRect: inset, cornerRadius: inset.width * 0.22)
        case .hex:
            return polygon(in: inset, sides: 6)
        case .triangle:
            return triangle(in: inset)
        case .teardrop:
            return teardrop(in: inset)
        case .cloud:
            return cloud(in: inset)
        }
    }

    private func polygon(in rect: CGRect, sides: Int) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for i in 0..<sides {
            let angle = (Double(i) / Double(sides)) * .pi * 2 - .pi / 2
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func triangle(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    private func teardrop(in rect: CGRect) -> Path {
        let circle = CGRect(
            x: rect.minX,
            y: rect.midY - rect.width * 0.28,
            width: rect.width,
            height: rect.width * 0.72
        )
        var path = Path(ellipseIn: circle)
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.04))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.midY))
        path.closeSubpath()
        return path
    }

    private func cloud(in rect: CGRect) -> Path {
        let left = CGRect(x: rect.minX, y: rect.midY - rect.height * 0.18, width: rect.width * 0.48, height: rect.height * 0.48)
        let right = CGRect(x: rect.maxX - rect.width * 0.5, y: rect.midY - rect.height * 0.14, width: rect.width * 0.5, height: rect.height * 0.46)
        let top = CGRect(x: rect.midX - rect.width * 0.28, y: rect.minY + rect.height * 0.08, width: rect.width * 0.52, height: rect.height * 0.5)
        var path = Path(ellipseIn: left)
        path.addEllipse(in: right)
        path.addEllipse(in: top)
        return path
    }
}

private struct GrokBotEyes: View {
    let time: TimeInterval
    let working: Bool
    let size: CGFloat

    var body: some View {
        let blink = eyeScale(time)
        let gaze = working ? sin(time * 4.2) * size * 0.04 : sin(time * 0.7) * size * 0.02
        HStack(spacing: size * 0.16) {
            Capsule()
                .fill(Color.white)
                .frame(width: size * 0.11, height: size * 0.28 * blink)
                .rotationEffect(.degrees(-18))
            Capsule()
                .fill(Color.white)
                .frame(width: size * 0.11, height: size * 0.28 * blink)
                .rotationEffect(.degrees(-18))
        }
        .offset(x: gaze, y: working ? size * 0.02 : size * 0.04)
    }

    private func eyeScale(_ time: TimeInterval) -> CGFloat {
        let cycle = time.truncatingRemainder(dividingBy: working ? 1.6 : 3.4)
        if cycle > 0.12 { return 1 }
        return max(0.12, CGFloat(sin(cycle / 0.12 * .pi)))
    }
}

private extension GrokBotFace.Tint {
    var color: Color {
        let key: String
        switch self {
        case .named(let name): key = name
        case .fallback(let index):
            key = GrokBotFace.Tint.names[index % GrokBotFace.Tint.names.count]
        }
        switch key {
        case "black": return Color(hex: 0x1A1A1A)
        case "violet": return Color(hex: 0x7C5CFF)
        case "red": return Color(hex: 0xE23B3B)
        case "orange": return Color(hex: 0xF27A2C)
        case "yellow": return Color(hex: 0xF2C14E)
        case "green": return Color(hex: 0x3CB86A)
        case "blue": return Color(hex: 0x3D7EFF)
        case "pink": return Color(hex: 0xF07AB8)
        case "white": return Color(hex: 0xE8E8E8)
        default: return Color(hex: 0x6E6E73)
        }
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
    var attention: Bool = false
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
            .background { WidgetBackground(app: app, palette: palette, shape: shape) }
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
            .overlay {
                if attention {
                    WidgetAttentionBorder(shape: shape, palette: palette)
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

private struct WidgetAttentionBorder: View {
    let shape: RoundedRectangle
    let palette: Theme.Palette

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: false)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 2.6) / 2.6
            shape.stroke(
                AngularGradient(
                    colors: [
                        palette.widgetLive,
                        Color.white.opacity(0.92),
                        palette.widgetLive.opacity(0.2),
                        Color(hex: 0x5CE1FF).opacity(0.9),
                        palette.widgetLive
                    ],
                    center: .center,
                    angle: .degrees(turn * 360)
                ),
                lineWidth: 1.6
            )
        }
        .allowsHitTesting(false)
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
