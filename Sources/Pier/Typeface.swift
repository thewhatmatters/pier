import AppKit
import CoreText
import SwiftUI

enum Typeface {
    static let sansName = "Geist"
    static let monoName = "Geist Mono"

    static func register() {
        for folder in folders() {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil
            ) else { continue }
            for file in files where ["ttf", "otf"].contains(file.pathExtension.lowercased()) {
                CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
            }
        }
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(sansName, size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(monoName, size: size).weight(weight)
    }

    static func isAvailable(_ name: String) -> Bool {
        NSFont(name: name, size: 12) != nil
    }

    private static func folders() -> [URL] {
        var urls: [URL] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts") {
            urls.append(bundled)
        }
        #if SWIFT_PACKAGE
        urls.append(Bundle.module.bundleURL.appendingPathComponent("Fonts"))
        if let resource = Bundle.module.resourceURL?.appendingPathComponent("Fonts") {
            urls.append(resource)
        }
        #endif
        return urls
    }
}
