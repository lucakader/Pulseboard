import AppKit
import SwiftUI

public struct PulseboardRootView: View {
    @EnvironmentObject private var presets: PresetStore
    @EnvironmentObject private var monitor: MonitorStore
    @StateObject private var processController = ProcessController()
    @State private var selectedPID: Int32?
    @State private var isCustomizing = false
    @State private var isCommandPalettePresented = false
    @State private var pendingAction: ProcessAction?

    public init() {}

    private var presetBinding: Binding<DashboardPreset> {
        Binding(
            get: { presets.selectedPreset },
            set: { presets.selectedPreset = $0 }
        )
    }

    private var selectedProcess: ProcessMetric? {
        monitor.snapshot.processes.first(where: { $0.pid == selectedPID })
    }

    public var body: some View {
        HSplitView {
            SidebarView()
                .environmentObject(presets)
                .frame(minWidth: 190, idealWidth: 220, maxWidth: 280)

            VSplitView {
                MonitorWorkspaceView(
                    preset: presetBinding,
                    selectedPID: $selectedPID,
                    isCustomizing: $isCustomizing,
                    isCommandPalettePresented: $isCommandPalettePresented
                )
                .environmentObject(monitor)
                .frame(minWidth: 680, minHeight: 460)

                if presets.selectedPreset.widgets.contains(where: { $0.kind == .processTable && $0.isVisible }) {
                    ProcessTablePane(
                        preset: presetBinding,
                        selectedPID: $selectedPID
                    )
                    .environmentObject(monitor)
                    .frame(minHeight: 220, idealHeight: 310)
                }
            }

            ProcessInspectorView(
                process: selectedProcess,
                snapshot: monitor.snapshot,
                actionMessage: processController.lastActionMessage,
                requestAction: { pendingAction = $0 }
            )
            .frame(minWidth: 250, idealWidth: 300, maxWidth: 360)
        }
        .background(AppBackground(preset: presets.selectedPreset))
        .preferredColorScheme(colorScheme(for: presets.selectedPreset.theme.mode))
        .sheet(isPresented: $isCustomizing) {
            CustomizationView(
                preset: presetBinding,
                duplicatePreset: { presets.duplicateSelected() },
                resetDefaults: { presets.resetDefaults() }
            )
            .frame(minWidth: 560, minHeight: 620)
        }
        .sheet(isPresented: $isCommandPalettePresented) {
            CommandPaletteView(
                refresh: { monitor.refreshInBackground() },
                customize: { isCustomizing = true },
                duplicate: { presets.duplicateSelected() }
            )
            .frame(width: 480, height: 420)
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            )
        ) {
            if let pendingAction {
                Button(pendingAction.buttonTitle, role: pendingAction.role) {
                    run(pendingAction)
                    self.pendingAction = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        }
        .onAppear {
            monitor.start(interval: presets.selectedPreset.refreshInterval)
        }
        .onChange(of: presets.selectedPresetID) { _, _ in
            selectedPID = nil
            monitor.start(interval: presets.selectedPreset.refreshInterval)
        }
        .onChange(of: presets.selectedPreset.refreshInterval) { _, newValue in
            monitor.start(interval: newValue)
        }
    }

    private var confirmationTitle: String {
        guard let pendingAction else { return "Confirm" }
        return pendingAction.confirmationTitle
    }

    private func run(_ action: ProcessAction) {
        switch action {
        case .quit(let process):
            processController.quit(process)
        case .forceQuit(let process):
            processController.forceQuit(process)
        }
    }

    private func colorScheme(for mode: ThemeMode) -> ColorScheme? {
        switch mode {
        case .system:
            nil
        case .light:
            .light
        case .dark, .highContrast:
            .dark
        }
    }
}

public enum ProcessAction {
    case quit(ProcessMetric)
    case forceQuit(ProcessMetric)

    var confirmationTitle: String {
        switch self {
        case .quit(let process):
            "Quit \(process.name)?"
        case .forceQuit(let process):
            "Force Quit \(process.name)?"
        }
    }

    var buttonTitle: String {
        switch self {
        case .quit:
            "Quit"
        case .forceQuit:
            "Force Quit"
        }
    }

