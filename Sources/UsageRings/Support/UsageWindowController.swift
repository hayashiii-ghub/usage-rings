import AppKit
import SwiftUI

@MainActor
final class UsageWindowController {
    private let store: UsageStore
    private var window: NSWindow?

    init(store: UsageStore) { self.store = store }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 508, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Usage Rings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: UsageDetailsView(store: store))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
