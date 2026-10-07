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
            // The small widget has no percentage rows: use the full square for its 2 × 2 grid.
            let size = max(1, min(compact ? (geometry.size.width - 14) / 2 : (geometry.size.width - 48) / 4,
                           compact ? (geometry.size.height - 14) / 2 : geometry.size.height * 0.62))
            if compact {
                VStack(spacing: 14) {
                    HStack(spacing: 14) { ring(.codex, size: size); ring(.claude, size: size) }
                    HStack(spacing: 14) { ring(.cursor, size: size); ring(.grokBot, size: size) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ring(.codex, size: size)
                    ring(.claude, size: size)
                    ring(.cursor, size: size)
                    ring(.grokBot, size: size)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func ring(_ service: UsageService, size: CGFloat) -> some View {
        let usage = snapshot.usage(for: service)
        let remaining = usage.remainingPercent(at: date)
        return VStack(spacing: 16) {
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
                    .frame(width: size * 0.60, height: size * 0.60)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .bottom) {
                // Preserve an explicit unknown state without reserving a percentage row.
                // A current, exhausted allowance has no badge; stale data never looks current.
                if compact && remaining == nil {
                    Text("—")
                        .font(.system(size: size * 0.22, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 3)
                        .background(.background, in: Capsule())
                        .offset(y: 2)
                }
            }
            if !compact {
                Text(remaining.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.system(size: size * 0.27, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(remaining == nil ? .secondary : .primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(service.name)
        .accessibilityValue(remaining.map { "\(Int($0.rounded())) percent remaining" } ?? "Usage unavailable. Open Usage Rings to refresh.")
    }

    private func track(size: CGFloat) -> some View {
        Circle().stroke(.primary.opacity(0.13), lineWidth: size * 0.095).padding(size * 0.048)
    }

    private func color(_ remaining: Double) -> Color {
        remaining <= 10 ? .red : remaining <= 20 ? .yellow : .green
    }
}