    var role: ButtonRole? {
        switch self {
        case .quit:
            nil
        case .forceQuit:
            .destructive
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var presets: PresetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                    Text("Pulseboard")
                        .font(.title3.weight(.semibold))
                    Spacer()
                }

                Text("Workspace")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(presets.presets) { preset in
                        SidebarPresetButton(
                            preset: preset,
                            isSelected: preset.id == presets.selectedPresetID
                        ) {
                            presets.selectedPresetID = preset.id
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Label("Local JSON", systemImage: "doc.text")
                    .font(.caption.weight(.semibold))
                Text("Application Support/Pulseboard")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .background(.bar)
    }
}

private struct SidebarPresetButton: View {
    var preset: DashboardPreset
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: preset.theme.accentHex).opacity(isSelected ? 0.24 : 0.14))
                    Image(systemName: preset.resolvedSymbolName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: preset.theme.accentHex))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: preset.theme.accentHex))
                            .frame(width: 6, height: 6)
                        Text(preset.resolvedCanvasStyle.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color(hex: preset.theme.accentHex).opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color(hex: preset.theme.accentHex).opacity(0.45) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MonitorWorkspaceView: View {
    @EnvironmentObject private var monitor: MonitorStore
    @Binding var preset: DashboardPreset
    @Binding var selectedPID: Int32?
    @Binding var isCustomizing: Bool
    @Binding var isCommandPalettePresented: Bool

    private var visibleWidgets: [WidgetConfig] {
        preset.widgets.filter(\.isVisible).sorted { $0.order < $1.order }.filter { $0.kind != .processTable }
    }

    var body: some View {
        VStack(spacing: 0) {
            MonitorToolbar(
                preset: $preset,
                isCustomizing: $isCustomizing,
                isCommandPalettePresented: $isCommandPalettePresented
            )
            .environmentObject(monitor)

            ScrollView {
                VStack(spacing: 14) {
                    DashboardHeroView(
                        preset: preset,
                        snapshot: monitor.snapshot,
                        customize: { isCustomizing = true },
                        command: { isCommandPalettePresented = true }
                    )

                    if preset.resolvedShowSignalRail {
                        SignalRailView(preset: preset, snapshot: monitor.snapshot)
                    }

                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(visibleWidgets) { widget in
                            WidgetCard(widget: widget, preset: preset, snapshot: monitor.snapshot, history: monitor.history)
                                .frame(minHeight: widget.size == .compact ? 150 : 204)
                                .gridCellColumns(widget.size == .wide ? 2 : 1)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 300, maximum: 560), spacing: 12, alignment: .top)
        ]
    }
}

private struct MonitorToolbar: View {
    @EnvironmentObject private var monitor: MonitorStore
    @Binding var preset: DashboardPreset
    @Binding var isCustomizing: Bool
    @Binding var isCommandPalettePresented: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.headline)
                Text(monitor.snapshot.isWarm ? "Live" : "Warming")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            MetricPill(title: "CPU", value: monitor.snapshot.system.cpuUsage.percentText, color: accent)
            MetricPill(title: "Memory", value: monitor.snapshot.system.memoryPressure.percentText, color: secondary)
            MetricPill(title: "Load", value: String(format: "%.2f", monitor.snapshot.system.loadAverage1), color: .orange)

            Button {
                monitor.refreshInBackground()
            } label: {
                Image(systemName: monitor.isRefreshing ? "hourglass" : "arrow.clockwise")
            }
            .disabled(monitor.isRefreshing)
            .help("Refresh")

            Button {
                isCommandPalettePresented = true
            } label: {
                Image(systemName: "command")
            }
            .help("Command Palette")

            Button {
                isCustomizing = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Customize")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var accent: Color { Color(hex: preset.theme.accentHex) }
    private var secondary: Color { Color(hex: preset.theme.secondaryHex) }
}

private struct MetricPill: View {
    var title: String
    var value: String
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .rounded).weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DashboardHeroView: View {
    var preset: DashboardPreset
    var snapshot: MetricSnapshot
    var customize: () -> Void
    var command: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(heroFill)
                Image(systemName: preset.resolvedSymbolName)
                    .font(.system(size: 32, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(hex: preset.theme.accentHex))
            }
            .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(preset.name)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    StatusDot(isWarm: snapshot.isWarm, color: Color(hex: preset.theme.accentHex))
                }

                Text(preset.resolvedSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    BadgeLabel(title: preset.resolvedCanvasStyle.title, systemImage: "rectangle.dashed")
                    BadgeLabel(title: preset.resolvedCardStyle.title, systemImage: "square.stack")
                    BadgeLabel(title: String(format: "%.1fs", preset.refreshInterval), systemImage: "timer")
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 8) {
                    Button(action: command) {
                        Image(systemName: "command")
                    }
                    .help("Command Palette")

                    Button(action: customize) {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help("Customize Dashboard")
                }
                .buttonStyle(.borderless)

                HStack(spacing: 10) {
                    HeroMetric(title: "CPU", value: snapshot.system.cpuUsage.percentText, color: Color(hex: preset.theme.accentHex))
                    HeroMetric(title: "RAM", value: snapshot.system.memoryPressure.percentText, color: Color(hex: preset.theme.secondaryHex))
                }
            }
        }
        .padding(16)
        .background(heroBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(hex: preset.theme.accentHex).opacity(0.20))
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 8)
    }

    private var heroFill: Color {
        Color(hex: preset.theme.accentHex).opacity(preset.theme.mode == .highContrast ? 0.18 : 0.12)
    }

    @ViewBuilder
    private var heroBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.regularMaterial)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: preset.theme.accentHex).opacity(0.18),
                                Color(hex: preset.theme.secondaryHex).opacity(0.10),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 3)
            }
    }
}

