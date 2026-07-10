import Foundation

struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }
}

enum ProcessRunnerError: Error, LocalizedError {
    case timedOut(command: String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let cmd): return "Timed out running: \(cmd)"
        case .launchFailed(let msg): return "Failed to launch process: \(msg)"
        }
    }
}

/// Runs command-line tools on behalf of update sources.
///
/// GUI apps inherit a minimal PATH that lacks `/opt/homebrew/bin`, `~/.cargo/bin`, etc.
/// We therefore run everything through an interactive-ish login shell so the user's
/// normal PATH (Homebrew, cargo, rustup, pipx…) is available. Commands are forced
/// non-interactive so a tool can never block waiting on a TTY prompt.
struct ProcessRunner: Sendable {

    /// A deterministic environment prelude prepended to every command.
    ///
    /// We deliberately do **not** source the user's interactive `~/.zshrc`: on machines
    /// with powerlevel10k/gitstatus that emits prompt/"instant prompt" noise and even
    /// breaks lazy-loaded functions when there's no TTY. Instead we compose a known-good
    /// PATH and activate nvm directly, so tools resolve cleanly and output stays parseable.
    static let shellPrelude = """
    export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
    command -v nvm >/dev/null 2>&1 && nvm use default >/dev/null 2>&1
    if ! command -v npm >/dev/null 2>&1; then
      for d in "$NVM_DIR"/versions/node/*/bin(Nn); do export PATH="$d:$PATH"; done
    fi
    """

    /// Runs `command` through a clean non-interactive zsh with `shellPrelude` applied.
    /// - Parameters:
    ///   - command: A full shell command string.
    ///   - timeout: Max seconds before the process is killed and an error thrown.
    func runShell(_ command: String, timeout: TimeInterval = 120) async throws -> ProcessResult {
        try await run(
            executable: "/bin/zsh",
            arguments: ["-c", "\(Self.shellPrelude)\n\(command)"],
            timeout: timeout
        )
    }

    func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 120
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        // Force non-interactive, quiet behavior for common package managers.
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["NONINTERACTIVE"] = "1"
        env["CI"] = "1"
        env["TERM"] = "dumb"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        // Accumulate output off the pipes to avoid the 64KB buffer deadlock.
        let collector = OutputCollector()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collector.appendOut(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collector.appendErr(data) }
        }

        let commandDescription = "\(executable) \(arguments.joined(separator: " "))"

        return try await withThrowingTaskGroup(of: ProcessResult.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { proc in
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stderrPipe.fileHandleForReading.readabilityHandler = nil
                        // Drain anything remaining.
                        collector.appendOut(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                        collector.appendErr(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                        let result = ProcessResult(
                            stdout: collector.stdoutString,
                            stderr: collector.stderrString,
                            exitCode: proc.terminationStatus
                        )
                        continuation.resume(returning: result)
                    }
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning { process.terminate() }
                throw ProcessRunnerError.timedOut(command: commandDescription)
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw ProcessRunnerError.launchFailed(commandDescription)
            }
            return result
        }
    }
}

/// Thread-safe byte accumulator for the two pipes.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func appendOut(_ data: Data) { lock.lock(); out.append(data); lock.unlock() }
    func appendErr(_ data: Data) { lock.lock(); err.append(data); lock.unlock() }

    var stdoutString: String { lock.lock(); defer { lock.unlock() }; return String(decoding: out, as: UTF8.self) }
    var stderrString: String { lock.lock(); defer { lock.unlock() }; return String(decoding: err, as: UTF8.self) }
}
