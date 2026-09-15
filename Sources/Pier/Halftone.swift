import AppKit
import SwiftUI

/// Stippled symbol, the widget glyph language: circular dots on a
/// staggered grid, sized by the source symbol's coverage. Looks printed,
/// not pixelated-cheap.
enum Halftone {
    private static var cache: [String: NSImage] = [:]

    static func image(systemName: String, pointSize: CGFloat) -> NSImage {
        let key = "\(systemName):\(Int(pointSize.rounded()))"
        if let cached = cache[key] { return cached }
        let rendered = render(systemName: systemName, pointSize: max(12, pointSize))
        cache[key] = rendered
        return rendered
    }

    private static func render(systemName: String, pointSize: CGFloat) -> NSImage {
        let scale: CGFloat = 4
        let pixel = Int((pointSize * scale).rounded())
        let bitmapSize = NSSize(width: pixel, height: pixel)
        let output = NSImage(size: NSSize(width: pointSize, height: pointSize))

        guard
            let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
                .withSymbolConfiguration(
                    NSImage.SymbolConfiguration(pointSize: pointSize * scale * 0.78, weight: .medium)
                        .applying(.init(hierarchicalColor: .white))
                ),
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixel,
                pixelsHigh: pixel,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .calibratedRGB,
                bytesPerRow: 0,
                bitsPerPixel: 32
            )
        else { return output }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: bitmapSize)).fill()
        let inset = CGFloat(pixel) * 0.08
        symbol.draw(
            in: NSRect(x: inset, y: inset, width: CGFloat(pixel) - inset * 2, height: CGFloat(pixel) - inset * 2),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        let coverage = Coverage(bitmap: bitmap)
        let pitch = max(2.2, pointSize / 11) * scale
        let dots = NSImage(size: bitmapSize)
        dots.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: bitmapSize)).fill()
        NSColor.white.setFill()

        var row = 0
        var y = pitch * 0.45
        while y < CGFloat(pixel) {
            var x = (row.isMultiple(of: 2) ? 0.45 : 0.95) * pitch
            while x < CGFloat(pixel) {
                let amount = pow(coverage.sample(x: x, y: y, radius: pitch * 0.55), 0.72)
                let radius = (pitch * 0.48) * amount
                if radius > 0.4 {
                    NSBezierPath(ovalIn: NSRect(
                        x: x - radius,
                        y: y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )).fill()
                }
                x += pitch
            }
            y += pitch * 0.86
            row += 1
        }
        dots.unlockFocus()

        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        dots.draw(
            in: NSRect(origin: .zero, size: output.size),
            from: NSRect(origin: .zero, size: bitmapSize),
            operation: .copy,
            fraction: 1
        )
        output.unlockFocus()
        output.isTemplate = true
        return output
    }

    private struct Coverage {
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let data: [UInt8]

        init(bitmap: NSBitmapImageRep) {
            width = bitmap.pixelsWide
            height = bitmap.pixelsHigh
            bytesPerRow = bitmap.bytesPerRow
            if let pointer = bitmap.bitmapData {
                data = Array(UnsafeBufferPointer(start: pointer, count: bytesPerRow * height))
            } else {
                data = []
            }
        }

        func sample(x: CGFloat, y: CGFloat, radius: CGFloat) -> CGFloat {
            guard !data.isEmpty else { return 0 }
            let r = max(1, Int(radius.rounded()))
            let cx = Int(x.rounded())
            let cy = Int(y.rounded())
            var total: CGFloat = 0
            var count: CGFloat = 0
            for dy in -r...r {
                for dx in -r...r {
                    let px = cx + dx
                    let py = cy + dy
                    guard px >= 0, py >= 0, px < width, py < height else { continue }
                    let offset = py * bytesPerRow + px * 4
                    guard offset + 3 < data.count else { continue }
                    // Prefer alpha; fall back to luma if the symbol was drawn opaque-on-clear.
                    let alpha = CGFloat(data[offset + 3]) / 255
                    let luma = (CGFloat(data[offset]) + CGFloat(data[offset + 1]) + CGFloat(data[offset + 2])) / (255 * 3)
                    total += max(alpha, luma)
                    count += 1
                }
            }
            return count == 0 ? 0 : min(1, total / count)
        }
    }
}

struct HalftoneSymbol: View {
    var systemName: String
    var size: CGFloat
    var color: Color = .white

    var body: some View {
        Image(nsImage: Halftone.image(systemName: systemName, pointSize: size))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
