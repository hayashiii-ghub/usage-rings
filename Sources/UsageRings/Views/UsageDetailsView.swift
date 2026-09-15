import UsageCore
import SwiftUI

struct UsageDetailsView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Usage Rings").font(.title2.weight(.semibold))
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!store.isEnabled || store.isRefreshing)
            }

            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                UsageRingsView(snapshot: store.snapshot, date: timeline.date)
                    .padding(24)
                    .frame(height: 190)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 28))
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(UsageService.allCases) { service in
                        details(store.snapshot.usage(for: service), date: timeline.date)
                    }
                }
            }

            Divider()
            Toggle("Show AI usage", isOn: $store.isEnabled)
            Text("Refreshes every 5 minutes while Usage Rings is running. Claude usage comes from Claude Code activity.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Grok Bot uses the account signed in to Cursor on this Mac.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("To add the widget, right-click your desktop, choose Edit Widgets, then search for Usage Rings.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if store.sharingError {
                Text("The widget connection is unavailable. Restart Usage Rings to try again.")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func details(_ usage: ServiceUsage, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(usage.service.name).font(.headline)
                Spacer()
                if let updated = usage.updatedAt {
                    Text("Updated \(updated, format: .dateTime.hour().minute())").font(.caption).foregroundStyle(.secondary)
                }
            }
            if usage.isCurrent(at: date) {
                ForEach(usage.windows) { window in
                    HStack {
                        Text(window.title)
                        Spacer()
                        Text("\(Int(window.remainingPercent.rounded()))% left").monospacedDigit()
                        if let reset = window.resetsAt {
                            Text("· \(reset, format: .dateTime.month(.abbreviated).day().hour().minute())")
                                .foregroundStyle(.secondary)
                                .help("Resets at \(reset.formatted())")
                        }
                    }
                    .font(.callout)
                }
            } else {
                Text(statusText(usage)).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func statusText(_ usage: ServiceUsage) -> String {
        switch usage.state {
        case .disabled: return "Enable AI usage to connect."
        case .signInRequired:
            switch usage.service {
            case .codex: return "Sign in to Codex, then refresh."
            case .cursor: return "Open Cursor and sign in, then refresh."
            case .claude: return "Use Claude Code, then refresh to receive usage."
            case .grokBot: return "Sign in to Cursor with your Grok Bot account, then refresh."
            }
        case .unavailable: return "Could not update. Try refreshing in a moment."
        case .ready: return usage.service == .claude ? "Use Claude Code to update your usage." : "Waiting for a fresh reading."
        }
    }
}
