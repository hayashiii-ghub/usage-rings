import Darwin
import Foundation
import UsageCore

enum CodexAppServerError: Error, Equatable {
    case cliUnavailable, unsupportedCLI, signInRequired, invalidResponse, requestFailed, timedOut

    var state: UsageState {
        switch self {
        case .cliUnavailable, .unsupportedCLI: return .setupRequired
        case .signInRequired: return .signInRequired
        case .invalidResponse, .requestFailed, .timedOut: return .unavailable
        }
    }
}

enum CodexAppServerClient {
    // Direct execution of fixed install locations; never run a shell or resolve a user-supplied PATH.
    static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> URL? {
        ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", home.appendingPathComponent(".local/bin/codex").path]
            .first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }

    static func fetch() async -> ServiceUsage {
        guard let executable = executable() else {
            return ServiceUsage(service: .codex, state: .setupRequired)
        }
        do {
            return try await read(executable: executable)
        } catch let error as CodexAppServerError {
            return ServiceUsage(service: .codex, state: error.state)
        } catch {
            return ServiceUsage(service: .codex, state: .unavailable)
        }
    }

    static func read(executable: URL, arguments: [String] = launchArguments,
                     versionArguments: [String] = ["--version"],
                     timeout: TimeInterval = 20) async throws -> ServiceUsage {
        // The older CLI may ignore explicitGatewayOauth and authorize automatically after initialize.
        // Check a known-compatible stable version without starting the server or loading account state.
        let probe = CodexAppServerConnection(executable: executable, arguments: versionArguments,
                                            timeout: min(timeout, 3), versionOnly: true)
        _ = try await run(probe)
        try Task.checkCancellation()
        let connection = CodexAppServerConnection(executable: executable, arguments: arguments, timeout: timeout)
        guard case .usage(let usage) = try await run(connection) else { throw CodexAppServerError.invalidResponse }
        return usage
    }

    private static func run(_ connection: CodexAppServerConnection) async throws -> CodexAppServerOutput {
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await connection.read()
        } onCancel: {
            connection.cancel()
        }
    }

    // Overrides only affect this short-lived process. The CLI owns its saved authentication.
    static let launchArguments = [
        "app-server", "--listen", "stdio://",
        "--disable", "plugins", "--disable", "apps",
        "--disable", "local_thread_store_compression", "--disable", "background_paginated_rollout_migration",
        "-c", "analytics.enabled=false", "-c", "feedback.enabled=false"
    ]

    static func supportedVersion(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.hasPrefix("codex-cli ") else { return false }
        let components = text.dropFirst("codex-cli ".count).split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) }),
              let major = Int(components[0]), let minor = Int(components[1]), let patch = Int(components[2]) else { return false }
        return major > 0 || minor > 160 || (minor == 160 && patch >= 1)
    }
}

private enum CodexAppServerOutput { case version, usage(ServiceUsage) }

/// One bounded, read-only JSONL exchange. No thread, turn, tool, login or configuration-write RPCs.
/// Protocol: https://learn.chatgpt.com/docs/app-server
/// Gateway support must be probed even after initialize, since old CLIs ignore unknown capabilities:
/// https://github.com/openai/codex/blob/rust-v0.160.1/codex-rs/app-server/README.md#gateway-oauth-sign-in
private final class CodexAppServerConnection: @unchecked Sendable {
    private let queue = DispatchQueue(label: "UsageRings.CodexAppServer")
    private let executable: URL
    private let arguments: [String]
    private let timeout: TimeInterval
    private let versionOnly: Bool
    private var continuation: CheckedContinuation<CodexAppServerOutput, Error>?
    private var outcome: Result<CodexAppServerOutput, Error>?
    private var cancelled = false
    private var pid: pid_t = 0
    private var inputFD: Int32 = -1
    private var outputFD: Int32 = -1
    private var outputSource: DispatchSourceRead?
    private var processSource: DispatchSourceProcess?
    private var timer: DispatchSourceTimer?
    private var workingDirectory: URL?
    private var buffer = Data()
    private var outputBytes = 0
    private var expectedID = 1
    private var sawRateLimitUpdate = false
    private var refetched = false
    private static let maximumLineBytes = 65_536
    private static let maximumOutputBytes = 262_144

