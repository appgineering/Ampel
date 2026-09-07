import ServiceManagement
import SwiftUI

/// The settings pane, shown in place of the session list rather than in a
/// separate window, so the whole app stays inside one popover.
struct SettingsView: View {
    @Bindable var settings: Settings

    private let statusline = StatuslineInstaller()
    @State private var planUsage = false
    @State private var planFailure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Usage section", selection: $settings.usageStyle) {
                ForEach(Settings.UsageStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.radioGroup)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show real plan usage", isOn: $planUsage)
                Text("Reads your actual 5-hour and 7-day limits from Claude Code, the same numbers /usage shows. Needs a statusLine hook, which Ampel installs and chains onto any statusline you already have. Turning this off restores the previous one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let planFailure {
                    Text(planFailure).font(.caption).foregroundStyle(.orange)
                }
            }
            .onChange(of: planUsage) { _, on in
                do {
                    planFailure = nil
                    on ? try statusline.install() : try statusline.uninstall()
                } catch {
                    planFailure = error.localizedDescription
                    planUsage = statusline.isInstalled
                }
            }
            .task { planUsage = statusline.isInstalled }

            Divider()

            Toggle("Pulse the icon when a session is blocked", isOn: $settings.pulseOnAttention)
            Toggle("Notify when a session is blocked", isOn: $settings.notifyOnAttention)
            LaunchAtLoginToggle()
        }
        .toggleStyle(.checkbox)
        .padding(20)
        .frame(width: 380, alignment: .leading)
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at Login", isOn: $enabled)
            .toggleStyle(.checkbox)
            .onChange(of: enabled) { _, on in
                do {
                    on ? try SMAppService.mainApp.register()
                       : try SMAppService.mainApp.unregister()
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}
