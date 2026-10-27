import AppKit
import SwiftUI

@main
struct EmberApp: App {
    @State private var monitor = Monitor()

    var body: some Scene {
        Window("Ember", id: "main") {
            ContentView().environment(monitor)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1040, height: 900)

        MenuBarExtra {
            MenuBarPanel().environment(monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