private struct StatusDot: View {
    var isWarm: Bool
    var color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isWarm ? color : .orange)
                .frame(width: 8, height: 8)
            Text(isWarm ? "Live" : "Warming")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BadgeLabel: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct HeroMetric: View {
    var title: String
    var value: String
    var color: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(minWidth: 64, alignment: .trailing)
    }
}

private struct SignalRailView: View {
    var preset: DashboardPreset
    var snapshot: MetricSnapshot

    var body: some View {
        HStack(spacing: 10) {
            SignalTile(title: "CPU", value: snapshot.system.cpuUsage, detail: snapshot.system.cpuUsage.percentText, color: Color(hex: preset.theme.accentHex), systemImage: "cpu")
            SignalTile(title: "Memory", value: snapshot.system.memoryPressure, detail: snapshot.system.memoryPressure.percentText, color: Color(hex: preset.theme.secondaryHex), systemImage: "memorychip")
            SignalTile(title: "Disk", value: diskPercent, detail: ByteFormatter.string(snapshot.system.diskUsed), color: .orange, systemImage: "internaldrive")
            SignalTile(title: "Network", value: networkPulse, detail: ByteFormatter.rate(snapshot.system.networkDownRate), color: .teal, systemImage: "network")
        }
    }

    private var diskPercent: Double {
        guard snapshot.system.diskTotal > 0 else { return 0 }
        return Double(snapshot.system.diskUsed) / Double(snapshot.system.diskTotal) * 100
    }

    private var networkPulse: Double {
        min(100, (snapshot.system.networkDownRate + snapshot.system.networkUpRate) / 500_000 * 100)
    }
}

private struct SignalTile: View {
    var title: String
    var value: Double
    var detail: String
    var color: Color
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(detail)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            MiniBar(value: value, color: color)
                .frame(height: 8)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.18))
        )
    }
}

private struct MiniBar: View {
    var value: Double
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: proxy.size.width * max(0, min(value, 100)) / 100)
            }
        }
    }
}

private struct WidgetCard: View {
    var widget: WidgetConfig
    var preset: DashboardPreset
    var snapshot: MetricSnapshot
    var history: [MetricSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(widget.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(widget.kind.defaultTitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                Spacer()

                Text(widget.size.rawValue.capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            }

            content
        }
        .padding(cardPadding)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(cardBorder)
        )
        .shadow(color: cardShadow, radius: shadowRadius, x: 0, y: 8)
    }

