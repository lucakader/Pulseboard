import Foundation
import SwiftUI

public enum WidgetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case disk
    case network
    case topOffenders
    case processTable
    case trend

    public var id: String { rawValue }

    public var defaultTitle: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .network: "Network"
        case .topOffenders: "Top Offenders"
        case .processTable: "Processes"
        case .trend: "Trend"
        }
    }
}

public enum WidgetSize: String, Codable, CaseIterable, Sendable {
    case compact
    case regular
    case wide
}

public enum DisplayDensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case comfortable
    case compact
    case dense

    public var id: String { rawValue }

    public var rowHeight: CGFloat {
        switch self {
        case .comfortable: 28
        case .compact: 24
        case .dense: 20
        }
    }
}

public enum ChartStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case line
    case bars
    case filled

    public var id: String { rawValue }
}

public enum CanvasStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case studio
    case grid
    case paper
    case terminal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .studio: "Studio"
        case .grid: "Grid"
        case .paper: "Paper"
        case .terminal: "Terminal"
        }
    }
}

public enum CardStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case glass
    case editorial
    case outline
    case solid

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .glass: "Glass"
        case .editorial: "Editorial"
        case .outline: "Outline"
        case .solid: "Solid"
        }
    }
}

public enum ThemeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark
    case highContrast

    public var id: String { rawValue }
}

public struct ThemeConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var mode: ThemeMode
    public var density: DisplayDensity
    public var chartStyle: ChartStyle
    public var accentHex: String
    public var secondaryHex: String
    public var warningThreshold: Double
    public var criticalThreshold: Double

    public init(
        id: UUID = UUID(),
        name: String,
        mode: ThemeMode,
        density: DisplayDensity,
        chartStyle: ChartStyle,
        accentHex: String,
        secondaryHex: String,
        warningThreshold: Double = 70,
        criticalThreshold: Double = 90
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.density = density
        self.chartStyle = chartStyle
        self.accentHex = accentHex
        self.secondaryHex = secondaryHex
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
    }

    public static let aurora = ThemeConfig(
        name: "Aurora",
        mode: .system,
        density: .compact,
        chartStyle: .filled,
        accentHex: "#3DD6A7",
        secondaryHex: "#6C7CFF"
    )

    public static let graphite = ThemeConfig(
        name: "Graphite",
        mode: .dark,
        density: .dense,
        chartStyle: .line,
        accentHex: "#E6B95D",
        secondaryHex: "#78B7FF"
    )

    public static let clarity = ThemeConfig(
        name: "Clarity",
        mode: .light,
        density: .comfortable,
        chartStyle: .bars,
        accentHex: "#227C9D",
        secondaryHex: "#FA7F72"
    )

    public static let highContrast = ThemeConfig(
        name: "High Contrast",
        mode: .highContrast,
        density: .compact,
        chartStyle: .line,
        accentHex: "#FFFFFF",
        secondaryHex: "#FFD60A",
        warningThreshold: 65,
        criticalThreshold: 85
    )

    public static let neonDesk = ThemeConfig(
        name: "Neon Desk",
        mode: .dark,
        density: .compact,
        chartStyle: .filled,
        accentHex: "#58FCEC",
        secondaryHex: "#FF5C8A",
        warningThreshold: 72,
        criticalThreshold: 88
    )

    public static let fieldNotes = ThemeConfig(
        name: "Field Notes",
        mode: .light,
        density: .comfortable,
        chartStyle: .bars,
        accentHex: "#587C56",
        secondaryHex: "#D56C3D",
        warningThreshold: 68,
        criticalThreshold: 86
    )
}

public struct WidgetConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: WidgetKind
    public var title: String
    public var size: WidgetSize
    public var isVisible: Bool
    public var order: Int

    public init(
        id: UUID = UUID(),
        kind: WidgetKind,
        title: String? = nil,
        size: WidgetSize = .regular,
        isVisible: Bool = true,
        order: Int
    ) {
        self.id = id
        self.kind = kind
        self.title = title ?? kind.defaultTitle
        self.size = size
        self.isVisible = isVisible
        self.order = order
    }
}

public enum ProcessColumn: String, Codable, CaseIterable, Identifiable, Sendable {
    case name
    case pid
    case cpu
    case memory
    case threads
    case user
    case path

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .name: "Process"
        case .pid: "PID"
        case .cpu: "CPU %"
        case .memory: "Memory"
        case .threads: "Threads"
        case .user: "User"
        case .path: "Path"
        }
    }
}

