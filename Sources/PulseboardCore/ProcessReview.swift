import Foundation

public enum ProcessReviewReason: String, Codable, CaseIterable, Sendable {
    case highCPU
    case highMemory
    case manyThreads

    public var title: String {
        switch self {
        case .highCPU: "High CPU"
        case .highMemory: "High memory"
        case .manyThreads: "Many threads"
        }
    }
}

public struct ProcessReviewCandidate: Identifiable, Equatable, Sendable {
    public var id: Int32 { process.pid }
    public var process: ProcessMetric
    public var reasons: [ProcessReviewReason]
    public var score: Double

    public init(process: ProcessMetric, reasons: [ProcessReviewReason], score: Double) {
        self.process = process
        self.reasons = reasons
        self.score = score
    }
}

public enum ProcessReviewEngine {
    public static func stableRows(from liveRows: [ProcessMetric], heldPIDs: [Int32]) -> [ProcessMetric] {
        guard !heldPIDs.isEmpty else { return liveRows }

        let latestByPID = Dictionary(liveRows.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<Int32>()
        var rows: [ProcessMetric] = []
        rows.reserveCapacity(liveRows.count)

        for pid in heldPIDs {
            guard let process = latestByPID[pid], !seen.contains(pid) else { continue }
            rows.append(process)
            seen.insert(pid)
        }

        for process in liveRows where !seen.contains(process.pid) {
            rows.append(process)
        }

        return rows
    }

    public static func candidates(
        from processes: [ProcessMetric],
        excluding keptPIDs: Set<Int32> = []
    ) -> [ProcessReviewCandidate] {
        processes.compactMap { process in
            guard !keptPIDs.contains(process.pid), isUserReviewable(process) else { return nil }

            var reasons: [ProcessReviewReason] = []
            if process.cpuPercent >= 20 {
                reasons.append(.highCPU)
            }
            if process.residentMemory >= 750 * 1_024 * 1_024 {
                reasons.append(.highMemory)
            }
            if process.threadCount >= 80 {
                reasons.append(.manyThreads)
            }

            guard !reasons.isEmpty else { return nil }

            let memoryMegabytes = Double(process.residentMemory) / 1_024 / 1_024
            let score = process.cpuPercent * 2 + memoryMegabytes / 64 + Double(process.threadCount) / 5
            return ProcessReviewCandidate(process: process, reasons: reasons, score: score)
        }
        .sorted {
            if $0.score == $1.score {
                return $0.process.pid < $1.process.pid
            }
            return $0.score > $1.score
        }
        .prefix(8)
        .map { $0 }
    }

    private static func isUserReviewable(_ process: ProcessMetric) -> Bool {
        guard process.pid > 1 else { return false }

        let protectedNames: Set<String> = [
            "kernel_task",
            "launchd",
            "WindowServer",
            "loginwindow",
            "systemstats",
            "runningboardd",
            "trustd",
            "notifyd",
            "syslogd",
            "powerd",
            "configd",
            "distnoted",
            "cfprefsd",
            "taskgated",
            "opendirectoryd",
            "softwareupdated",
            "backupd",
            "mds",
            "mdworker",
            "fseventsd"
        ]
        if protectedNames.contains(process.name) {
            return false
        }

        let protectedPrefixes = [
            "/System/",
            "/usr/libexec/",
            "/usr/sbin/",
            "/sbin/",
            "/Library/Apple/"
        ]
        return !protectedPrefixes.contains { process.path.hasPrefix($0) }
    }
}
