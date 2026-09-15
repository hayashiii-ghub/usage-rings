import AppKit
import UsageCore
import SwiftUI
import WidgetKit

@MainActor
final class UsageStore: ObservableObject {
    private static let preferenceKey = "usageMonitoringEnabled"
    @Published private(set) var snapshot: UsageSnapshot = .empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var sharingError = false
    @Published var isEnabled: Bool {
        didSet {
            generation += 1
            UserDefaults.standard.set(isEnabled, forKey: Self.preferenceKey)
            if isEnabled { start() } else { stop() }
        }
    }
    private var pollingTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var generation = 0
    private let bridge = UsageSnapshotServer()

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.preferenceKey) as? Bool ?? true
    }

    func startIfEnabled() {
        bridge.start(snapshot: { [weak self] in self?.snapshot ?? .empty }, onStateChange: { [weak self] ready in
            self?.sharingError = !ready
        })
        if isEnabled { start() }
    }

    func refresh() async {
        guard isEnabled, !isRefreshing else { return }
        isRefreshing = true
        let requestGeneration = generation
        defer { isRefreshing = false }
        async let codex = UsageClient.fetch(.codex)
        async let cursor = UsageClient.fetch(.cursor)
        async let claude = UsageClient.fetch(.claude)
        async let grokBot = UsageClient.fetch(.grokBot)
        let readings = await [codex, cursor, claude, grokBot]
        guard isEnabled, generation == requestGeneration, !Task.isCancelled else { return }
        snapshot = UsageSnapshot(services: readings.map { reading in
            guard reading.state == .unavailable else { return reading }
            var previous = snapshot.usage(for: reading.service)
            previous.state = .unavailable
            return previous
        })
        publish()
    }

    private func start() {
        guard pollingTask == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(5 * 60)) } catch { return }
            }
        }
    }

    private func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        snapshot = .empty
        publish()
    }

    private func publish() {
        WidgetCenter.shared.reloadTimelines(ofKind: UsageSnapshot.widgetKind)
    }
}
