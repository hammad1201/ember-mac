import Foundation

// Ember's background agent. launchd runs it every 8 minutes (and at login), so the desktop widget
// stays fresh while the Ember app is closed. Each run reads the sensors, writes the widget's
// snapshot and exits: nothing stays in memory between runs.

let groups = SensorReader.group(SensorReader().read())
if let chip = groups.first(where: { $0.kind == .chip }) ?? groups.first {
    SnapshotWriter.write(chip: chip, power: PowerReader.read(), reloadWidget: true)
}
