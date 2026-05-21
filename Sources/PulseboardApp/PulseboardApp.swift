import PulseboardCore
import SwiftUI

@main
struct PulseboardApp: App {
    @StateObject private var presets = PresetStore()
    @StateObject private var monitor = MonitorStore()

    var body: some Scene {
        WindowGroup {
            PulseboardRootView()
                .environmentObject(presets)
                .environmentObject(monitor)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environmentObject(presets)
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var presets: PresetStore

    var body: some View {
        Form {
            Section("Storage") {
                Text("Presets are stored as JSON in Application Support.")
                    .foregroundStyle(.secondary)
                Button("Reset Dashboards", role: .destructive) {
                    presets.resetDefaults()
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
