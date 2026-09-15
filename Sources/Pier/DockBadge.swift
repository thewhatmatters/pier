import AppKit
import ApplicationServices
import CoreFoundation
import Foundation

/// Unread marks other apps put on the system Dock.
/// Slack and Discord publish Launch Services `StatusLabel`. Messages and
/// similar system apps do not — those come from the Dock tile's
/// `AXStatusLabel` once Pier is allowed to control the computer.
enum DockBadge {
    enum Mark: Equatable {
        case count(String)
        case dot
    }

    private static let session: Int32 = -2
    private static let statusKey = "StatusLabel"
    private static var didPromptAccess = false

    private static let copyRunning: (@convention(c) (Int32) -> Unmanaged<CFArray>?)? = {
        guard
            let bundle = CFBundleGetBundleWithIdentifier("com.apple.CoreServices" as CFString),
            let pointer = CFBundleGetFunctionPointerForName(bundle, "_LSCopyRunningApplicationArray" as CFString)
        else { return nil }
        return unsafeBitCast(pointer, to: (@convention(c) (Int32) -> Unmanaged<CFArray>?).self)
    }()

    private static let copyInfo: (@convention(c) (Int32, CFTypeRef, CFArray?) -> Unmanaged<CFDictionary>?)? = {
        guard
            let bundle = CFBundleGetBundleWithIdentifier("com.apple.CoreServices" as CFString),
            let pointer = CFBundleGetFunctionPointerForName(bundle, "_LSCopyApplicationInformation" as CFString)
        else { return nil }
        return unsafeBitCast(pointer, to: (@convention(c) (Int32, CFTypeRef, CFArray?) -> Unmanaged<CFDictionary>?).self)
    }()

    static var isAccessTrusted: Bool { AXIsProcessTrusted() }

    static func labels(for bundleIDs: Set<String>) -> [String: String] {
        guard !bundleIDs.isEmpty else { return [:] }
        var result = labelsFromLaunchServices()
        for (bundleID, raw) in labelsFromDock() where result[bundleID] == nil {
            result[bundleID] = raw
        }
        return result.filter { bundleIDs.contains($0.key) }
    }

    static func labelsByBundleID() -> [String: String] {
        var result = labelsFromLaunchServices()
        for (bundleID, raw) in labelsFromDock() where result[bundleID] == nil {
            result[bundleID] = raw
        }
        return result
    }

    static func mark(from raw: String?) -> Mark? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if ["•", "●", "∙", "·", "."].contains(trimmed) { return .dot }
        if let value = Int(trimmed) {
            guard value > 0 else { return nil }
            return .count(value > 99 ? "99+" : String(value))
        }
        if trimmed.hasSuffix("+"), let value = Int(trimmed.dropLast()), value > 0 {
            return .count(value > 99 ? "99+" : "\(value)+")
        }
        return .count(trimmed)
    }

    static func help(appName: String, raw: String?) -> String {
        switch mark(from: raw) {
        case .count(let text):
            return "\(appName) — \(text) unread"
        case .dot:
            return "\(appName) — unread"
        case nil:
            return appName
        }
    }

    static func bundleID(title: String?, url: URL?) -> String? {
        if let url {
            if let id = Bundle(url: url)?.bundleIdentifier, !id.isEmpty {
                return id
            }
            let path = url.path
            if let pin = Settings.shared.pinnedApps.first(where: { $0.path == path }) {
                return pin.bundleID
            }
        }
        if let title, !title.isEmpty {
            if ["Messages", "iMessage"].contains(title) {
                return AppMarks.messagesBundleID
            }
            if let pin = Settings.shared.pinnedApps.first(where: { $0.name == title }) {
                return pin.bundleID
            }
        }
        return nil
    }

    /// Accessory apps only get the Accessibility sheet when they are active.
    @MainActor
    static func requestAccessFromUser() {
        if AXIsProcessTrusted() { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSApp.setActivationPolicy(.accessory)
    }

    @MainActor
    static func promptAccessIfNeeded() {
        guard !didPromptAccess, !AXIsProcessTrusted() else { return }
        didPromptAccess = true
        requestAccessFromUser()
    }

    static func openAccessSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private static func labelsFromLaunchServices() -> [String: String] {
        guard let copyRunning, let copyInfo else { return [:] }
        guard let running = copyRunning(session)?.takeRetainedValue() as? [CFTypeRef] else { return [:] }
        var result: [String: String] = [:]
        for asn in running {
            guard let info = copyInfo(session, asn, nil)?.takeRetainedValue() as NSDictionary? else { continue }
            guard let bundleID = info["CFBundleIdentifier"] as? String,
                  let raw = label(from: info[statusKey])
            else { continue }
            result[bundleID] = raw
        }
        return result
    }

    private static func labelsFromDock() -> [String: String] {
        guard AXIsProcessTrusted() else { return [:] }
        guard let pid = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first(where: { !$0.isTerminated })?
            .processIdentifier
        else { return [:] }

        var result: [String: String] = [:]
        collect(from: AXUIElementCreateApplication(pid), depth: 0, into: &result)
        return result
    }

    private static func collect(from element: AXUIElement, depth: Int, into result: inout [String: String]) {
        guard depth < 6 else { return }
        var status: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, "AXStatusLabel" as CFString, &status)
        if error == .success || error == .noValue {
            if let raw = label(from: status),
               let bundleID = bundleID(title: stringValue(element, kAXTitleAttribute as CFString), url: urlValue(element)) {
                result[bundleID] = raw
            }
        }
        for child in children(of: element) {
            collect(from: child, depth: depth + 1, into: &result)
        }
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement]
        else { return [] }
        return elements
    }

    private static func stringValue(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private static func urlValue(_ element: AXUIElement) -> URL? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success else {
            return nil
        }
        if let url = value as? URL { return url }
        if let url = value as? NSURL { return url as URL }
        return nil
    }

    private static func label(from value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        guard let status = value as? [AnyHashable: Any] ?? (value as? NSDictionary) as? [AnyHashable: Any],
              let inner = status["label"] ?? status["Label"]
        else { return nil }
        return label(from: inner)
    }
}
