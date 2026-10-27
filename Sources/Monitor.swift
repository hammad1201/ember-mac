import CoreGraphics
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
    @ObservationIgnored private var usageVisible = true
    @ObservationIgnored private var userAway = false
    @ObservationIgnored private var listLastNeeded = Date.distantPast

    /// No keyboard or mouse input for this long counts as away: nobody is reading the dashboard.
    private static let awayAfter: TimeInterval = 60

    /// While nobody is looking, only the menu bar temperature is published, so SwiftUI doesn't
    /// re-render the dashboard and `top` isn't running.
    private var isWatched: Bool { (dashboardVisible || menuOpen) && !userAway }

    /// `top` is the expensive part, so it only runs while a process list is actually on screen:
    /// the menu panel, or the dashboard scrolled to "What's using power".
    private var listOnScreen: Bool { isWatched && (menuOpen || usageVisible) }

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
                // Reading 40+ sensors and the SMC happens on the main thread, so skip it mid-scroll;
                // setScrolling(false) refreshes as soon as the scroll ends.
                guard let self, !self.scrolling else { return }
                self.ticks += 1
                self.checkAway()
                // Unwatched, only the menu bar label and widget need data: every 6 s, or 10 s while away.
                let every = self.isWatched ? 1 : (self.userAway ? 5 : 3)
                if self.ticks % every == 0 { self.refresh() }
                self.updateSampler()
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

    func setUsageVisible(_ visible: Bool) {
        guard visible != usageVisible else { return }
        usageVisible = visible
        updateSampler()
    }

    private func watchersChanged() {
        log.debug("watchers: dashboard=\(self.dashboardVisible) menu=\(self.menuOpen) away=\(self.userAway)")
        if isWatched { refresh() }
        updateSampler()
    }

    private func checkAway() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0) ?? .null)
        let away = idle > Self.awayAfter
        guard away != userAway else { return }
        userAway = away
        watchersChanged()
    }

    private func updateSampler() {
        let now = Date()
        if listOnScreen {
            listLastNeeded = now
            processStream.start()
        } else if !isWatched || now.timeIntervalSince(listLastNeeded) > 10 {
            // Scrolling past the list briefly shouldn't restart `top`, so keep it for 10 s after.
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
