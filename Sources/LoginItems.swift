import Foundation
import Observation
import ServiceManagement

/// "Open at login" and the background agent (Contents/MacOS/EmberAgent), which launchd runs every
/// 8 minutes to keep the desktop widget fresh while the app is closed. Shared by Settings and the menu panel.
@MainActor
@Observable
final class LoginItems {
    static let shared = LoginItems()

    private static let agent = SMAppService.agent(plistName: "com.hammad.Ember.agent.plist")
    private static let offeredKey = "BackgroundAgentOffered"
    /// Bump when Resources/Agent.plist changes: launchd only reads it when the agent is registered.
    private static let plistVersion = 2
    private static let plistVersionKey = "BackgroundAgentPlistVersion"

    /// Only builds signed with a team have the widget, and so the agent.
    let agentAvailable = Snapshot.appGroup != nil
    private(set) var opensAtLogin = false
    private(set) var updatesWidget = false
    /// The user switched Ember's background item off in System Settings; only they can turn it back on there.
    private(set) var agentNeedsApproval = false

    private init() { refresh() }

    /// The widget is no use without the agent, so it's switched on once by default; after that it's the user's call.
    /// Also re-registers an enabled agent once after its launchd plist changes.
    func prepareAgent() {
        guard agentAvailable else { return }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.offeredKey) {
            defaults.set(true, forKey: Self.offeredKey)
            try? Self.agent.register()
        } else if defaults.integer(forKey: Self.plistVersionKey) < Self.plistVersion, Self.agent.status == .enabled {
            try? Self.agent.unregister()
            try? Self.agent.register()
        }
        defaults.set(Self.plistVersion, forKey: Self.plistVersionKey)
        refresh()
    }

    func setOpensAtLogin(_ on: Bool) {
        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        refresh()
    }

    func setUpdatesWidget(_ on: Bool) {
        guard agentAvailable else { return }
        try? on ? Self.agent.register() : Self.agent.unregister()
        refresh()
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }

    /// Re-reads the state, which can also change in System Settings › General › Login Items & Extensions.
    func refresh() {
        opensAtLogin = SMAppService.mainApp.status == .enabled
        let status = agentAvailable ? Self.agent.status : .notRegistered
        updatesWidget = status == .enabled
        agentNeedsApproval = status == .requiresApproval
    }
}
