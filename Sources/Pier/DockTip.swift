import AppKit
import SwiftUI

/// Hover name chip for icon-only tiles. Widgets stay quiet until their
/// richer popover lands. Lives in its own panel so the dock window can
/// stay tight and nonactivating.
enum DockTip {
    static let delay: TimeInterval = 0.4
    static let hideGrace: TimeInterval = 0.06
    static let gap: CGFloat = 6
    static let fontSize: CGFloat = 12
    /// Room for the drop shadow to fade — same plate we used to see
    /// around the dock when the window was tight to the capsule.
    static let bleed: CGFloat = 12

    /// App icons show the name. Widgets wait for the detailed popover.
    static func title(app: PinnedApp?, kind: WidgetKind?) -> String? {
        guard kind == nil else { return nil }
        let name = app?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    static func labelSize(title: String) -> NSSize {
        let font = NSFont(name: "Geist Medium", size: fontSize)
            ?? NSFont(name: Typeface.sansName, size: fontSize)
            ?? .systemFont(ofSize: fontSize, weight: .medium)
        let text = (title as NSString).size(withAttributes: [.font: font])
        return NSSize(
            width: max(44, ceil(text.width) + 32),
            height: max(24, ceil(text.height) + 16)
        )
    }

    /// Window rect: chip size plus bleed, centered on the icon, chip
    /// sitting just above the glass bar.
    static func frame(
        labelSize: NSSize,
        icon: NSRect,
        barTop: CGFloat,
        screen: NSRect
    ) -> NSRect {
        let width = labelSize.width + bleed * 2
        let height = labelSize.height + bleed * 2
        var x = icon.midX - width / 2
        let minX = screen.minX + 8
        let maxX = screen.maxX - width - 8
        if maxX >= minX {
            x = min(max(x, minX), maxX)
        }
        return NSRect(
            x: x.rounded(),
            y: (barTop + gap - bleed).rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }
}

@MainActor
final class DockTipController {
    static let shared = DockTipController()

    private var panel: DockTipWindow?
    private var pending: Task<Void, Never>?
    private var visibleID: String?

    func enter(id: String, title: String, icon: NSRect, barTop: CGFloat, screen: NSRect) {
        pending?.cancel()
        if visibleID != nil {
            present(id: id, title: title, icon: icon, barTop: barTop, screen: screen)
            return
        }
        pending = Task {
            try? await Task.sleep(nanoseconds: UInt64(DockTip.delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            present(id: id, title: title, icon: icon, barTop: barTop, screen: screen)
        }
    }

    func leave(id: String) {
        pending?.cancel()
        guard visibleID == id else { return }
        pending = Task {
            try? await Task.sleep(nanoseconds: UInt64(DockTip.hideGrace * 1_000_000_000))
            guard !Task.isCancelled, visibleID == id else { return }
            hide()
        }
    }

    func hide() {
        pending?.cancel()
        pending = nil
        visibleID = nil
        panel?.orderOut(nil)
    }

    private func present(id: String, title: String, icon: NSRect, barTop: CGFloat, screen: NSRect) {
        let window = panel ?? DockTipWindow()
        panel = window
        window.show(title: title, icon: icon, barTop: barTop, screen: screen)
        visibleID = id
    }
}

private final class DockTipWindow: NSPanel {
    private let hosting = NSHostingView(rootView: DockTipView(title: "", palette: Theme.palette(.dark)))

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = .clear
        hosting.layer?.masksToBounds = false
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(title: String, icon: NSRect, barTop: CGFloat, screen: NSRect) {
        let palette = Settings.shared.palette
        appearance = Settings.shared.appearance.nsAppearance
        hosting.rootView = DockTipView(title: title, palette: palette)
        let frame = DockTip.frame(
            labelSize: DockTip.labelSize(title: title),
            icon: icon,
            barTop: barTop,
            screen: screen
        )
        setFrame(frame, display: true)
        orderFrontRegardless()
    }
}

private struct DockTipView: View {
    let title: String
    let palette: Theme.Palette

    var body: some View {
        Text(title)
            .font(Typeface.sans(DockTip.fontSize, weight: .medium))
            .foregroundStyle(palette.textPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background { DockTipBackground(palette: palette) }
            .padding(DockTip.bleed)
            .background(Color.clear)
    }
}

private struct DockTipBackground: View {
    let palette: Theme.Palette
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        shape
            .fill(palette.barFill)
            .overlay { shape.stroke(palette.barStroke, lineWidth: 0.8) }
            .shadow(color: palette.barShadow, radius: 8, y: 2)
    }
}