    private var cardPadding: CGFloat {
        preset.resolvedCardStyle == .editorial ? 16 : 14
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch preset.resolvedCardStyle {
        case .glass:
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .overlay(alignment: .topLeading) {
                    Rectangle()
                        .fill(accent.opacity(0.28))
                        .frame(width: 4)
                }
        case .editorial:
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.94))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.55), secondary.opacity(0.40), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 2)
                }
        case .outline:
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.62))
        case .solid:
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: preset.theme.accentHex).opacity(0.09))
        }
    }

    private var cardBorder: Color {
        switch preset.resolvedCardStyle {
        case .glass:
            .primary.opacity(0.08)
        case .editorial:
            accent.opacity(0.22)
        case .outline:
            .primary.opacity(0.18)
        case .solid:
            accent.opacity(0.24)
        }
    }

    private var cardShadow: Color {
        preset.resolvedCardStyle == .outline ? .clear : Color.black.opacity(0.07)
    }

    private var shadowRadius: CGFloat {
        preset.resolvedCardStyle == .outline ? 0 : 12
    }

    @ViewBuilder
    private var content: some View {
        switch widget.kind {
        case .cpu:
            GaugeWidget(
                value: snapshot.system.cpuUsage,
                title: "Total",
                detail: "\(snapshot.system.logicalCPUCount) logical cores",
                color: accent,
                theme: preset.theme
            )
        case .memory:
            MemoryCompositionWidget(
                system: snapshot.system,
                accent: accent,
                secondary: secondary,
                theme: preset.theme
            )
        case .disk:
            CapacityWidget(
                title: "Root Volume",
                used: snapshot.system.diskUsed,
                total: snapshot.system.diskTotal,
                color: .orange
            )
        case .network:
            NetworkWidget(system: snapshot.system, accent: accent, secondary: secondary)
        case .topOffenders:
            TopOffendersWidget(processes: snapshot.processes.sorted(using: ProcessSort(column: .cpu, ascending: false)), accent: accent)
        case .trend:
            TrendWidget(history: history, snapshot: snapshot, accent: accent, secondary: secondary, style: preset.theme.chartStyle)
        case .processTable:
            EmptyView()
        }
    }

    private var accent: Color { Color(hex: preset.theme.accentHex) }
    private var secondary: Color { Color(hex: preset.theme.secondaryHex) }

    private var icon: String {
        switch widget.kind {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .topOffenders: "flame"
        case .processTable: "tablecells"
        case .trend: "waveform.path.ecg"
        }
    }

    private func percent(_ used: UInt64, _ total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(100, Double(used) / Double(total) * 100)
    }
}

private struct GaugeWidget: View {
    var value: Double
    var title: String
    var detail: String
    var color: Color
    var theme: ThemeConfig

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.10), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: max(0.01, min(value / 100, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value.percentText)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ThresholdBar(value: value, theme: theme, color: color)
                    .frame(height: 8)
            }
        }
    }
}

private struct CompactStatWidget: View {
    var primary: String
    var secondary: String
    var progress: Double
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(primary)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(secondary)
                .font(.callout)
                .foregroundStyle(.secondary)
            ProgressView(value: progress, total: 100)
                .tint(color)
        }
    }
}

private struct MemoryCompositionWidget: View {
    var system: SystemMetric
    var accent: Color
    var secondary: Color
    var theme: ThemeConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(system.memoryPressure.percentText)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(secondary)
                    Text("Pressure")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(ByteFormatter.string(system.totalMemory.saturatingSubtract(system.freeMemory)))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text("\(ByteFormatter.string(system.totalMemory)) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SegmentedCapacityBar(
                segments: [
                    CapacitySegment(value: system.activeMemory, color: accent, title: "Active"),
                    CapacitySegment(value: system.wiredMemory, color: .orange, title: "Wired"),
                    CapacitySegment(value: system.compressedMemory, color: secondary, title: "Compressed"),
                    CapacitySegment(value: system.freeMemory, color: .secondary.opacity(0.35), title: "Free")
                ],
                total: max(system.totalMemory, 1)
            )
            .frame(height: 14)

            HStack(spacing: 10) {
                MemoryLegend(title: "Active", value: system.activeMemory, color: accent)
                MemoryLegend(title: "Wired", value: system.wiredMemory, color: .orange)
                MemoryLegend(title: "Compressed", value: system.compressedMemory, color: secondary)
            }
        }
    }
}

private struct CapacitySegment: Identifiable {
    let id = UUID()
    var value: UInt64
    var color: Color
    var title: String
}

private struct SegmentedCapacityBar: View {
    var segments: [CapacitySegment]
    var total: UInt64

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(segment.color)
                        .frame(width: segmentWidth(segment.value, availableWidth: proxy.size.width))
                        .help("\(segment.title): \(ByteFormatter.string(segment.value))")
                }
            }
        }
    }

    private func segmentWidth(_ value: UInt64, availableWidth: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        let width = availableWidth * CGFloat(Double(value) / Double(total))
        return max(value == 0 ? 0 : 3, width)
    }
}

