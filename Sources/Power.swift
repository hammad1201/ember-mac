import Foundation
import IOKit

struct PowerInfo: Equatable {
    var batteryPercent: Int
    var isCharging: Bool
    var onAdapter: Bool
    /// Whole-system power draw in watts.
    var systemWatts: Double?
    /// Positive while charging, negative while discharging.
    var batteryWatts: Double
    var minutesRemaining: Int?
    var cycleCount: Int?
    var healthPercent: Int?

    var statusText: String {
        if isCharging { return "Charging · \(batteryPercent)%" }
        if onAdapter { return "On power adapter · \(batteryPercent)%" }
        var text = "On battery · \(batteryPercent)%"
        if let m = minutesRemaining { text += " · \(m / 60):" + String(format: "%02d", m % 60) + " left" }
        return text
    }
}

/// Reads AppleSmartBattery from the IORegistry (no root needed). Nil on Macs without a battery.
enum PowerReader {
    static func read() -> PowerInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }

        func int(_ key: String, in dict: [String: Any]? = nil) -> Int64? {
            ((dict ?? d)[key] as? NSNumber)?.int64Value
        }
        let battery = d["BatteryData"] as? [String: Any]
        let telemetry = d["PowerTelemetryData"] as? [String: Any]

        let millivolts = Double(int("Voltage") ?? 0)
        let milliamps = Double(int("InstantAmperage") ?? int("Amperage") ?? 0)
        let batteryWatts = millivolts * milliamps / 1_000_000

        let onAdapter = d["ExternalConnected"] as? Bool ?? false
        // The battery gauge only refreshes about once a minute, so prefer the SMC's live reading.
        var systemWatts = SMCReader.systemPower()
        if systemWatts == nil {
            if !onAdapter, batteryWatts < 0 {
                systemWatts = -batteryWatts
            } else if let load = int("SystemLoad", in: telemetry), load > 0 {
                systemWatts = Double(load) / 1000
            }
        }

        let remaining = int("TimeRemaining").map(Int.init)
        let design = int("DesignCapacity", in: battery) ?? 0
        let nominal = int("NominalChargeCapacity", in: battery) ?? 0

        return PowerInfo(
            batteryPercent: Int(int("CurrentCapacity") ?? 0),
            isCharging: d["IsCharging"] as? Bool ?? false,
            onAdapter: onAdapter,
            systemWatts: systemWatts,
            batteryWatts: batteryWatts,
            minutesRemaining: remaining.flatMap { $0 > 0 && $0 < 65535 ? $0 : nil },
            cycleCount: int("CycleCount").map(Int.init),
            healthPercent: design > 0 ? Int(min(100, (Double(nominal) / Double(design) * 100).rounded())) : nil
        )
    }
}

enum SystemStats {
    static var loadAverage: [Double] {
        var values = [Double](repeating: 0, count: 3)
        return getloadavg(&values, 3) == 3 ? values : [0, 0, 0]
    }

    static var swapUsedGB: Double {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Double(usage.xsu_used) / 1_073_741_824
    }

    static let chipName: String = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }()
}
