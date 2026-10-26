import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: TinyproxyMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                if monitor.brewAvailable {
                    details
                } else {
                    brewMissing
                }
                actions
            }
            .padding(20)

            Divider()

            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
        .frame(width: 340)
        .alert("Homebrew is not installed", isPresented: $monitor.showBrewMissingAlert) {
            Button("Open brew.sh") { monitor.openBrewWebsite() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This app uses Homebrew to install and manage tinyproxy. Visit https://brew.sh/ for installation instructions.")
        }
        .alert("tinyproxy is not installed", isPresented: $monitor.showInstallPrompt) {
            Button("Install") { Task { await monitor.install() } }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Do you want to install it now with Homebrew (`brew install tinyproxy`)?")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { monitor.errorMessage != nil },
            set: { if !$0 { monitor.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(monitor.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 14, height: 14)
                .shadow(color: statusColor.opacity(0.6), radius: 3)
            Text("tinyproxy")
                .font(.title2.weight(.semibold))
            Spacer()
            Text(statusText)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Version").foregroundStyle(.secondary)
                Text(monitor.version ?? "—").textSelection(.enabled)
            }
            GridRow {
                Text("Updates").foregroundStyle(.secondary)
                updatesText
            }
            if let pid = monitor.pid {
                GridRow {
                    Text("PID").foregroundStyle(.secondary)
                    Text(String(pid)).textSelection(.enabled)
                }
            } else if monitor.installed == true, let code = monitor.lastExitCode, code != 0 {
                GridRow {
                    Text("Last exit").foregroundStyle(.secondary)
                    Text("code \(code)").foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private var updatesText: some View {
        if monitor.installed != true {
            Text("—")
        } else if monitor.outdated {
            Text("Update available (\(monitor.latestVersion ?? "?"))").foregroundStyle(.orange)
        } else {
            Text("Up to date").foregroundStyle(.green)
        }
    }

    private var brewMissing: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Homebrew was not found on this Mac.")
            Link("Install instructions at brew.sh", destination: TinyproxyMonitor.brewWebsite)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack {
            if let message = monitor.busyMessage {
                Text(message).foregroundStyle(.secondary)
            } else if monitor.outdated {
                Button("Upgrade") { Task { await monitor.upgrade() } }
            }
            Spacer()
            // Always laid out so showing it doesn't shift the button.
            ProgressView()
                .controlSize(.small)
                .opacity(monitor.isBusy ? 1 : 0)
            if monitor.installed == false {
                Button("Install tinyproxy") { Task { await monitor.install() } }
                    .disabled(!monitor.brewAvailable || monitor.isBusy)
            } else {
                Button {
                    Task { await monitor.toggleService() }
                } label: {
                    Text(monitor.running ? "Stop" : "Start").frame(minWidth: 44)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(monitor.installed != true || monitor.isBusy)
            }
        }
        .frame(minHeight: 24)
    }

    private var footer: some View {
        HStack {
            if let lastCheck = monitor.lastCheck {
                Text("Last check: \(lastCheck.formatted(date: .abbreviated, time: .standard))")
            } else {
                Text("Checking…")
            }
            Spacer()
            Button {
                Task { await monitor.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Check now")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var statusColor: Color {
        guard monitor.brewAvailable, monitor.installed == true else { return .gray }
        return monitor.running ? .green : .red
    }

    private var statusText: String {
        if !monitor.brewAvailable { return "Unavailable" }
        switch monitor.installed {
        case nil: return "Checking…"
        case false?: return "Not installed"
        case true?: return monitor.running ? "Running" : "Stopped"
        }
    }
}