    init(executable: URL, arguments: [String], timeout: TimeInterval, versionOnly: Bool = false) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = max(0.01, min(timeout, 60))
        self.versionOnly = versionOnly
    }

    func read() async throws -> CodexAppServerOutput {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                if self.cancelled { self.stop(.failure(CancellationError())); return }
                self.start()
            }
        }
    }

    func cancel() {
        queue.async {
            self.cancelled = true
            if self.continuation != nil { self.stop(.failure(CancellationError())) }
        }
    }

    private func start() {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("usage-rings-codex-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            workingDirectory = directory
            try spawn(in: directory)
            let source = DispatchSource.makeReadSource(fileDescriptor: outputFD, queue: queue)
            source.setEventHandler { [weak self] in self?.drainOutput() }
            outputSource = source
            source.resume()

            let child = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
            child.setEventHandler { [weak self] in self?.childExited() }
            processSource = child
            child.resume()

            let deadline = DispatchSource.makeTimerSource(queue: queue)
            deadline.schedule(deadline: .now() + timeout)
            deadline.setEventHandler { [weak self] in self?.stop(.failure(CodexAppServerError.timedOut)) }
            timer = deadline
            deadline.resume()
            if versionOnly {
                close(inputFD); inputFD = -1
                return
            }
            try send(id: 1, method: "initialize", params: [
                "clientInfo": ["name": "usage_rings", "version": "1"],
                "capabilities": ["experimentalApi": false, "explicitGatewayOauth": true]
            ])
        } catch {
            stop(.failure(error as? CodexAppServerError ?? .requestFailed))
        }
    }

    private func spawn(in directory: URL) throws {
        var input: [Int32] = [-1, -1]
        var output: [Int32] = [-1, -1]
        guard pipe(&input) == 0 else { throw CodexAppServerError.requestFailed }
        guard pipe(&output) == 0 else {
            close(input[0]); close(input[1]); throw CodexAppServerError.requestFailed
        }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            input.forEach { close($0) }; output.forEach { close($0) }
            throw CodexAppServerError.requestFailed
        }
        guard posix_spawnattr_init(&attributes) == 0 else {
            posix_spawn_file_actions_destroy(&actions)
            input.forEach { close($0) }; output.forEach { close($0) }
            throw CodexAppServerError.requestFailed
        }
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
            close(input[0]); close(output[1])
        }
        // A separate process group lets cancellation also stop any CLI background descendants.
        let flags = Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)
        let setup = [
            posix_spawnattr_setflags(&attributes, flags),
            posix_spawnattr_setpgroup(&attributes, 0),
            posix_spawn_file_actions_adddup2(&actions, input[0], STDIN_FILENO),
            posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO),
            posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0),
            posix_spawn_file_actions_addchdir(&actions, directory.path),
            fcntl(input[1], F_SETNOSIGPIPE, 1),
            fcntl(input[1], F_SETFL, O_NONBLOCK),
            fcntl(output[0], F_SETFL, O_NONBLOCK)
        ]
        guard setup.allSatisfy({ $0 == 0 }) else {
            close(input[1]); close(output[0]); throw CodexAppServerError.requestFailed
        }
        let environment = [
            "HOME=\(FileManager.default.homeDirectoryForCurrentUser.path)",
            "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR=\(FileManager.default.temporaryDirectory.path)", "LANG=en_US.UTF-8",
            // Exact 0.160.1 CLI source: use DisabledEphemeral instead of saved remote-control
            // enrollment; this changes neither preferences nor authentication. No remote RPCs follow.
            // codex-rs/app-server-transport/src/transport/remote_control/mod.rs
            "CODEX_INTERNAL_APP_SERVER_REMOTE_CONTROL_DISABLED=1"
        ]
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        let result = argv.withUnsafeBufferPointer { argv in
            envp.withUnsafeBufferPointer { envp in
                posix_spawn(&pid, executable.path, &actions, &attributes, argv.baseAddress!, envp.baseAddress!)
            }
        }
        guard result == 0 else {
            pid = 0; close(input[1]); close(output[0])
            throw result == ENOENT || result == EACCES ? CodexAppServerError.cliUnavailable : .requestFailed
        }
        inputFD = input[1]
        outputFD = output[0]
    }

    private func send(id: Int? = nil, method: String, params: [String: Any]? = nil) throws {
        var message: [String: Any] = ["method": method]
        if let id { message["id"] = id; expectedID = id }
        if let params { message["params"] = params }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        // All permitted requests are small enough to be atomic pipe writes.
        guard data.count <= 4_096, inputFD >= 0 else { throw CodexAppServerError.requestFailed }
        let count = data.withUnsafeBytes { Darwin.write(inputFD, $0.baseAddress, $0.count) }
        guard count == data.count else { throw CodexAppServerError.requestFailed }
    }

    private func drainOutput() {
        guard outcome == nil, outputFD >= 0 else { return }
        var bytes = [UInt8](repeating: 0, count: 8_192)
        while outcome == nil {
            let count = Darwin.read(outputFD, &bytes, bytes.count)
            if count == 0 {
                if !versionOnly { stop(.failure(CodexAppServerError.requestFailed)) }
                return
            }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                if errno == EINTR { continue }
                stop(.failure(CodexAppServerError.requestFailed)); return
            }
            outputBytes += count
            guard outputBytes <= (versionOnly ? 4_096 : Self.maximumOutputBytes) else {
                stop(.failure(CodexAppServerError.invalidResponse)); return
            }
            buffer.append(contentsOf: bytes.prefix(count))
            if versionOnly { continue }
            while outcome == nil, let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                guard line.count <= Self.maximumLineBytes else { stop(.failure(CodexAppServerError.invalidResponse)); return }
                let data = Data(line)
                buffer.removeSubrange(...newline)
                handle(data)
            }
            guard buffer.count <= Self.maximumLineBytes else { stop(.failure(CodexAppServerError.invalidResponse)); return }
        }
    }

    private func handle(_ data: Data) {
        do {
            guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CodexAppServerError.invalidResponse
            }
            if let method = message["method"] as? String {
                // No server-initiated requests (including token-refresh or tool requests) are executed.
                if message["id"] != nil { throw CodexAppServerError.requestFailed }
                guard message["result"] == nil, message["error"] == nil else { throw CodexAppServerError.invalidResponse }
                if method == "account/rateLimits/updated", expectedID >= 4 {
                    guard let params = message["params"] as? [String: Any], params["rateLimits"] is [String: Any] else {
                        throw CodexAppServerError.invalidResponse
                    }
                    sawRateLimitUpdate = true
                }
                return
            }
            guard message["method"] == nil,
                  let rawID = message["id"] as? NSNumber,
                  CFGetTypeID(rawID) != CFBooleanGetTypeID(),
                  let id = message["id"] as? Int, id == expectedID else { throw CodexAppServerError.invalidResponse }
            if message["error"] != nil {
                guard message["result"] == nil, let error = message["error"] as? [String: Any] else {
                    throw CodexAppServerError.invalidResponse
                }
                // Raw CLI errors can contain account/config information, so never expose or log them.
                if error["code"] as? Int == -32601 { throw CodexAppServerError.unsupportedCLI }
                if id == 3, error["code"] as? Int == -32603,
                   error["message"] as? String == "workspace routing discovery unauthorized (401)" {
                    throw CodexAppServerError.signInRequired
                }
                // Exact fixed messages from account_processor.rs in 0.160.1, without raw diagnostics.
                if id >= 4, error["code"] as? Int == -32600,
                   let message = error["message"] as? String,
                   ["codex account authentication required to read rate limits",
                    "chatgpt authentication required to read rate limits"].contains(message) {
                    throw CodexAppServerError.signInRequired
                }
                throw CodexAppServerError.requestFailed
            }
            guard let result = message["result"] as? [String: Any] else { throw CodexAppServerError.invalidResponse }
            switch id {
            case 1:
                guard result["userAgent"] is String, result["codexHome"] is String,
                      result["platformFamily"] is String, result["platformOs"] is String else {
                    throw CodexAppServerError.invalidResponse
                }
                try send(method: "initialized")
                try send(id: 2, method: "account/gatewayOAuth/read")
            case 2:
                guard let required = Self.boolean(result["required"]) else { throw CodexAppServerError.invalidResponse }
                if required && result["status"] as? String != "succeeded" { throw CodexAppServerError.signInRequired }
                try send(id: 3, method: "account/read", params: ["refreshToken": false])
            case 3:
                guard Self.boolean(result["requiresOpenaiAuth"]) != nil else { throw CodexAppServerError.invalidResponse }
                guard let account = result["account"] as? [String: Any], account["type"] as? String == "chatgpt" else {
                    throw CodexAppServerError.signInRequired
                }
                try requestRateLimits(id: 4)
            case 4, 5:
                if sawRateLimitUpdate && !refetched {
                    // Rolling notifications are sparse; use a fresh full snapshot instead of clearing fields.
                    refetched = true
                    sawRateLimitUpdate = false
                    try requestRateLimits(id: 5)
                    return
                }
                let payload = try JSONSerialization.data(withJSONObject: result)
                let usage: ServiceUsage
                do { usage = try UsageResponseParser.codex(payload) }
                catch { throw CodexAppServerError.invalidResponse }
                stop(.success(.usage(usage)))
            default: throw CodexAppServerError.invalidResponse
            }
        } catch {
            stop(.failure(error as? CodexAppServerError ?? .invalidResponse))
        }
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private func requestRateLimits(id: Int) throws {
        // Background polls do not request reset-credit details or opt into reserve experiments.
        try send(id: id, method: "account/rateLimits/read", params: ["excludeResetCreditDetails": true])
    }

    private func stop(_ result: Result<CodexAppServerOutput, Error>) {
        guard outcome == nil else { return }
        outcome = result
        timer?.cancel(); timer = nil
        if inputFD >= 0 { close(inputFD); inputFD = -1 }
        guard pid > 0 else { finish(); return }
        // Give stdin EOF a brief opportunity to shut down, then stop the entire owned process group.
        let group = pid
        queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.pid == group else { return }
            _ = kill(-group, SIGTERM)
        }
        queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.pid == group else { return }
            _ = kill(-group, SIGKILL)
        }
    }

    private func childExited() {
        guard pid > 0 else { return }
        if outcome == nil { drainOutput() }
        // Stop descendants even when the CLI parent exited before them; then reap our child.
        _ = kill(-pid, SIGKILL)
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        pid = 0
        if outcome == nil {
            if versionOnly && status == 0 && CodexAppServerClient.supportedVersion(buffer) {
                outcome = .success(.version)
            } else {
                outcome = .failure(versionOnly ? CodexAppServerError.unsupportedCLI : .requestFailed)
            }
        }
        finish()
    }

    private func finish() {
        timer?.cancel(); timer = nil
        outputSource?.cancel(); outputSource = nil
        processSource?.cancel(); processSource = nil
        if inputFD >= 0 { close(inputFD); inputFD = -1 }
        if outputFD >= 0 { close(outputFD); outputFD = -1 }
        buffer.removeAll(keepingCapacity: false)
        if let workingDirectory { try? FileManager.default.removeItem(at: workingDirectory) }
        workingDirectory = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: outcome ?? .failure(CodexAppServerError.requestFailed))
    }
}
