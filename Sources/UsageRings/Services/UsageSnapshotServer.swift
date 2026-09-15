import UsageCore
import Foundation
import Network

/// A loopback-only, read-only bridge. It has no credential, file, or action endpoints.
@MainActor
final class UsageSnapshotServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "work.hayashigoto.UsageRings.usage-bridge")

    func start(snapshot: @escaping @MainActor @Sendable () -> UsageSnapshot,
               onStateChange: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                        port: NWEndpoint.Port(rawValue: UsageSnapshot.bridgePort)!)
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { state in
                if case .ready = state { Task { @MainActor in onStateChange(true) } }
                if case .failed = state { Task { @MainActor in onStateChange(false) } }
            }
            let queue = queue
            listener.newConnectionHandler = { connection in
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
                Self.receive(connection, buffered: Data(), snapshot: snapshot)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch { onStateChange(false) }
    }

    nonisolated private static func receive(_ connection: NWConnection, buffered: Data,
                                           snapshot: @escaping @MainActor @Sendable () -> UsageSnapshot) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { bytes, _, complete, error in
            var request = buffered
            if let bytes { request.append(bytes) }
            guard error == nil, request.count <= 4096 else { connection.cancel(); return }
            guard request.range(of: Data("\r\n\r\n".utf8)) != nil else {
                if complete { connection.cancel() } else { receive(connection, buffered: request, snapshot: snapshot) }
                return
            }
            guard accepts(request) else {
                send(connection, status: "403 Forbidden", body: Data())
                return
            }
            Task { @MainActor in
                let body = (try? JSONEncoder().encode(snapshot())) ?? Data()
                send(connection, status: "200 OK", body: body)
            }
        }
    }

    nonisolated static func accepts(_ request: Data) -> Bool {
        guard let text = String(data: request, encoding: .utf8) else { return false }
        let lines = text.components(separatedBy: "\r\n")
        guard lines.first == "GET /v1/usage HTTP/1.1" else { return false }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { return false }
            let key = pair[0].lowercased()
            guard headers[key] == nil else { return false }
            headers[key] = pair[1].trimmingCharacters(in: .whitespaces)
        }
        return headers["host"] == "127.0.0.1:\(UsageSnapshot.bridgePort)"
            && headers["x-usage-rings-widget"] == "1" && headers["origin"] == nil
    }

    nonisolated private static func send(_ connection: NWConnection, status: String, body: Data) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