public struct ColumnConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: ProcessColumn
    public var isVisible: Bool
    public var width: Double
    public var isPinned: Bool

    public init(id: ProcessColumn, isVisible: Bool, width: Double, isPinned: Bool = false) {
        self.id = id
        self.isVisible = isVisible
        self.width = width
        self.isPinned = isPinned
    }
}

public struct ProcessSort: Codable, Equatable, Sendable {
    public var column: ProcessColumn
    public var ascending: Bool

    public init(column: ProcessColumn = .cpu, ascending: Bool = false) {
        self.column = column
        self.ascending = ascending
    }
}

public struct DashboardPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var subtitle: String?
    public var symbolName: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var refreshInterval: TimeInterval
    public var theme: ThemeConfig
    public var canvasStyle: CanvasStyle?
    public var cardStyle: CardStyle?
    public var showSignalRail: Bool?
    public var widgets: [WidgetConfig]
    public var columns: [ColumnConfig]
    public var processSort: ProcessSort
    public var processFilter: String

    public init(
        id: UUID = UUID(),
        name: String,
        subtitle: String? = nil,
        symbolName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        refreshInterval: TimeInterval = 1,
        theme: ThemeConfig = .aurora,
        canvasStyle: CanvasStyle? = .studio,
        cardStyle: CardStyle? = .glass,
        showSignalRail: Bool? = true,
        widgets: [WidgetConfig] = DashboardPreset.defaultWidgets,
        columns: [ColumnConfig] = DashboardPreset.defaultColumns,
        processSort: ProcessSort = ProcessSort(),
        processFilter: String = ""
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.refreshInterval = refreshInterval
        self.theme = theme
        self.canvasStyle = canvasStyle
        self.cardStyle = cardStyle
        self.showSignalRail = showSignalRail
        self.widgets = widgets
        self.columns = columns
        self.processSort = processSort
        self.processFilter = processFilter
    }

    public static let defaultWidgets: [WidgetConfig] = [
        WidgetConfig(kind: .cpu, size: .regular, order: 0),
        WidgetConfig(kind: .memory, size: .regular, order: 1),
        WidgetConfig(kind: .disk, size: .compact, order: 2),
        WidgetConfig(kind: .network, size: .compact, order: 3),
        WidgetConfig(kind: .topOffenders, size: .wide, order: 4),
        WidgetConfig(kind: .trend, size: .wide, order: 5),
        WidgetConfig(kind: .processTable, size: .wide, order: 6)
    ]

    public static let defaultColumns: [ColumnConfig] = [
        ColumnConfig(id: .name, isVisible: true, width: 220, isPinned: true),
        ColumnConfig(id: .pid, isVisible: true, width: 72),
        ColumnConfig(id: .cpu, isVisible: true, width: 90),
        ColumnConfig(id: .memory, isVisible: true, width: 110),
        ColumnConfig(id: .threads, isVisible: true, width: 80),
        ColumnConfig(id: .user, isVisible: false, width: 96),
        ColumnConfig(id: .path, isVisible: false, width: 420)
    ]

    public static let defaults: [DashboardPreset] = [
        DashboardPreset(
            name: "Focus",
            subtitle: "Live system cockpit",
            symbolName: "sparkles.rectangle.stack",
            theme: .aurora,
            canvasStyle: .studio,
            cardStyle: .glass
        ),
        DashboardPreset(
            name: "Dense Ops",
            subtitle: "Process-heavy operations view",
            symbolName: "rectangle.grid.3x2",
            theme: .graphite,
            canvasStyle: .terminal,
            cardStyle: .outline,
            widgets: defaultWidgets.map { widget in
                var copy = widget
                copy.isVisible = widget.kind != .trend
                return copy
            }
        ),
        DashboardPreset(
            name: "Clean Room",
            subtitle: "Quiet memory-first workspace",
            symbolName: "square.dashed.inset.filled",
            theme: .clarity,
            canvasStyle: .paper,
            cardStyle: .editorial,
            processSort: ProcessSort(column: .memory, ascending: false)
        )
    ]
}

public extension DashboardPreset {
    var resolvedCanvasStyle: CanvasStyle { canvasStyle ?? .studio }
    var resolvedCardStyle: CardStyle { cardStyle ?? .glass }
    var resolvedSymbolName: String { symbolName?.isEmpty == false ? symbolName! : "rectangle.3.group" }
    var resolvedSubtitle: String { subtitle?.isEmpty == false ? subtitle! : "Live system cockpit" }
    var resolvedShowSignalRail: Bool { showSignalRail ?? true }
}

