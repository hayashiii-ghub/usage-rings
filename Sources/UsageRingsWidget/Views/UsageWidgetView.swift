import UsageCore
import SwiftUI
import WidgetKit

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        UsageRingsView(snapshot: entry.snapshot, date: entry.date, compact: family == .systemSmall)
            .padding(family == .systemSmall ? 14 : 18)
            .containerBackground(for: .widget) {
                Rectangle().fill(.background)
            }
            .widgetURL(URL(string: "usagerings://usage"))
    }
}
