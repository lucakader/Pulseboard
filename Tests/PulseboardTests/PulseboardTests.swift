import XCTest
@testable import PulseboardCore

@MainActor
final class PulseboardTests: XCTestCase {
    func testThemeAndColumnRoundTrip() throws {
        let preset = DashboardPreset(
            name: "Round Trip",
            subtitle: "Custom cockpit",
            symbolName: "sparkles.rectangle.stack",
            focusProfile: .coding,
            refreshInterval: 1.5,
            theme: .graphite,
            canvasStyle: .terminal,
            cardStyle: .outline,
            showSignalRail: false,
            columns: DashboardPreset.defaultColumns.map { column in
                var copy = column
                copy.isVisible.toggle()
                return copy
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(preset)
        let decoded = try decoder.decode(DashboardPreset.self, from: data)

        XCTAssertEqual(decoded.name, "Round Trip")
        XCTAssertEqual(decoded.subtitle, "Custom cockpit")
        XCTAssertEqual(decoded.symbolName, "sparkles.rectangle.stack")
        XCTAssertEqual(decoded.resolvedFocusProfile, .coding)
        XCTAssertEqual(decoded.theme, .graphite)
        XCTAssertEqual(decoded.resolvedCanvasStyle, .terminal)
        XCTAssertEqual(decoded.resolvedCardStyle, .outline)
        XCTAssertFalse(decoded.resolvedShowSignalRail)
        XCTAssertEqual(decoded.columns, preset.columns)
        XCTAssertEqual(decoded.refreshInterval, 1.5)
    }

    func testPresetStorePersistsJSON() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("presets.json")

        let store = PresetStore(storageURL: url)
        var preset = store.selectedPreset
        preset.name = "Saved Studio"
        preset.theme = .neonDesk
        preset.canvasStyle = .grid
        preset.cardStyle = .solid
        store.selectedPreset = preset

        let reloaded = PresetStore(storageURL: url)
        XCTAssertEqual(reloaded.presets.first?.name, "Saved Studio")
        XCTAssertEqual(reloaded.presets.first?.theme, .neonDesk)
        XCTAssertEqual(reloaded.presets.first?.resolvedCanvasStyle, .grid)
        XCTAssertEqual(reloaded.presets.first?.resolvedCardStyle, .solid)
    }

    func testApplyingFocusProfileTunesDashboardWithoutRenamingIt() {
        var preset = DashboardPreset(name: "My Workbench", theme: .aurora)
        preset.widgets[0].title = "Custom CPU"

        preset.applyFocusProfile(.battery)

        XCTAssertEqual(preset.name, "My Workbench")
        XCTAssertEqual(preset.resolvedFocusProfile, .battery)
        XCTAssertEqual(preset.refreshInterval, FocusProfile.battery.refreshInterval)
        XCTAssertEqual(preset.theme, FocusProfile.battery.theme)
        XCTAssertEqual(preset.processSort, FocusProfile.battery.processSort)
        XCTAssertEqual(preset.widgets.first(where: { $0.kind == .cpu })?.title, "Custom CPU")
        XCTAssertEqual(
            Set(preset.widgets.filter(\.isVisible).map(\.kind)),
            FocusProfile.battery.visibleWidgets
        )
    }

    func testPresetNormalizationRepairsEditableState() {
        let preset = DashboardPreset(
            name: "   ",
            subtitle: "   ",
            symbolName: "  cpu  ",
            refreshInterval: 42,
            theme: ThemeConfig(
                name: "   ",
                mode: .dark,
                density: .dense,
                chartStyle: .line,
                accentHex: "not-a-color",
                secondaryHex: "abc",
                warningThreshold: 95,
                criticalThreshold: 15
            ),
            widgets: [
                WidgetConfig(kind: .cpu, title: "   ", size: .compact, order: 4),
                WidgetConfig(kind: .cpu, title: "Duplicate", size: .wide, order: 5)
            ],
            columns: [
                ColumnConfig(id: .name, isVisible: true, width: 12),
                ColumnConfig(id: .cpu, isVisible: true, width: 2_000)
            ]
        ).normalized()

        XCTAssertEqual(preset.name, "Untitled Dashboard")
        XCTAssertNil(preset.subtitle)
        XCTAssertEqual(preset.resolvedSymbolName, "cpu")
        XCTAssertEqual(preset.refreshInterval, 5)
        XCTAssertEqual(preset.theme.name, "Custom Theme")
        XCTAssertEqual(preset.theme.accentHex, ThemeConfig.aurora.accentHex)
        XCTAssertEqual(preset.theme.secondaryHex, "#ABC")
        XCTAssertLessThanOrEqual(preset.theme.warningThreshold, preset.theme.criticalThreshold)
        XCTAssertEqual(Set(preset.widgets.map(\.kind)), Set(WidgetKind.allCases))
        XCTAssertEqual(preset.widgets.map(\.order), Array(0..<preset.widgets.count))
        XCTAssertEqual(preset.widgets.first?.title, WidgetKind.cpu.defaultTitle)
        XCTAssertEqual(preset.columns.count, DashboardPreset.defaultColumns.count)
        XCTAssertEqual(preset.columns.first(where: { $0.id == .name })?.width, 48)
        XCTAssertEqual(preset.columns.first(where: { $0.id == .cpu })?.width, 900)
    }

    func testCPUPercentRequiresPreviousSample() {
        XCTAssertEqual(MetricCalculator.processCPUPercent(current: 10_000, previous: nil, elapsed: 1), 0)
        XCTAssertEqual(MetricCalculator.processCPUPercent(current: 2_000_000_000, previous: 1_000_000_000, elapsed: 1), 100, accuracy: 0.001)
        XCTAssertEqual(MetricCalculator.processCPUPercent(current: 3_000_000_000, previous: 1_000_000_000, elapsed: 0.5), 400, accuracy: 0.001)
    }

    func testLiveSamplerDoesNotCrashOnProtectedProcesses() {
        let sampler = CSystemSampler()
        let first = sampler.capture(previous: nil)
        let second = sampler.capture(previous: first)

        XCTAssertFalse(first.processes.isEmpty)
        XCTAssertFalse(second.processes.isEmpty)
        XCTAssertTrue(second.system.cpuUsage >= 0)
    }

    func testBackgroundRefreshUpdatesStore() async throws {
        let expected = MetricSnapshot(
            timestamp: Date(),
            system: SystemMetric(cpuUsage: 42),
            processes: [
                ProcessMetric(pid: 7, name: "Fixture")
            ],
            isWarm: true
        )
        let store = MonitorStore(sampler: FixedSampler(snapshot: expected))

        store.refreshInBackground()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(store.snapshot.system.cpuUsage, 42)
        XCTAssertEqual(store.snapshot.processes.first?.name, "Fixture")
        XCTAssertFalse(store.isRefreshing)
    }

    func testSmartInsightsSurfaceActionableSignals() {
        let snapshot = MetricSnapshot(
            system: SystemMetric(
                cpuUsage: 92,
                totalMemory: 16_000_000_000,
                freeMemory: 800_000_000,
                memoryPressure: 91,
                diskUsed: 940,
                diskTotal: 1_000,
                networkDownRate: 6_000_000,
                networkUpRate: 500_000
            ),
            processes: [
                ProcessMetric(pid: 42, name: "Renderer", residentMemory: 3_500_000_000, cpuPercent: 76, threadCount: 18)
            ],
            isWarm: true
        )

        let insights = SmartInsightEngine.insights(for: snapshot, profile: .balanced)

        XCTAssertTrue(insights.contains { $0.id == "cpu-pressure" })
        XCTAssertTrue(insights.contains { $0.id == "memory-pressure" })
        XCTAssertTrue(insights.contains { $0.processPID == 42 })
        XCTAssertEqual(insights.first?.severity, .critical)
        XCTAssertLessThanOrEqual(insights.count, 4)
    }

    func testSmartInsightsReturnCalmFallback() {
        let snapshot = MetricSnapshot(
            system: SystemMetric(
                cpuUsage: 10,
                totalMemory: 16_000_000_000,
                freeMemory: 8_000_000_000,
                memoryPressure: 22,
                diskUsed: 200,
                diskTotal: 1_000
            ),
            processes: [
                ProcessMetric(pid: 1, name: "Quiet", residentMemory: 120_000_000, cpuPercent: 2, threadCount: 3)
            ],
            isWarm: true
        )

        let insights = SmartInsightEngine.insights(for: snapshot, profile: .coding)

        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights.first?.severity, .calm)
    }

    func testSortingThousandSyntheticRowsIsStableEnough() {
        var rows: [ProcessMetric] = []
        rows.reserveCapacity(1_000)

        for index in 0..<1_000 {
            let metric = ProcessMetric(
                pid: Int32(index),
                name: "Process \(1_000 - index)",
                residentMemory: UInt64(index) * 1_024 * 1_024,
                cpuTimeNanoseconds: UInt64(index) * 1_000,
                cpuPercent: Double(index % 100),
                threadCount: index % 32
            )
            rows.append(metric)
        }

        measure {
            let sorted = rows.sorted(using: ProcessSort(column: .memory, ascending: false))
            XCTAssertEqual(sorted.first?.residentMemory, rows.last?.residentMemory)
            XCTAssertEqual(sorted.count, 1_000)
        }
    }
}

private struct FixedSampler: SystemSampling {
    var snapshot: MetricSnapshot

    func capture(previous: MetricSnapshot?) -> MetricSnapshot {
        snapshot
    }
}
