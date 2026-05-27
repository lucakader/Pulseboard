import Foundation

public enum InsightSeverity: Int, Codable, CaseIterable, Sendable {
    case calm = 0
    case info = 1
    case warning = 2
    case critical = 3

    public var title: String {
        switch self {
        case .calm: "Calm"
        case .info: "Note"
        case .warning: "Watch"
        case .critical: "Act"
        }
    }

    public var symbolName: String {
        switch self {
        case .calm: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "flame.fill"
        }
    }
}

public struct SmartInsight: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var message: String
    public var severity: InsightSeverity
    public var systemImage: String
    public var processPID: Int32?

    public init(
        id: String,
        title: String,
        message: String,
        severity: InsightSeverity,
        systemImage: String,
        processPID: Int32? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.severity = severity
        self.systemImage = systemImage
        self.processPID = processPID
    }
}

public enum SmartInsightEngine {
    public static func insights(for snapshot: MetricSnapshot, profile: FocusProfile) -> [SmartInsight] {
        guard snapshot.isWarm else {
            return [
                SmartInsight(
                    id: "warming",
                    title: "Warming up",
                    message: "Pulseboard is collecting a second sample so CPU and network rates are meaningful.",
                    severity: .info,
                    systemImage: "hourglass"
                )
            ]
        }

        var insights: [SmartInsight] = []
        appendSystemInsights(to: &insights, snapshot: snapshot, profile: profile)
        appendProcessInsights(to: &insights, snapshot: snapshot, profile: profile)

        if insights.isEmpty {
            insights.append(
                SmartInsight(
                    id: "all-clear-\(profile.rawValue)",
                    title: "\(profile.title) looks calm",
                    message: "No major pressure signals. Keep an eye on the process table if something starts feeling sluggish.",
                    severity: .calm,
                    systemImage: profile.symbolName
                )
            )
        }

        return insights
            .sorted {
                if $0.severity.rawValue == $1.severity.rawValue {
                    return $0.title < $1.title
                }
                return $0.severity.rawValue > $1.severity.rawValue
            }
            .prefix(4)
            .map { $0 }
    }

    private static func appendSystemInsights(to insights: inout [SmartInsight], snapshot: MetricSnapshot, profile: FocusProfile) {
        let system = snapshot.system

        if system.cpuUsage >= profile.cpuConcernThreshold {
            insights.append(
                SmartInsight(
                    id: "cpu-pressure",
                    title: "CPU is running hot",
                    message: "\(system.cpuUsage.percentText) total CPU in \(profile.title) mode.",
                    severity: system.cpuUsage >= 90 ? .critical : .warning,
                    systemImage: "cpu"
                )
            )
        }

        if system.memoryPressure >= profile.memoryConcernThreshold {
            insights.append(
                SmartInsight(
                    id: "memory-pressure",
                    title: "Memory pressure is high",
                    message: "\(system.memoryPressure.percentText) pressure with \(ByteFormatter.string(system.freeMemory)) free.",
                    severity: system.memoryPressure >= 90 ? .critical : .warning,
                    systemImage: "memorychip"
                )
            )
        }

        if system.diskTotal > 0 {
            let diskPercent = Double(system.diskUsed) / Double(system.diskTotal) * 100
            if diskPercent >= 88 {
                insights.append(
                    SmartInsight(
                        id: "disk-pressure",
                        title: "Disk is getting tight",
                        message: "\(diskPercent.percentText) of the root volume is in use.",
                        severity: diskPercent >= 94 ? .critical : .warning,
                        systemImage: "internaldrive"
                    )
                )
            }
        }

        let networkRate = system.networkDownRate + system.networkUpRate
        if networkRate >= 5_000_000 {
            insights.append(
                SmartInsight(
                    id: "network-spike",
                    title: "Network spike",
                    message: "\(ByteFormatter.rate(networkRate)) combined transfer right now.",
                    severity: .info,
                    systemImage: "network"
                )
            )
        }
    }

    private static func appendProcessInsights(to insights: inout [SmartInsight], snapshot: MetricSnapshot, profile: FocusProfile) {
        guard !snapshot.processes.isEmpty else { return }

        if let topCPU = snapshot.processes.max(by: { $0.cpuPercent < $1.cpuPercent }), topCPU.cpuPercent >= profile.cpuConcernThreshold * 0.5 {
            insights.append(
                SmartInsight(
                    id: "top-cpu-\(topCPU.pid)",
                    title: "\(topCPU.name) leads CPU",
                    message: "\(String(format: "%.1f%%", topCPU.cpuPercent)) CPU across \(topCPU.threadCount) threads.",
                    severity: topCPU.cpuPercent >= profile.cpuConcernThreshold ? .warning : .info,
                    systemImage: "flame",
                    processPID: topCPU.pid
                )
            )
        }

        guard snapshot.system.totalMemory > 0 else { return }
        if let topMemory = snapshot.processes.max(by: { $0.residentMemory < $1.residentMemory }) {
            let memoryShare = Double(topMemory.residentMemory) / Double(snapshot.system.totalMemory) * 100
            if memoryShare >= 8 || topMemory.residentMemory >= 2_000_000_000 {
                insights.append(
                    SmartInsight(
                        id: "top-memory-\(topMemory.pid)",
                        title: "\(topMemory.name) is memory-heavy",
                        message: "\(ByteFormatter.string(topMemory.residentMemory)) resident memory.",
                        severity: memoryShare >= 18 ? .warning : .info,
                        systemImage: "memorychip",
                        processPID: topMemory.pid
                    )
                )
            }
        }
    }
}
