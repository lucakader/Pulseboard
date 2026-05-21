import Foundation
import PulseboardSystem

public protocol SystemSampling {
    func capture(previous: MetricSnapshot?) -> MetricSnapshot
}

public enum MetricCalculator {
    public static func cpuUsage(current: SystemCounters, previous: SystemCounters?) -> Double {
        guard let previous else { return 0 }

        let totalDelta = current.total.saturatingSubtract(previous.total)
        let idleDelta = current.idle.saturatingSubtract(previous.idle)

        guard totalDelta > 0 else { return 0 }
        return max(0, min(100, Double(totalDelta - idleDelta) / Double(totalDelta) * 100))
    }

    public static func processCPUPercent(current: UInt64, previous: UInt64?, elapsed: TimeInterval) -> Double {
        guard let previous, elapsed > 0 else { return 0 }
        let delta = current.saturatingSubtract(previous)
        return max(0, Double(delta) / 1_000_000_000 / elapsed * 100)
    }

    public static func rate(current: UInt64, previous: UInt64?, elapsed: TimeInterval) -> Double {
        guard let previous, elapsed > 0 else { return 0 }
        let delta = current.saturatingSubtract(previous)
        return Double(delta) / elapsed
    }

    public static func memoryPressure(total: UInt64, free: UInt64, inactive: UInt64, compressed: UInt64, wired: UInt64) -> Double {
        guard total > 0 else { return 0 }
        let reclaimable = Double(free) + Double(inactive) * 0.55
        let committed = max(0, Double(total) - reclaimable + Double(compressed) * 0.25 + Double(wired) * 0.15)
        return max(0, min(100, committed / Double(total) * 100))
    }
}

public final class CSystemSampler: SystemSampling {
    public init() {}

    public func capture(previous: MetricSnapshot?) -> MetricSnapshot {
        let timestamp = Date()
        var systemSample = PBSystemSample()
        PBReadSystem(&systemSample)

        let counters = SystemCounters(
            user: systemSample.cpu_user_ticks,
            nice: systemSample.cpu_nice_ticks,
            system: systemSample.cpu_system_ticks,
            idle: systemSample.cpu_idle_ticks
        )

        let elapsed = max(0.001, timestamp.timeIntervalSince(previous?.timestamp ?? timestamp))
        let disk = Self.rootDiskUsage()
        let system = SystemMetric(
            cpuUsage: MetricCalculator.cpuUsage(current: counters, previous: previous?.system.counters),
            counters: counters,
            totalMemory: systemSample.total_memory,
            freeMemory: systemSample.free_memory,
            activeMemory: systemSample.active_memory,
            inactiveMemory: systemSample.inactive_memory,
            wiredMemory: systemSample.wired_memory,
            compressedMemory: systemSample.compressed_memory,
            swapUsed: systemSample.swap_used,
            swapTotal: systemSample.swap_total,
            memoryPressure: MetricCalculator.memoryPressure(
                total: systemSample.total_memory,
                free: systemSample.free_memory,
                inactive: systemSample.inactive_memory,
                compressed: systemSample.compressed_memory,
                wired: systemSample.wired_memory
            ),
            diskUsed: disk.used,
            diskTotal: disk.total,
            networkInBytes: systemSample.network_in_bytes,
            networkOutBytes: systemSample.network_out_bytes,
            networkDownRate: MetricCalculator.rate(
                current: systemSample.network_in_bytes,
                previous: previous?.system.networkInBytes,
                elapsed: elapsed
            ),
            networkUpRate: MetricCalculator.rate(
                current: systemSample.network_out_bytes,
                previous: previous?.system.networkOutBytes,
                elapsed: elapsed
            ),
            loadAverage1: systemSample.load_average_1,
            loadAverage5: systemSample.load_average_5,
            loadAverage15: systemSample.load_average_15,
            logicalCPUCount: Int(systemSample.logical_cpu_count)
        )

        let previousCPUTime = Dictionary(uniqueKeysWithValues: previous?.processes.map { ($0.pid, $0.cpuTimeNanoseconds) } ?? [])
        let processes = Self.processes(previousCPUTime: previousCPUTime, elapsed: elapsed)

        return MetricSnapshot(
            timestamp: timestamp,
            system: system,
            processes: processes,
            isWarm: previous != nil
        )
    }

    private static func processes(previousCPUTime: [Int32: UInt64], elapsed: TimeInterval) -> [ProcessMetric] {
        let count = max(32, Int(PBProcessCount()))
        var samples = Array(repeating: PBProcessSample(), count: count + 64)
        let observed = PBListProcesses(&samples, samples.count)
        guard observed > 0 else { return [] }

        return samples.prefix(Int(observed)).map { sample in
            let name = cString(sample.name)
            let path = cString(sample.path)
            let cpuTime = sample.total_user_time_ns + sample.total_system_time_ns
            let startDate: Date?
            if sample.start_time_sec > 0 {
                startDate = Date(timeIntervalSince1970: TimeInterval(sample.start_time_sec) + TimeInterval(sample.start_time_usec) / 1_000_000)
            } else {
                startDate = nil
            }

            return ProcessMetric(
                pid: sample.pid,
                parentPID: sample.ppid,
                name: name.isEmpty ? "PID \(sample.pid)" : name,
                path: path,
                uid: sample.uid,
                residentMemory: sample.resident_size,
                virtualMemory: sample.virtual_size,
                cpuTimeNanoseconds: cpuTime,
                cpuPercent: MetricCalculator.processCPUPercent(
                    current: cpuTime,
                    previous: previousCPUTime[sample.pid],
                    elapsed: elapsed
                ),
                threadCount: Int(sample.thread_count),
                status: sample.status,
                startDate: startDate
            )
        }
    }

    private static func rootDiskUsage() -> (used: UInt64, total: UInt64) {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]

        guard let values = try? url.resourceValues(forKeys: keys) else {
            return (0, 0)
        }

        let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
        let availableValue = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        let available = UInt64(max(Int64(0), availableValue))
        return (total.saturatingSubtract(available), total)
    }

    private static func cString<T>(_ tuple: T) -> String {
        var copy = tuple
        return withUnsafePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { charPointer in
                String(cString: charPointer)
            }
        }
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}