private struct MemoryLegend: View {
    var title: String
    var value: UInt64
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(ByteFormatter.string(value))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CapacityWidget: View {
    var title: String
    var used: UInt64
    var total: UInt64
    var color: Color

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total) * 100
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.08), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: max(0.01, min(progress / 100, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(progress.percentText)
                    .font(.system(.callout, design: .rounded).weight(.bold))
            }
            .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(ByteFormatter.string(used))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(ByteFormatter.string(total)) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NetworkWidget: View {
    var system: SystemMetric
    var accent: Color
    var secondary: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NetworkRateRow(title: "Down", value: ByteFormatter.rate(system.networkDownRate), color: accent, progress: pulse(system.networkDownRate))
            NetworkRateRow(title: "Up", value: ByteFormatter.rate(system.networkUpRate), color: secondary, progress: pulse(system.networkUpRate))
            HStack {
                BadgeLabel(title: "In \(ByteFormatter.string(system.networkInBytes))", systemImage: "arrow.down.to.line")
                BadgeLabel(title: "Out \(ByteFormatter.string(system.networkOutBytes))", systemImage: "arrow.up.to.line")
            }
        }
    }

    private func pulse(_ rate: Double) -> Double {
        min(100, rate / 400_000 * 100)
    }
}

private struct NetworkRateRow: View {
    var title: String
    var value: String
    var color: Color
    var progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(title, systemImage: title == "Down" ? "arrow.down" : "arrow.up")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            MiniBar(value: progress, color: color)
                .frame(height: 7)
        }
    }
}

private struct TopOffendersWidget: View {
    var processes: [ProcessMetric]
    var accent: Color

    var body: some View {
        VStack(spacing: 9) {
            ForEach(Array(processes.prefix(6).enumerated()), id: \.element.id) { index, process in
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accent)
                            .frame(width: 20, height: 20)
                            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                        Text(process.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)

                        Spacer()

                        Text(String(format: "%.1f%%", process.cpuPercent))
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundStyle(accent)
                            .monospacedDigit()
                    }
                    MiniBar(value: min(process.cpuPercent, 100), color: accent)
                        .frame(height: 5)
                }
            }
        }
    }
}

private struct TrendWidget: View {
    var history: [MetricSnapshot]
    var snapshot: MetricSnapshot
    var accent: Color
    var secondary: Color
    var style: ChartStyle

    private var values: [Double] {
        let base = history.map(\.system.cpuUsage)
        return (base + [snapshot.system.cpuUsage]).suffix(40)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Sparkline(values: Array(values), color: accent, style: style)
                .frame(height: 86)
            HStack {
                Label(snapshot.system.cpuUsage.percentText, systemImage: "cpu")
                    .foregroundStyle(accent)
                Spacer()
                Label(snapshot.system.memoryPressure.percentText, systemImage: "memorychip")
                    .foregroundStyle(secondary)
            }
            .font(.callout.weight(.medium))
        }
    }
}

private struct Sparkline: View {
    var values: [Double]
    var color: Color
    var style: ChartStyle

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let points = normalizedPoints(in: size)
                guard points.count > 1 else { return }

                switch style {
                case .bars:
                    for point in points {
                        let rect = CGRect(x: point.x - 2, y: point.y, width: 4, height: size.height - point.y)
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(0.75)))
                    }
                case .filled:
                    var fillPath = Path()
                    fillPath.move(to: CGPoint(x: points[0].x, y: size.height))
                    for point in points {
                        fillPath.addLine(to: point)
                    }
                    fillPath.addLine(to: CGPoint(x: points.last?.x ?? size.width, y: size.height))
                    fillPath.closeSubpath()
                    context.fill(fillPath, with: .color(color.opacity(0.22)))
                    fallthrough
                case .line:
                    var linePath = Path()
                    linePath.move(to: points[0])
                    for point in points.dropFirst() {
                        linePath.addLine(to: point)
                    }
                    context.stroke(linePath, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topLeading) {
                Text("\(Int(proxy.size.width))")
                    .hidden()
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let safeValues = values.isEmpty ? [0, 0] : values
        let step = safeValues.count > 1 ? size.width / CGFloat(safeValues.count - 1) : size.width
        return safeValues.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height - CGFloat(max(0, min(value, 100)) / 100) * size.height
            )
        }
    }
}

private struct ThresholdBar: View {
    var value: Double
    var theme: ThemeConfig
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: 4)
                    .fill(barColor)
                    .frame(width: proxy.size.width * max(0, min(value, 100)) / 100)
            }
        }
    }

    private var barColor: Color {
        if value >= theme.criticalThreshold {
            .red
        } else if value >= theme.warningThreshold {
            .orange
        } else {
            color
        }
    }
}

private struct ProcessTablePane: View {
    @EnvironmentObject private var monitor: MonitorStore
    @Binding var preset: DashboardPreset
    @Binding var selectedPID: Int32?

