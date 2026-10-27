import Foundation
import os

/// The small summary Ember writes to its App Group container for the desktop widget.
struct Snapshot: Codable, Equatable {
    var date: Date
    var chipMax: Double
    var chipAverage: Double
    var fanRPM: Double?
    var fanFraction: Double?
    var watts: Double?
    var batteryPercent: Int?
    var charging: Bool
    var thermalState: Int
    /// Hottest-sensor reading once a minute, oldest first.
    var history: [Double]

    var state: ProcessInfo.ThermalState { ProcessInfo.ThermalState(rawValue: thermalState) ?? .nominal }

    /// Set at build time in Info.plist; empty when the app was built without a signing team.
    static var appGroup: String? {
        (Bundle.main.object(forInfoDictionaryKey: "EmberAppGroup") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var url: URL? {
        guard let group = appGroup,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return dir.appendingPathComponent("snapshot.json")
    }

    static func load() -> Snapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private static let log = Logger(subsystem: "com.hammad.Ember", category: "snapshot")

    func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return }
        do {
            try data.write(to: url, options: .atomic)
            Self.log.notice("Wrote widget snapshot (\(data.count) bytes)")
        } catch {
            Self.log.error("Couldn't write widget snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    static let placeholder = Snapshot(
        date: .now, chipMax: 62, chipAverage: 57, fanRPM: 2400, fanFraction: 0.31, watts: 21.5,
        batteryPercent: 64, charging: false, thermalState: 0,
        history: [55, 56, 58, 61, 60, 59, 62, 64, 63, 61, 60, 62, 63, 61, 62]
    )
}
