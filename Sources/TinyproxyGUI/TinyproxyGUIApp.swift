import AppKit
import SwiftUI

@main
struct TinyproxyGUIApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var monitor = TinyproxyMonitor()

    var body: some Scene {
        Window("Tinyproxy", id: "main") {
            ContentView()
                .environmentObject(monitor)
                .onAppear { monitor.start() }
        }
        .windowResizability(.contentSize)
        .commands {
            TinyproxyCommands(monitor: monitor)
        }
    }
}

struct TinyproxyCommands: Commands {
    @ObservedObject var monitor: TinyproxyMonitor

    var body: some Commands {
        CommandMenu("Tinyproxy") {
            Button(monitor.running ? "Stop" : "Start") {
                Task { await monitor.toggleService() }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(monitor.installed != true || monitor.isBusy)

            Button("Refresh") {
                Task { await monitor.refresh() }
            }
            .keyboardShortcut("r")
        }

        // The `.sidebar` group lives in the View menu.
        CommandGroup(after: .sidebar) {
            Button("Logs") { monitor.openLogs() }
                .keyboardShortcut("l")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
