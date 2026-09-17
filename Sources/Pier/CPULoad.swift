import Darwin
import Foundation

/// Host CPU ticks via `HOST_CPU_LOAD_INFO`. Two samples make a
/// System / User / Idle split; a ring of those paints the sparkline.
enum CPULoad {
    static let bundleID = "com.apple.ActivityMonitor"
    static let historyLimit = 30

    struct Ticks: Equatable {
        var user: UInt64
        var system: UInt64
        var idle: UInt64
        var nice: UInt64
    }

    struct Sample: Equatable {
        var user: Double
        var system: Double
        var idle: Double

        var load: Double { min(100, max(0, user + system)) }
    }

    static func ticks() -> Ticks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Ticks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    static func sample(previous: Ticks, current: Ticks) -> Sample? {
        let user = current.user &- previous.user &+ (current.nice &- previous.nice)
        let system = current.system &- previous.system
        let idle = current.idle &- previous.idle
        let total = user &+ system &+ idle
        guard total > 0 else { return nil }
        let scale = 100.0 / Double(total)
        return Sample(
            user: Double(user) * scale,
            system: Double(system) * scale,
            idle: Double(idle) * scale
        )
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func appending(_ history: [Sample], _ sample: Sample, limit: Int = historyLimit) -> [Sample] {
        var next = history
        next.append(sample)
        if next.count > limit {
            next.removeFirst(next.count - limit)
        }
        return next
    }
}

struct CPULoadSnapshot: Equatable {
    var current: CPULoad.Sample
    var history: [CPULoad.Sample]

    static let empty = CPULoadSnapshot(
        current: CPULoad.Sample(user: 0, system: 0, idle: 100),
        history: []
    )

    var headline: String { CPULoad.percent(current.load) }

    var help: String {
        "System \(CPULoad.percent(current.system)) · User \(CPULoad.percent(current.user)) · Idle \(CPULoad.percent(current.idle))"
    }

    func appending(_ sample: CPULoad.Sample) -> CPULoadSnapshot {
        CPULoadSnapshot(current: sample, history: CPULoad.appending(history, sample))
    }
}
