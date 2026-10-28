import Foundation
import WidgetKit

/// Builds the widget's snapshot. Shared by the app (once a minute while it runs) and the background
/// agent (every 8 minutes), so the trend is kept in the snapshot file itself rather than in memory.
enum SnapshotWriter {
    /// Trend points are at least this far apart, whoever writes them, and cover this much time.
    static let trendSpacing: TimeInterval = 8 * 60
    static let trendWindow: TimeInterval = 3 * 60 * 60

    static func write(chip: SensorGroup, power: PowerInfo?, at now: Date = .now, reloadWidget: Bool) {
        guard Snapshot.url != nil else { return }
        var history: [Double] = [], dates: [Date] = []
        if let last = Snapshot.load(), let lastDates = last.historyDates, lastDates.count == last.history.count {
            history = last.history
            dates = lastDates
        }
        if let newest = dates.last, now.timeIntervalSince(newest) < trendSpacing {
            // Too soon for a new point: refresh the newest one so the trend ends at the current reading.
            history[history.count - 1] = chip.maximum
        } else {
            history.append(chip.maximum)
            dates.append(now)
        }
        while let oldest = dates.first, now.timeIntervalSince(oldest) > trendWindow {
            dates.removeFirst()
            history.removeFirst()
        }

        let fans = SMCReader.fans()
        Snapshot(
            date: now,
            chipMax: chip.maximum,
            chipAverage: chip.average,
            fanRPM: fans.isEmpty ? nil : fans.map(\.rpm).reduce(0, +) / Double(fans.count),
            fanFraction: fans.isEmpty ? nil : fans.map(\.fraction).reduce(0, +) / Double(fans.count),
            watts: power?.systemWatts,
            batteryPercent: power?.batteryPercent,
            charging: power?.isCharging ?? false,
            thermalState: ProcessInfo.processInfo.thermalState.rawValue,
            history: history,
            historyDates: dates
        ).save()
        if reloadWidget { WidgetCenter.shared.reloadAllTimelines() }
    }
}