    private var displayedProcesses: [ProcessMetric] {
        monitor.snapshot.processes
            .filtered(preset.processFilter)
            .sorted(using: preset.processSort)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Processes", systemImage: "tablecells")
                    .font(.headline)

                TextField("Filter", text: Binding(
                    get: { preset.processFilter },
                    set: { preset.processFilter = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

                Spacer()

                Picker("Sort", selection: Binding(
                    get: { preset.processSort.column },
                    set: { preset.processSort.column = $0 }
                )) {
                    ForEach(ProcessColumn.allCases) { column in
                        Text(column.title).tag(column)
                    }
                }
                .frame(width: 140)

                Button {
                    preset.processSort.ascending.toggle()
                } label: {
                    Image(systemName: preset.processSort.ascending ? "arrow.up" : "arrow.down")
                }
                .help("Sort Direction")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial)

            ProcessTableView(
                processes: displayedProcesses,
                columns: preset.columns.filter(\.isVisible),
                density: preset.theme.density,
                sort: preset.processSort,
                selectedPID: $selectedPID,
                onSort: { newSort in
                    preset.processSort = newSort
                }
            )
        }
    }
}

private struct ProcessInspectorView: View {
    var process: ProcessMetric?
    var snapshot: MetricSnapshot
    var actionMessage: String?
    var requestAction: (ProcessAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Inspector", systemImage: "sidebar.right")
                    .font(.headline)
                Spacer()
            }

            if let process {
                VStack(alignment: .leading, spacing: 12) {
                    Text(process.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    InfoRow("PID", String(process.pid))
                    InfoRow("CPU", String(format: "%.1f%%", process.cpuPercent))
                    InfoRow("Memory", ByteFormatter.string(process.residentMemory))
                    InfoRow("Threads", String(process.threadCount))
                    InfoRow("Path", process.path.isEmpty ? "Unavailable" : process.path)

                    Divider()

                    HStack {
                        Button {
                            requestAction(.quit(process))
                        } label: {
                            Label("Quit", systemImage: "xmark.circle")
                        }

                        Button(role: .destructive) {
                            requestAction(.forceQuit(process))
                        } label: {
                            Label("Force", systemImage: "bolt.circle")
                        }
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: process.path)])
                    } label: {
                        Label("Reveal", systemImage: "finder")
                    }
                    .disabled(process.path.isEmpty)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    InfoRow("Processes", "\(snapshot.processes.count)")
                    InfoRow("Memory", ByteFormatter.string(snapshot.system.totalMemory))
                    InfoRow("Swap", "\(ByteFormatter.string(snapshot.system.swapUsed)) / \(ByteFormatter.string(snapshot.system.swapTotal))")
                    InfoRow("Load 5", String(format: "%.2f", snapshot.system.loadAverage5))
                }
                .foregroundStyle(.secondary)
            }

            if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(.regularMaterial)
    }
}

private struct InfoRow: View {
    var title: String
    var value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }
}

private struct CustomizationView: View {
    @Binding var preset: DashboardPreset
    var duplicatePreset: () -> Void
    var resetDefaults: () -> Void

    @State private var tab: StudioTab = .style

    private let themes = ThemeConfig.builtIns

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                StudioPreviewCard(preset: preset)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Studio")
                        .font(.title2.weight(.semibold))
                    Text(preset.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Picker("Section", selection: $tab) {
                    ForEach(StudioTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.systemImage).tag(tab)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Spacer()

                Button(action: duplicatePreset) {
                    Label("Duplicate Dashboard", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive, action: resetDefaults) {
                    Label("Reset Defaults", systemImage: "arrow.counterclockwise")
                }
            }
            .padding(18)
            .frame(minWidth: 220, idealWidth: 250)
            .background(.bar)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .style:
                        StyleStudioSection(preset: $preset, themes: themes)
                    case .widgets:
                        WidgetStudioSection(preset: $preset)
                    case .properties:
                        ProcessPropertiesSection(preset: $preset)
                    }
                }
                .padding(20)
            }
            .frame(minWidth: 420)
        }
    }
}

private enum StudioTab: String, CaseIterable, Identifiable {
    case style
    case widgets
    case properties

    var id: String { rawValue }

    var title: String {
        switch self {
        case .style: "Style"
        case .widgets: "Widgets"
        case .properties: "Properties"
        }
    }

    var systemImage: String {
        switch self {
        case .style: "paintpalette"
        case .widgets: "square.grid.2x2"
        case .properties: "slider.horizontal.below.rectangle"
        }
    }
}

