import AppKit
import SwiftUI

@main
struct TinyproxyGUIApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("Tinyproxy", id: "main") {
            ContentView()
                .environmentObject(appDelegate.monitor)
                .modifier(MainWindowOpenerCapture(appDelegate: appDelegate))
        }
        .windowResizability(.contentSize)
        .commands {
            TinyproxyCommands(monitor: appDelegate.monitor)
        }
    }
}

/// Hands SwiftUI's `openWindow` action to the app delegate, so the status item can reopen
/// the window after it was closed. The action is only available from inside a view.
private struct MainWindowOpenerCapture: ViewModifier {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            appDelegate.openMainWindow = { openWindow(id: "main") }
        }
    }
}

struct TinyproxyCommands: Commands {
    @ObservedObject var monitor: TinyproxyMonitor
    @AppStorage(AppSettings.showDockIconKey) private var showDockIcon = true

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

            Divider()
            Button(StatusReportingDialog.menuTitle) {
                StatusReportingDialog.present(for: monitor)
            }
        }

        // The `.sidebar` group lives in the View menu.
        CommandGroup(after: .sidebar) {
            Button("Logs") { monitor.openLogs() }
                .keyboardShortcut("l")
            Divider()
            Toggle("Show Dock Icon", isOn: $showDockIcon)
        }
    }
}

enum AppSettings {
    static let showDockIconKey = "showDockIcon"
}

extension UserDefaults {
    /// Key-value observable, so the app delegate sees changes made through `@AppStorage`.
    /// The property name must match `AppSettings.showDockIconKey`.
    @objc dynamic var showDockIcon: Bool { bool(forKey: AppSettings.showDockIconKey) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owned here rather than by the window, so checks and status reporting keep running
    /// while the window is closed.
    let monitor = TinyproxyMonitor()

    /// Opens the main window, or brings it to the front if it's already open. Set once the window appears.
    var openMainWindow: (() -> Void)?

    private var statusItem: NSStatusItem?
    private var dockIconObservation: NSKeyValueObservation?

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [AppSettings.showDockIconKey: true])
        // Applied before launch finishes so a hidden Dock icon doesn't appear at all.
        applyDockIconPreference()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor.start()
        setUpStatusItem()
        dockIconObservation = UserDefaults.standard.observe(\.showDockIcon) { [weak self] _, _ in
            Task { @MainActor in self?.applyDockIconPreference() }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The app keeps running in the menu bar after its window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon while the window is closed reopens it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return false
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let openMainWindow {
            openMainWindow()
        } else {
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: Dock icon

    private func applyDockIconPreference() {
        // `.regular` is also needed when launched as a bare executable (`swift run`) rather than from the .app bundle.
        let policy: NSApplication.ActivationPolicy = UserDefaults.standard.showDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Changing the policy deactivates the app; bring it back so the window doesn't drop behind other apps.
        if NSApp.isRunning {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func toggleDockIcon() {
        UserDefaults.standard.set(!UserDefaults.standard.showDockIcon, forKey: AppSettings.showDockIconKey)
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.statusIcon()
            button.toolTip = "Tinyproxy"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    private static func statusIcon() -> NSImage? {
        if let image = NSImage(named: "StatusIcon") {
            image.size = NSSize(width: 24, height: 18)
            // Monochrome: macOS tints it for light and dark menu bars.
            image.isTemplate = true
            image.accessibilityDescription = "Tinyproxy"
            return image
        }
        // `swift run` has no app bundle, so no StatusIcon.tiff.
        return NSImage(systemSymbolName: "network", accessibilityDescription: "Tinyproxy")
    }

    /// Click opens the window; right-click or Control-click shows a menu.
    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showStatusMenu()
        } else {
            showMainWindow()
        }
    }

    private func showStatusMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open Tinyproxy", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let dockIcon = NSMenuItem(title: "Show Dock Icon", action: #selector(toggleDockIcon), keyEquivalent: "")
        dockIcon.target = self
        dockIcon.state = UserDefaults.standard.showDockIcon ? .on : .off
        menu.addItem(dockIcon)

        let reporting = NSMenuItem(title: StatusReportingDialog.menuTitle, action: #selector(configureReporting), keyEquivalent: "")
        reporting.target = self
        menu.addItem(reporting)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Tinyproxy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Attach the menu only for this click, so a plain click keeps opening the window.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openFromMenu() {
        showMainWindow()
    }

    @objc private func configureReporting() {
        StatusReportingDialog.present(for: monitor)
    }
}