public struct SystemCounters: Equatable, Sendable {
    public var user: UInt64
    public var nice: UInt64
    public var system: UInt64
    public var idle: UInt64

    public var total: UInt64 { user + nice + system + idle }

    public init(user: UInt64 = 0, nice: UInt64 = 0, system: UInt64 = 0, idle: UInt64 = 0) {
        self.user = user
        self.nice = nice
        self.system = system
        self.idle = idle
    }
}

public struct SystemMetric: Equatable, Sendable {
    public var cpuUsage: Double
    public var counters: SystemCounters
    public var totalMemory: UInt64
    public var freeMemory: UInt64
    public var activeMemory: UInt64
    public var inactiveMemory: UInt64
    public var wiredMemory: UInt64
    public var compressedMemory: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64
    public var memoryPressure: Double
    public var diskUsed: UInt64
    public var diskTotal: UInt64
    public var networkInBytes: UInt64
    public var networkOutBytes: UInt64
    public var networkDownRate: Double
    public var networkUpRate: Double
    public var loadAverage1: Double
    public var loadAverage5: Double
    public var loadAverage15: Double
    public var logicalCPUCount: Int

    public init(
        cpuUsage: Double = 0,
        counters: SystemCounters = SystemCounters(),
        totalMemory: UInt64 = 0,
        freeMemory: UInt64 = 0,
        activeMemory: UInt64 = 0,
        inactiveMemory: UInt64 = 0,
        wiredMemory: UInt64 = 0,
        compressedMemory: UInt64 = 0,
        swapUsed: UInt64 = 0,
        swapTotal: UInt64 = 0,
        memoryPressure: Double = 0,
        diskUsed: UInt64 = 0,
        diskTotal: UInt64 = 0,
        networkInBytes: UInt64 = 0,
        networkOutBytes: UInt64 = 0,
        networkDownRate: Double = 0,
        networkUpRate: Double = 0,
        loadAverage1: Double = 0,
        loadAverage5: Double = 0,
        loadAverage15: Double = 0,
        logicalCPUCount: Int = 0
    ) {
        self.cpuUsage = cpuUsage
        self.counters = counters
        self.totalMemory = totalMemory
        self.freeMemory = freeMemory
        self.activeMemory = activeMemory
        self.inactiveMemory = inactiveMemory
        self.wiredMemory = wiredMemory
        self.compressedMemory = compressedMemory
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.memoryPressure = memoryPressure
        self.diskUsed = diskUsed
        self.diskTotal = diskTotal
        self.networkInBytes = networkInBytes
        self.networkOutBytes = networkOutBytes
        self.networkDownRate = networkDownRate
        self.networkUpRate = networkUpRate
        self.loadAverage1 = loadAverage1
        self.loadAverage5 = loadAverage5
        self.loadAverage15 = loadAverage15
        self.logicalCPUCount = logicalCPUCount
    }
}

public struct ProcessMetric: Identifiable, Equatable, Sendable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var parentPID: Int32
    public var name: String
    public var path: String
    public var uid: UInt32
    public var residentMemory: UInt64
    public var virtualMemory: UInt64
    public var cpuTimeNanoseconds: UInt64
    public var cpuPercent: Double
    public var threadCount: Int
    public var status: Int32
    public var startDate: Date?

    public init(
        pid: Int32,
        parentPID: Int32 = 0,
        name: String,
        path: String = "",
        uid: UInt32 = 0,
        residentMemory: UInt64 = 0,
        virtualMemory: UInt64 = 0,
        cpuTimeNanoseconds: UInt64 = 0,
        cpuPercent: Double = 0,
        threadCount: Int = 0,
        status: Int32 = 0,
        startDate: Date? = nil
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.name = name
        self.path = path
        self.uid = uid
        self.residentMemory = residentMemory
        self.virtualMemory = virtualMemory
        self.cpuTimeNanoseconds = cpuTimeNanoseconds
        self.cpuPercent = cpuPercent
        self.threadCount = threadCount
        self.status = status
        self.startDate = startDate
    }
}

public struct MetricSnapshot: Equatable, Sendable {
    public var timestamp: Date
    public var system: SystemMetric
    public var processes: [ProcessMetric]
    public var isWarm: Bool

    public init(timestamp: Date = Date(), system: SystemMetric = SystemMetric(), processes: [ProcessMetric] = [], isWarm: Bool = false) {
        self.timestamp = timestamp
        self.system = system
        self.processes = processes
        self.isWarm = isWarm
    }

    public static let empty = MetricSnapshot(timestamp: Date(timeIntervalSince1970: 0))
}
