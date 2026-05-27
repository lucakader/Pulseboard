import AppKit
import Combine
import Foundation
import PulseboardSystem

@MainActor
public final class PresetStore: ObservableObject {
    @Published public private(set) var presets: [DashboardPreset]
    @Published public var selectedPresetID: UUID

    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let loaded = Self.load(from: self.storageURL, decoder: decoder)
        let initialPresets = (loaded.isEmpty ? DashboardPreset.defaults : loaded).map { $0.normalized() }
        self.presets = initialPresets
        self.selectedPresetID = initialPresets.first?.id ?? UUID()

        if loaded.isEmpty {
            save()
        }
    }

    public var selectedPreset: DashboardPreset {
        get {
            presets.first(where: { $0.id == selectedPresetID }) ?? presets.first ?? DashboardPreset.defaults[0]
        }
        set {
            updatePreset(newValue)
            selectedPresetID = newValue.id
        }
    }

    public func select(_ preset: DashboardPreset) {
        selectedPresetID = preset.id
    }

    public func updatePreset(_ preset: DashboardPreset) {
        var copy = preset.normalized()
        copy.updatedAt = Date()

        if let index = presets.firstIndex(where: { $0.id == copy.id }) {
            presets[index] = copy
        } else {
            presets.append(copy)
        }
        save()
    }

    public func duplicateSelected() {
        var copy = selectedPreset
        copy.id = UUID()
        copy.name = "\(copy.name) Copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        presets.append(copy)
        selectedPresetID = copy.id
        save()
    }

    public func resetDefaults() {
        presets = DashboardPreset.defaults.map { $0.normalized() }
        selectedPresetID = presets[0].id
        save()
    }

    public func moveWidget(widgetID: UUID, before targetID: UUID) {
        var preset = selectedPreset
        guard
            let sourceIndex = preset.widgets.firstIndex(where: { $0.id == widgetID }),
            let targetIndex = preset.widgets.firstIndex(where: { $0.id == targetID }),
            sourceIndex != targetIndex
        else { return }

        let moved = preset.widgets.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        preset.widgets.insert(moved, at: adjustedTarget)
        for index in preset.widgets.indices {
            preset.widgets[index].order = index
        }
        selectedPreset = preset
    }

    public func save() {
        do {
            let folder = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try encoder.encode(presets.map { $0.normalized() })
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("Pulseboard failed to save presets: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL, decoder: JSONDecoder) -> [DashboardPreset] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([DashboardPreset].self, from: data)) ?? []
    }

    private static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("Pulseboard", isDirectory: true).appendingPathComponent("presets.json")
    }
}

@MainActor
public final class MonitorStore: ObservableObject {
    @Published public private(set) var snapshot: MetricSnapshot = .empty
    @Published public private(set) var history: [MetricSnapshot] = []
    @Published public private(set) var isRefreshing = false
    @Published public var lastError: String?

    private let sampler: SystemSampling
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    public init(sampler: SystemSampling = CSystemSampler()) {
        self.sampler = sampler
    }

    public func start(interval: TimeInterval) {
        stop()
        refreshInBackground()

        timer = Timer.scheduledTimer(withTimeInterval: max(0.25, interval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshInBackground()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
    }

    public func refreshNow() {
        let next = sampler.capture(previous: history.last)
        apply(next)
    }

    public func refreshInBackground() {
        guard !isRefreshing else { return }

        let previous = history.last
        let sampler = sampler
        isRefreshing = true

        refreshTask = Task { [weak self] in
            let next = await Task.detached(priority: .userInitiated) {
                sampler.capture(previous: previous)
            }.value

            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.apply(next)
                self.isRefreshing = false
                self.refreshTask = nil
            }
        }
    }

    private func apply(_ next: MetricSnapshot) {
        snapshot = next
        history.append(next)
        if history.count > 120 {
            history.removeFirst(history.count - 120)
        }
    }
}

@MainActor
public final class ProcessController: ObservableObject {
    @Published public private(set) var lastActionMessage: String?

    public init() {}

    @discardableResult
    public func quit(_ process: ProcessMetric) -> Bool {
        if let app = NSRunningApplication(processIdentifier: process.pid), app.terminate() {
            lastActionMessage = "Quit requested for \(process.name)."
            return true
        }

        let result = PBTerminateProcess(process.pid, 0)
        lastActionMessage = result == 0 ? "Quit requested for \(process.name)." : "Could not quit \(process.name). Permission may be required."
        return result == 0
    }

    @discardableResult
    public func forceQuit(_ process: ProcessMetric) -> Bool {
        if let app = NSRunningApplication(processIdentifier: process.pid), app.forceTerminate() {
            lastActionMessage = "Force quit requested for \(process.name)."
            return true
        }

        let result = PBTerminateProcess(process.pid, 1)
        lastActionMessage = result == 0 ? "Force quit requested for \(process.name)." : "Could not force quit \(process.name). Permission may be required."
        return result == 0
    }

    public func reveal(_ process: ProcessMetric) {
        guard !process.path.isEmpty else {
            lastActionMessage = "No file path is available for \(process.name)."
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: process.path)])
        lastActionMessage = "Revealed \(process.name)."
    }
}
