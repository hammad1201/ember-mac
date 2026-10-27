import Foundation
import Observation
import os
import WidgetKit

struct HistorySample: Identifiable, Equatable {
    let date: Date
    let chipMax: Double
    let chipAverage: Double
    let watts: Double?
    var id: Date { date }
}

@MainActor
@Observable
final class Monitor {
    private(set) var readings: [SensorReading] = []
    private(set) var groups: [SensorGroup] = []
    private(set) var fans: [Fan] = []
    private(set) var power: PowerInfo?
    private(set) var processes: [ProcessUsage] = []
    private(set) var history: [HistorySample] = []
    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    private(set) var loadAverage: Double = 0
    private(set) var swapUsedGB: Double = 0
    /// Hottest chip sensor in whole degrees; the only value the menu bar label needs.
    private(set) var menuTemperature: Int?

    static let historyWindow: TimeInterval = 10 * 60
    private static let sensorInterval: TimeInterval = 2

    @ObservationIgnored private let sensors = SensorReader()
    @ObservationIgnored private let processStream = ProcessStream()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var historyBuffer: [HistorySample] = []
    @ObservationIgnored private var dashboardVisible = false
    @ObservationIgnored private var menuOpen = false
    @ObservationIgnored private var scrolling = false
    @ObservationIgnored private var lastSnapshot = Date.distantPast
    @ObservationIgnored private var snapshotHistory: [Double] = []
    @ObservationIgnored private var snapshotsWritten = 0
    @ObservationIgnored private var ticks = 0

    /// While nobody is looking, only the menu bar temperature is published, so SwiftUI doesn't
    /// re-render the dashboard and `top` isn't running.
    private var isWatched: Bool { dashboardVisible || menuOpen }

    init() {
        processStream.onSample = { [weak self] sample in
            MainActor.assumeIsolated {
                guard let self, !self.scrolling else { return }
                self.update(\.processes, sample)
            }
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.sensorInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // With no window or menu open, only the menu bar label and widget need data: every 6 s is plenty.
                self.ticks += 1
                if self.isWatched || self.ticks % 3 == 0 { self.refresh() }
            }
        }
        timer?.tolerance = 0.5
    }

    var chip: SensorGroup? { groups.first { $0.kind == .chip } ?? groups.first }
    var appRows: [UsageRow] { UsageRows.apps(processes) }
    var processRows: [UsageRow] { UsageRows.processes(processes) }

    var temperatureDomain: ClosedRange<Double> {
        let values = history.flatMap { [$0.chipMax, $0.chipAverage] }
        guard let lo = values.min(), let hi = values.max() else { return 30...100 }
        let lower = (lo / 10).rounded(.down) * 10
        return lower...max((hi / 10).rounded(.up) * 10, lower + 20)
    }

    func setDashboardVisible(_ visible: Bool) {
        guard visible != dashboardVisible else { return }
        dashboardVisible = visible
        watchersChanged()
    }

    func setMenuOpen(_ open: Bool) {
        guard open != menuOpen else { return }
        menuOpen = open
        watchersChanged()
    }

    /// Holds back UI updates during a scroll so a mid-scroll re-layout can't cause a hitch.
    func setScrolling(_ isScrolling: Bool) {
        guard isScrolling != scrolling else { return }
        scrolling = isScrolling
        if !isScrolling { refresh() }
    }

    @ObservationIgnored private let log = Logger(subsystem: "com.hammad.Ember", category: "monitor")

    private func watchersChanged() {
        log.debug("watchers: dashboard=\(self.dashboardVisible) menu=\(self.menuOpen)")
        if isWatched {
            refresh()
            processStream.start()
        } else {
            processStream.stop()
        }
    }

    private func refresh() {
        let readings = sensors.read()
        let groups = SensorReader.group(readings)
        let chip = groups.first { $0.kind == .chip } ?? groups.first
        let power = PowerReader.read()

        let now = Date()
        if let chip {
            historyBuffer.append(HistorySample(date: now, chipMax: chip.maximum, chipAverage: chip.average, watts: power?.systemWatts))
        }
        historyBuffer.removeAll { now.timeIntervalSince($0.date) > Self.historyWindow }
        update(\.menuTemperature, chip.map { Int($0.maximum.rounded()) })
        if let chip, now.timeIntervalSince(lastSnapshot) >= 60 {
            writeSnapshot(chip: chip, power: power, at: now)
        }

        guard isWatched, !scrolling else { return }
        update(\.readings, readings)
        update(\.groups, groups)
        update(\.fans, SMCReader.fans())
        update(\.power, power)
        update(\.thermalState, ProcessInfo.processInfo.thermalState)
        update(\.loadAverage, (SystemStats.loadAverage[0] * 10).rounded() / 10)
        update(\.swapUsedGB, (SystemStats.swapUsedGB * 10).rounded() / 10)
        update(\.history, historyBuffer)
    }

    /// Writes the widget's snapshot (once a minute) and nudges WidgetKit every 5 minutes.
    private func writeSnapshot(chip: SensorGroup, power: PowerInfo?, at now: Date) {
        guard Snapshot.url != nil else { return }
        lastSnapshot = now
        snapshotHistory.append(chip.maximum)
        snapshotHistory = Array(snapshotHistory.suffix(30))
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
            history: snapshotHistory
        ).save()
        if snapshotsWritten % 5 == 0 { WidgetCenter.shared.reloadAllTimelines() }
        snapshotsWritten += 1
    }

    /// Assigns only when the value changed, so observers aren't invalidated for nothing.
    private func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<Monitor, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}
