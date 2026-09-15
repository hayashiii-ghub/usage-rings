import SwiftUI

public struct UsageRingsView: View {
    public let snapshot: UsageSnapshot
    public let date: Date
    public let compact: Bool

    public init(snapshot: UsageSnapshot, date: Date, compact: Bool = false) {
        self.snapshot = snapshot
        self.date = date
        self.compact = compact
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = max(1, min(compact ? (geometry.size.width - 20) / 2 : (geometry.size.width - 48) / 4,
                           compact ? (geometry.size.height - 54) / 2 : geometry.size.height * 0.62))
            if compact {
                VStack(spacing: 14) {
                    HStack(spacing: 20) { ring(.codex, size: size); ring(.cursor, size: size) }
                    HStack(spacing: 20) { ring(.claude, size: size); fourthRing(size: size) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ring(.codex, size: size)
                    ring(.cursor, size: size)
                    ring(.claude, size: size)
                    fourthRing(size: size)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func fourthRing(size: CGFloat) -> some View {
        ring(.grokBot, size: size)
    }

    private func ring(_ service: UsageService, size: CGFloat) -> some View {
        let usage = snapshot.usage(for: service)
        let remaining = usage.remainingPercent(at: date)
        return VStack(spacing: compact ? 5 : 16) {
            ZStack {
                track(size: size)
                if let remaining, remaining > 0 {
                    Circle()
                        .trim(from: 0, to: remaining / 100)
                        .stroke(color(remaining), style: StrokeStyle(lineWidth: size * 0.095, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(size * 0.048)
                }
                ServiceMark(service: service)
                    .foregroundStyle(remaining == nil ? .secondary : .primary)
                    .frame(width: size * 0.43, height: size * 0.43)
            }
            .frame(width: size, height: size)
            Text(remaining.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.system(size: compact ? 12 : size * 0.27, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(remaining == nil ? .secondary : .primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(service.name)
        .accessibilityValue(remaining.map { "\(Int($0.rounded())) percent remaining" } ?? "Usage unavailable. Open Usage Rings to refresh.")
    }

    private func empty(size: CGFloat) -> some View {
        VStack(spacing: compact ? 5 : 16) {
            track(size: size).frame(width: size, height: size)
            Text(" ").font(.system(size: compact ? 12 : size * 0.27))
        }
        .accessibilityHidden(true)
    }

    private func track(size: CGFloat) -> some View {
        Circle().stroke(.primary.opacity(0.13), lineWidth: size * 0.095).padding(size * 0.048)
    }

    private func color(_ remaining: Double) -> Color {
        remaining <= 10 ? .red : remaining <= 20 ? .yellow : .green
    }
}

private struct ServiceMark: View {
    let service: UsageService

    var body: some View {
        Image(nsImage: mark)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }

    private var mark: NSImage {
        let resources = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("UsageRings_UsageCore.bundle"))
        } ?? Bundle.module
        guard let url = resources.url(forResource: service.rawValue, withExtension: "svg", subdirectory: "Resources"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        return image
    }
}