private struct StudioPreviewCard: View {
    var preset: DashboardPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: preset.resolvedSymbolName)
                    .font(.title2)
                    .foregroundStyle(Color(hex: preset.theme.accentHex))
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: preset.theme.accentHex))
                    Circle().fill(Color(hex: preset.theme.secondaryHex))
                    Circle().fill(.orange)
                }
                .frame(width: 44, height: 10)
            }

            Text(preset.name)
                .font(.headline)
                .lineLimit(1)
            Text(preset.resolvedSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            MiniBar(value: 72, color: Color(hex: preset.theme.accentHex))
                .frame(height: 7)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(hex: preset.theme.accentHex).opacity(0.25))
        )
    }
}

private struct StyleStudioSection: View {
    @Binding var preset: DashboardPreset
    var themes: [ThemeConfig]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioSectionHeader(title: "Dashboard", systemImage: "rectangle.3.group")

            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: $preset.name)
                    .textFieldStyle(.roundedBorder)
                TextField("Subtitle", text: Binding(
                    get: { preset.subtitle ?? "" },
                    set: { preset.subtitle = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                TextField("SF Symbol", text: Binding(
                    get: { preset.symbolName ?? "" },
                    set: { preset.symbolName = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            StudioSectionHeader(title: "Themes", systemImage: "paintpalette")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(themes) { theme in
                    ThemeSwatchButton(theme: theme, isSelected: preset.theme.name == theme.name) {
                        preset.theme = theme
                    }
                }
            }

            StudioSectionHeader(title: "Canvas", systemImage: "square.dashed")
            VStack(alignment: .leading, spacing: 12) {
                Picker("Canvas", selection: Binding(
                    get: { preset.resolvedCanvasStyle },
                    set: { preset.canvasStyle = $0 }
                )) {
                    ForEach(CanvasStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Cards", selection: Binding(
                    get: { preset.resolvedCardStyle },
                    set: { preset.cardStyle = $0 }
                )) {
                    ForEach(CardStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Signal Rail", isOn: Binding(
                    get: { preset.resolvedShowSignalRail },
                    set: { preset.showSignalRail = $0 }
                ))

                Picker("Density", selection: $preset.theme.density) {
                    ForEach(DisplayDensity.allCases) { density in
                        Text(density.rawValue.capitalized).tag(density)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Charts", selection: $preset.theme.chartStyle) {
                    ForEach(ChartStyle.allCases) { style in
                        Text(style.rawValue.capitalized).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Refresh")
                        .font(.callout.weight(.medium))
                    Slider(value: $preset.refreshInterval, in: 0.5...5, step: 0.5)
                    Text("\(preset.refreshInterval, specifier: "%.1f")s")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ThemeSwatchButton: View {
    var theme: ThemeConfig
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(hex: theme.accentHex))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(hex: theme.secondaryHex))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(theme.mode == .dark || theme.mode == .highContrast ? .black : .white)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.16)))
                }
                .frame(height: 32)

                HStack {
                    Text(theme.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(hex: theme.accentHex))
                    }
                }

                Text(theme.chartStyle.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color(hex: theme.accentHex).opacity(0.65) : .primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WidgetStudioSection: View {
    @Binding var preset: DashboardPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSectionHeader(title: "Widget Library", systemImage: "square.grid.2x2")

            ForEach($preset.widgets) { $widget in
                WidgetStudioRow(
                    widget: $widget,
                    canMoveUp: widget.order > 0,
                    canMoveDown: widget.order < preset.widgets.count - 1,
                    moveUp: { move(widget.id, direction: -1) },
                    moveDown: { move(widget.id, direction: 1) }
                )
            }
        }
    }

    private func move(_ id: UUID, direction: Int) {
        guard
            let index = preset.widgets.firstIndex(where: { $0.id == id }),
            preset.widgets.indices.contains(index + direction)
        else { return }

        preset.widgets.swapAt(index, index + direction)
        for index in preset.widgets.indices {
            preset.widgets[index].order = index
        }
    }
}

private struct WidgetStudioRow: View {
    @Binding var widget: WidgetConfig
    var canMoveUp: Bool
    var canMoveDown: Bool
    var moveUp: () -> Void
    var moveDown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                    Image(systemName: widgetIcon(widget.kind))
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Title", text: $widget.title)
                        .textFieldStyle(.plain)
                        .font(.callout.weight(.semibold))
                    Picker("Size", selection: $widget.size) {
                        ForEach(WidgetSize.allCases, id: \.self) { size in
                            Text(size.rawValue.capitalized).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle("", isOn: $widget.isVisible)
                    .labelsHidden()

                VStack(spacing: 4) {
                    Button(action: moveUp) {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(!canMoveUp)
                    Button(action: moveDown) {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(!canMoveDown)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(widget.isVisible ? 0.12 : 0.05))
        )
    }
}

private struct ProcessPropertiesSection: View {
    @Binding var preset: DashboardPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSectionHeader(title: "Process Table", systemImage: "tablecells")

            VStack(alignment: .leading, spacing: 12) {
                TextField("Filter", text: $preset.processFilter)
                    .textFieldStyle(.roundedBorder)

                Picker("Sort", selection: $preset.processSort.column) {
                    ForEach(ProcessColumn.allCases) { column in
                        Text(column.title).tag(column)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Ascending", isOn: $preset.processSort.ascending)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            StudioSectionHeader(title: "Columns", systemImage: "rectangle.split.3x1")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach($preset.columns) { $column in
                    Toggle(isOn: $column.isVisible) {
                        Text(column.id.title)
                            .font(.callout.weight(.medium))
                    }
                    .toggleStyle(.checkbox)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct StudioSectionHeader: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }
}

private func widgetIcon(_ kind: WidgetKind) -> String {
        switch kind {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .topOffenders: "flame"
        case .processTable: "tablecells"
        case .trend: "waveform.path.ecg"
        }
}

private struct CommandPaletteView: View {
    var refresh: () -> Void
    var customize: () -> Void
    var duplicate: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var commands: [(String, String, () -> Void)] {
        [
            ("Refresh Now", "arrow.clockwise", refresh),
            ("Customize", "slider.horizontal.3", customize),
            ("Duplicate Dashboard", "plus.square.on.square", duplicate)
        ]
    }

    private var filteredCommands: [(String, String, () -> Void)] {
        guard !query.isEmpty else { return commands }
        return commands.filter { $0.0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 12) {
            TextField("Command", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .padding([.horizontal, .top], 16)

            List {
                ForEach(filteredCommands, id: \.0) { command in
                    Button {
                        command.2()
                        dismiss()
                    } label: {
                        Label(command.0, systemImage: command.1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct AppBackground: View {
    var preset: DashboardPreset

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
            Canvas { context, size in
                switch preset.resolvedCanvasStyle {
                case .studio:
                    drawDiagonalField(context: &context, size: size, spacing: 34, opacity: 0.05)
                case .grid:
                    drawGrid(context: &context, size: size, spacing: 28, opacity: 0.08)
                case .paper:
                    drawPaperLines(context: &context, size: size, spacing: 26, opacity: 0.055)
                case .terminal:
                    drawGrid(context: &context, size: size, spacing: 18, opacity: 0.10)
                    drawScanlines(context: &context, size: size, spacing: 6, opacity: 0.035)
                }
            }
            .foregroundStyle(Color(hex: preset.theme.accentHex))

            Rectangle()
                .fill(Color(hex: preset.theme.accentHex).opacity(preset.theme.mode == .highContrast ? 0.045 : 0.025))
        }
        .ignoresSafeArea()
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize, spacing: CGFloat, opacity: Double) {
        var path = Path()
        var x: CGFloat = 0
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }

        var y: CGFloat = 0
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }

        context.stroke(path, with: .color(Color(hex: preset.theme.accentHex).opacity(opacity)), lineWidth: 0.8)
    }

    private func drawDiagonalField(context: inout GraphicsContext, size: CGSize, spacing: CGFloat, opacity: Double) {
        var path = Path()
        var x = -size.height
        while x < size.width {
            path.move(to: CGPoint(x: x, y: size.height))
            path.addLine(to: CGPoint(x: x + size.height, y: 0))
            x += spacing
        }
        context.stroke(path, with: .color(Color(hex: preset.theme.secondaryHex).opacity(opacity)), lineWidth: 0.8)
    }

    private func drawPaperLines(context: inout GraphicsContext, size: CGSize, spacing: CGFloat, opacity: Double) {
        var path = Path()
        var y: CGFloat = 0
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        context.stroke(path, with: .color(Color(hex: preset.theme.secondaryHex).opacity(opacity)), lineWidth: 0.8)
    }

    private func drawScanlines(context: inout GraphicsContext, size: CGSize, spacing: CGFloat, opacity: Double) {
        var y: CGFloat = 0
        while y <= size.height {
            let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
            context.fill(Path(rect), with: .color(Color(hex: preset.theme.secondaryHex).opacity(opacity)))
            y += spacing
        }
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}
