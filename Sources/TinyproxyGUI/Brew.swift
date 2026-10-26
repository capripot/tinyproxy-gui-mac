import Foundation

struct CommandResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: String

    var succeeded: Bool { status == 0 }
    var output: String { String(decoding: stdout, as: UTF8.self) }
}

/// Thin wrapper around the `brew` executable.
struct Brew: Sendable {
    static let formula = "tinyproxy"

    let executable: URL

    /// GUI apps don't inherit the shell PATH, so look in the standard Homebrew locations first.
    static func locate() -> Brew? {
        var candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/home/linuxbrew/.linuxbrew/bin/brew"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/brew" }
        }
        let fm = FileManager.default
        return candidates.first { fm.isExecutableFile(atPath: $0) }
            .map { Brew(executable: URL(fileURLWithPath: $0)) }
    }

    /// e.g. /opt/homebrew
    var prefix: URL { executable.deletingLastPathComponent().deletingLastPathComponent() }

    func run(_ arguments: [String]) async -> CommandResult {
        let executable = executable
        var environment = ProcessInfo.processInfo.environment
        let basePath = "\(executable.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = environment["PATH"].map { "\(basePath):\($0)" } ?? basePath
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_COLOR"] = "1"
        let finalEnvironment = environment

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.environment = finalEnvironment
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: CommandResult(status: -1, stdout: Data(), stderr: error.localizedDescription))
                    return
                }

                // Drain both pipes concurrently so a chatty `brew install` can't fill a buffer and block.
                nonisolated(unsafe) var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()

                continuation.resume(returning: CommandResult(
                    status: process.terminationStatus,
                    stdout: outData,
                    stderr: String(decoding: errData, as: UTF8.self)
                ))
            }
        }
    }

    // MARK: - JSON models

    struct FormulaInfo: Decodable {
        struct Versions: Decodable { let stable: String? }
        struct Installed: Decodable { let version: String }

        let versions: Versions
        let revision: Int?
        let installed: [Installed]
        let linked_keg: String?
        let outdated: Bool?

        var installedVersion: String? { linked_keg ?? installed.last?.version }
        var latestVersion: String? {
            guard let stable = versions.stable else { return nil }
            if let revision, revision > 0 { return "\(stable)_\(revision)" }
            return stable
        }
    }

    struct ServiceInfo: Decodable {
        let running: Bool
        let loaded: Bool
        let pid: Int32?
        let exit_code: Int?
        let status: String?
    }

    func formulaInfo() async throws -> FormulaInfo {
        let result = await run(["info", "--json=v2", Self.formula])
        guard result.succeeded else { throw BrewError.commandFailed("brew info", result.stderr) }
        struct Wrapper: Decodable { let formulae: [FormulaInfo] }
        guard let info = try JSONDecoder().decode(Wrapper.self, from: result.stdout).formulae.first else {
            throw BrewError.commandFailed("brew info", "Formula \(Self.formula) not found.")
        }
        return info
    }

    func serviceInfo() async throws -> ServiceInfo {
        let result = await run(["services", "info", "--json", Self.formula])
        guard result.succeeded else { throw BrewError.commandFailed("brew services info", result.stderr) }
        guard let info = try JSONDecoder().decode([ServiceInfo].self, from: result.stdout).first else {
            throw BrewError.commandFailed("brew services info", "No service information for \(Self.formula).")
        }
        return info
    }
}

enum BrewError: LocalizedError {
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(command)` failed" + (trimmed.isEmpty ? "." : ":\n\(trimmed)")
        }
    }
}
