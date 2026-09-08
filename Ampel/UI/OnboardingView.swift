import SwiftUI

/// First run setup, in a window of its own. The popover is the wrong place for
/// this: it dismisses the moment you click elsewhere, which is exactly what
/// happens when someone reads an instruction and goes to follow it.
struct OnboardingView: View {
    @Bindable var settings: Settings
    let finish: () -> Void

    @State private var step = 0
    private static let steps = 4

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)

            Divider()

            HStack(spacing: 12) {
                ForEach(0..<Self.steps, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Button(step == Self.steps - 1 ? "Done" : "Continue") {
                    step == Self.steps - 1 ? finish() : (step += 1)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 460)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcome
        case 1: HooksStep()
        case 2: PlanUsageStep()
        default: appearance
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage ?? StatusIcon.image(for: .idle))
                    .resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Welcome to Ampel").font(.title2).fontWeight(.semibold)
                    Text("A traffic light for your Claude Code sessions.")
                        .foregroundStyle(.secondary)
                }
            }
            Text("Ampel sits in your menu bar and shows, without you asking, whether any session needs you. Run several at once and it always shows the one that needs you most.")
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            LegendView()
            Spacer()
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Make it yours").font(.title3).fontWeight(.semibold)
            Text("Pick how the icon looks. Each preview runs through the states it will actually show.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            IconStylePicker(selection: $settings.iconStyle)
            Divider()
            LaunchAtLoginToggle()
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text("All of this lives in Settings, reachable from the menu whenever you want to change it.")
                Text("Ampel is MIT licensed and not affiliated with Anthropic.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Step two: the hooks, without which Ampel sees nothing at all.
private struct HooksStep: View {
    private let installer = HookInstaller()
    @State private var installed = false
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect to Claude Code").font(.title3).fontWeight(.semibold)
            Text("Claude Code can run a small script when a session starts, finishes a turn, or waits on you. Ampel installs that script and registers it in your settings.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Your existing settings and any hooks from other tools are kept. A timestamped backup is written before anything changes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if installed {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Hooks installed. New sessions will show up automatically.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    // Claude Code snapshots its hook config at session start, so a
                    // session that was already running keeps firing nothing.
                    Text("Claude Code sessions that are already running will not appear until you restart them, or run /hooks in them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if working {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Installing…") }
            } else {
                Button("Install hooks") {
                    working = true
                    do {
                        try installer.install()
                        installed = installer.isInstalled
                        failure = installed ? nil : "Install ran but the hooks are still missing."
                    } catch {
                        failure = error.localizedDescription
                    }
                    working = false
                }
                .controlSize(.large)
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            Spacer()
        }
        .task { installed = installer.isInstalled }
    }
}

/// Step three: the opt-in that takes over the statusLine slot.
private struct PlanUsageStep: View {
    private let statusline = StatuslineInstaller()
    @State private var enabled = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Show your real plan usage").font(.title3).fontWeight(.semibold)
            Text("Ampel can show the same 5-hour and 7-day percentages the /usage screen does, rather than an estimated dollar cost.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Claude Code only reports those to a statusLine command, so Ampel installs one. If you already have a statusline it keeps running, unchanged, and turning this off puts it back exactly as it was.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Show real plan usage", isOn: $enabled)
                .toggleStyle(.switch)
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            Text("Entirely optional. Without it, Ampel falls back to cost estimates from ccusage, if you have it installed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .onChange(of: enabled) { _, on in
            do {
                failure = nil
                on ? try statusline.install() : try statusline.uninstall()
            } catch {
                failure = error.localizedDescription
                enabled = statusline.isInstalled
            }
        }
        .task { enabled = statusline.isInstalled }
    }
}
