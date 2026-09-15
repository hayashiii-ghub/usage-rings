import UsageCore
import Foundation

enum WidgetSnapshotReader {
    static func load() async -> UsageSnapshot {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: UsageSnapshot.bridgeURL)
        request.setValue("1", forHTTPHeaderField: "X-Usage-Rings-Widget")
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 65_536 else {
                return UsageSnapshotFile.read()
            }
            let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: data)
            try? UsageSnapshotFile.write(snapshot)
            return snapshot
        } catch { return UsageSnapshotFile.read() }
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
