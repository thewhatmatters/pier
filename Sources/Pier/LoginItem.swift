import Foundation
import ServiceManagement

enum LoginItem {
    private static let recordedPathKey = "loginItemBundlePath"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                UserDefaults.standard.set(Bundle.main.bundlePath, forKey: recordedPathKey)
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
                UserDefaults.standard.removeObject(forKey: recordedPathKey)
            }
        } catch {
            NSLog("Pier: login item change failed — \(error.localizedDescription)")
        }
    }

    static func refreshIfMoved() {
        let current = Bundle.main.bundlePath
        guard let recorded = UserDefaults.standard.string(forKey: recordedPathKey) else { return }
        guard !(isEnabled && recorded == current) else { return }
        try? SMAppService.mainApp.unregister()
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(current, forKey: recordedPathKey)
        } catch {
            NSLog("Pier: login item refresh failed — \(error.localizedDescription)")
        }
    }
}
