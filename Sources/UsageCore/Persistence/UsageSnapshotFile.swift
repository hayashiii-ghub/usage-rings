import Foundation

public enum UsageSnapshotFile {
    public static func url() throws -> URL {
        // This is the widget's own sandbox cache; the host app never opens its container.
        let directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        return directory.appendingPathComponent("UsageCore/usage-v1.json")
    }

    public static func read(from url: URL? = nil) -> UsageSnapshot {
        guard let location = try? url ?? Self.url(),
              let data = try? Data(contentsOf: location),
              let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data) else { return .empty }
        return snapshot
    }

    public static func write(_ snapshot: UsageSnapshot, to url: URL? = nil) throws {
        let location = try url ?? Self.url()
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: location, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
    }
}
