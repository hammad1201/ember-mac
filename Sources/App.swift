import AppKit
import SwiftUI

@main
struct EmberApp: App {
    @State private var monitor = Monitor()

    init() {
        LoginItems.shared.prepareAgent()
        // Ember lives in the menu bar, so macOS mustn't quit it just because no window is open.
        ProcessInfo.processInfo.disableAutomaticTermination("Monitoring temperatures from the menu bar")
    }

    var body: some Scene {
        Window("Ember", id: "main") {
            ContentView().environment(monitor)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1040, height: 900)

        Settings {
            SettingsView()
        }

        MenuBarExtra {
            MenuBarPanel().environment(monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
