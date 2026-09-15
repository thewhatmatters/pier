import Foundation

enum AppMarks {
    static let calendarBundleID = "com.apple.iCal"
    static let messagesBundleID = "com.apple.MobileSMS"

    static func calendarDay(now: Date = Date(), calendar: Calendar = .current) -> String {
        "\(calendar.component(.day, from: now))"
    }
}
