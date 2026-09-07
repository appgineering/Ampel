import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: Settings

    var body: some View {
        Form {
            Section {
                LaunchAtLoginToggle()
                Toggle("Pulse the icon when a session is blocked", isOn: $settings.pulseOnAttention)
                Toggle("Notify when a session is blocked", isOn: $settings.notifyOnAttention)
            } footer: {
                Text("A session is blocked when Claude is waiting on a decision from you, such as a permission prompt. Sitting at an empty prompt does not count.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct UsageSettingsView: View {
    @Bindable var settings: Settings

    private let statusline = StatuslineInstaller()
    @State private var planUsage = false
    @State private var failure: String?

    var body: some View {
        Form {
            Section {
                Picker("Show usage as", selection: $settings.usageStyle) {
                    ForEach(Settings.UsageStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
            }

            Section {
                Toggle("Show real plan usage", isOn: $planUsage)
                if let failure {
                    Text(failure).font(.caption).foregroundStyle(.orange)
                }
            } footer: {
                Text("Reads your actual 5-hour and 7-day limits from Claude Code, the same numbers /usage shows. This needs a statusLine hook, which Ampel installs and chains onto any statusline you already have; turning it off restores the previous one. Without it, the section falls back to ccusage cost estimates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: planUsage) { _, on in
            do {
                failure = nil
                on ? try statusline.install() : try statusline.uninstall()
            } catch {
                failure = error.localizedDescription
                planUsage = statusline.isInstalled
            }
        }
        .task { planUsage = statusline.isInstalled }
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at Login", isOn: $enabled)
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
