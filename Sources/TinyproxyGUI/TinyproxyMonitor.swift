import AppKit
import Foundation

@MainActor
final class TinyproxyMonitor: ObservableObject {
    static let pollInterval: TimeInterval = 60
    static let serviceChangeTimeout: TimeInterval = 30
    static let brewWebsite = URL(string: "https://brew.sh/")!

    @Published private(set) var brewAvailable = true
    @Published private(set) var installed: Bool?
    @Published private(set) var running = false
    @Published private(set) var pid: Int32?
    @Published private(set) var lastExitCode: Int?
    @Published private(set) var version: String?
    @Published private(set) var latestVersion: String?
    @Published private(set) var outdated = false
    @Published private(set) var busyMessage: String?
    @Published private(set) var isChangingService = false
    @Published private(set) var lastCheck: Date?
    @Published var showBrewMissingAlert = false
    @Published var showInstallPrompt = false
    @Published var errorMessage: String?

    private var brew: Brew?
    private var isRefreshing = false
    private var refreshQueued = false
    private var installPrompted = false
    private var pollTimer: Timer?
    private var exitSource: DispatchSourceProcess?
    private var watchedPid: Int32?
    private var launchAgentsSource: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?

    var isBusy: Bool { busyMessage != nil || isChangingService }

    func start() {
        guard pollTimer == nil else { return }
        // Fallback poll. Process exits and `brew services` changes are picked up immediately by the watchers.
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        watchLaunchAgents()
        Task { await refresh() }
    }

    // MARK: - Status

    func refresh() async {
        guard !isRefreshing else {
            refreshQueued = true
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            if refreshQueued {
                refreshQueued = false
                Task { await refresh() }
            }
        }

        guard let brew = brew ?? Brew.locate() else {
            if brewAvailable { showBrewMissingAlert = true }
            brewAvailable = false
            installed = nil
            running = false
            lastCheck = Date()
            return
        }
        self.brew = brew
        brewAvailable = true

        do {
            let info = try await brew.formulaInfo()
            installed = !info.installed.isEmpty
            version = info.installedVersion
            latestVersion = info.latestVersion
            outdated = info.outdated ?? false

            if installed == true {
                let service = try await brew.serviceInfo()
                running = service.running
                pid = service.running ? service.pid : nil
                lastExitCode = service.exit_code
            } else {
                running = false
                pid = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        watchProcessExit(pid: pid)
        lastCheck = Date()

        // Ask once per launch; the window keeps an Install button afterwards.
        if installed == false && !installPrompted && !isBusy {
            installPrompted = true
            showInstallPrompt = true
        }
    }

    /// Notified by the kernel (kqueue) as soon as the tinyproxy process exits.
    private func watchProcessExit(pid: Int32?) {
        guard pid != watchedPid else { return }
        exitSource?.cancel()
        exitSource = nil
        watchedPid = pid
        guard let pid else { return }

        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        source.resume()
        exitSource = source
    }

    /// `brew services start/stop` adds/removes the plist here, so this catches changes made from a terminal too.
    private func watchLaunchAgents() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents").path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleDebouncedRefresh() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        launchAgentsSource = source
    }

    private func scheduleDebouncedRefresh() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    // MARK: - Actions

    /// Starts or stops the service depending on its current state, then waits until the process
    /// is actually up (or gone): `brew services` returns as soon as launchd has loaded/unloaded the job.
    func toggleService() async {
        guard let brew else {
            showBrewMissingAlert = true
            return
        }
        guard !isBusy else { return }
        isChangingService = true
        defer { isChangingService = false }

        let shouldRun = !running
        let deadline = Date().addingTimeInterval(Self.serviceChangeTimeout)
        let arguments = ["services", shouldRun ? "start" : "stop", Brew.formula]
        let result = await brew.run(arguments)
        guard result.succeeded else {
            errorMessage = BrewError.commandFailed("brew " + arguments.joined(separator: " "), result.stderr)
                .localizedDescription
            await refresh()
            return
        }

        while Date() < deadline {
            if let service = try? await brew.serviceInfo(), service.running == shouldRun { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        await refresh()
    }

    func install() async {
        await perform("Installing tinyproxy with Homebrew…", ["install", Brew.formula])
    }

    func upgrade() async {
        let wasRunning = running
        await perform("Upgrading tinyproxy…", ["upgrade", Brew.formula])
        if wasRunning {
            await perform("Restarting tinyproxy…", ["services", "restart", Brew.formula])
        }
    }

    private func perform(_ message: String, _ arguments: [String]) async {
        guard let brew else {
            showBrewMissingAlert = true
            return
        }
        guard !isBusy else { return }
        busyMessage = message
        let result = await brew.run(arguments)
        busyMessage = nil
        if !result.succeeded {
            errorMessage = BrewError.commandFailed("brew " + arguments.joined(separator: " "), result.stderr)
                .localizedDescription
        }
        await refresh()
    }

    func openBrewWebsite() {
        NSWorkspace.shared.open(Self.brewWebsite)
    }

    // MARK: - Logs

    private static let consoleApp = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")

    func openLogs() {
        guard let brew = brew ?? Brew.locate() else {
            showBrewMissingAlert = true
            return
        }
        let config = TinyproxyConfig.load(prefix: brew.prefix)
        let configuration = NSWorkspace.OpenConfiguration()

        // With `Syslog On` tinyproxy logs to the unified log, which Console shows directly.
        guard !config.usesSyslog else {
            NSWorkspace.shared.openApplication(at: Self.consoleApp, configuration: configuration)
            return
        }

        let logFile = config.logFile
        guard FileManager.default.fileExists(atPath: logFile.path) else {
            errorMessage = "No log file at \(logFile.path) yet. tinyproxy creates it the first time it starts."
            return
        }
        NSWorkspace.shared.open([logFile], withApplicationAt: Self.consoleApp, configuration: configuration)
    }
}

/// The few settings we need from tinyproxy.conf.
struct TinyproxyConfig {
    var logFile: URL
    var usesSyslog = false

    static func load(prefix: URL) -> TinyproxyConfig {
        var config = TinyproxyConfig(logFile: prefix.appendingPathComponent("var/log/tinyproxy/tinyproxy.log"))
        let file = prefix.appendingPathComponent("etc/tinyproxy/tinyproxy.conf")
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return config }

        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" \t"))
            switch parts[0].lowercased() {
            case "logfile": config.logFile = URL(fileURLWithPath: value)
            case "syslog": config.usesSyslog = value.lowercased() == "on"
            default: break
            }
        }
        return config
    }
}
