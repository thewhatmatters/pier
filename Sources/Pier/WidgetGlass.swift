import AppKit
import SwiftUI

enum WidgetGlass {
    struct Swatch: Equatable {
        var core: Color
        var halo: Color
    }

    private static var cache: [String: Swatch] = [:]

    static func swatch(for app: PinnedApp) -> Swatch {
        if let cached = cache[app.bundleID] { return cached }
        let next = swatch(from: AppLaunch.icon(for: app))
        cache[app.bundleID] = next
        return next
    }

    static func swatch(from image: NSImage) -> Swatch {
        let tones = tones(from: image)
        guard let first = tones.first else {
            return Swatch(core: Color(hex: 0x5B5B60), halo: Color(hex: 0x2C2C2E))
        }
        let second = tones.dropFirst().first { tone in
            hueDistance(tone.hue, first.hue) > 0.12
        } ?? first.shifted(by: 0.18)
        return Swatch(
            core: first.boosted.color,
            halo: second.boosted.color
        )
    }

    static func tones(from image: NSImage) -> [Tone] {
        guard let rep = raster(image, side: 24) else { return [] }
        var collected: [Tone] = []
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                guard alpha > 0.4, brightness > 0.14, saturation > 0.14 else { continue }
                if brightness > 0.92 && saturation < 0.12 { continue }
                collected.append(Tone(hue: hue, saturation: saturation, brightness: brightness))
            }
        }
        return collected.sorted { $0.weight > $1.weight }
    }

    private static func raster(_ image: NSImage, side: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func hueDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let delta = abs(a - b)
        return min(delta, 1 - delta)
    }

    struct Tone: Equatable {
        var hue: CGFloat
        var saturation: CGFloat
        var brightness: CGFloat

        var weight: CGFloat { saturation * brightness }
        var boosted: Tone {
            Tone(
                hue: hue,
                saturation: min(1, saturation * 1.12),
                brightness: min(1, max(0.45, brightness * 1.08))
            )
        }
        var color: Color {
            Color(hue: hue, saturation: saturation, brightness: brightness)
        }

        func shifted(by amount: CGFloat) -> Tone {
            Tone(
                hue: (hue + amount).truncatingRemainder(dividingBy: 1),
                saturation: saturation,
                brightness: brightness
            )
        }
    }
}
