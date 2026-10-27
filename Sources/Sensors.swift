import Foundation

struct SensorReading: Identifiable, Hashable {
    let name: String
    let celsius: Double
    var id: String { name }
}

enum SensorKind: Int, CaseIterable, Comparable, Identifiable {
    case chip, performanceCores, efficiencyCores, gpu, ssd, battery, other

    var id: Int { rawValue }
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .chip: "Chip (SoC die)"
        case .performanceCores: "Performance cores"
        case .efficiencyCores: "Efficiency cores"
        case .gpu: "GPU"
        case .ssd: "SSD"
        case .battery: "Battery"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .chip, .performanceCores, .efficiencyCores: "cpu"
        case .gpu: "square.stack.3d.up"
        case .ssd: "internaldrive"
        case .battery: "battery.75percent"
        case .other: "thermometer.medium"
        }
    }

    /// Maps an IOHID sensor product name to a group; nil for calibration sensors.
    init?(sensorName name: String) {
        let s = name.lowercased()
        if s.contains("tcal") { return nil }
        if s.contains("tdie") || s.contains("soc") { self = .chip }
        else if s.contains("pacc") { self = .performanceCores }
        else if s.contains("eacc") { self = .efficiencyCores }
        else if s.contains("gpu") { self = .gpu }
        else if s.contains("nand") { self = .ssd }
        else if s.contains("battery") { self = .battery }
        else { self = .other }
    }
}

struct SensorGroup: Identifiable, Equatable {
    let kind: SensorKind
    let readings: [SensorReading]

    var id: SensorKind { kind }
    var average: Double { readings.map(\.celsius).reduce(0, +) / Double(max(readings.count, 1)) }
    var maximum: Double { readings.map(\.celsius).max() ?? 0 }
    var minimum: Double { readings.map(\.celsius).min() ?? 0 }
}

/// Reads Apple Silicon temperature sensors through the IOHID event system (no root needed).
final class SensorReader {
    private let client: CFTypeRef?
    private let services: [CFTypeRef]

    init() {
        client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        guard let client else { services = []; return }
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = IOHIDEventSystemClientSetMatching(client, matching)
        services = (IOHIDEventSystemClientCopyServices(client) as? [CFTypeRef]) ?? []
    }

    func read() -> [SensorReading] {
        let temperatureEvent: Int64 = 15
        var readings: [SensorReading] = []
        var seen: [String: Int] = [:]
        for service in services {
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String,
                  let event = IOHIDServiceClientCopyEvent(service, temperatureEvent, 0, 0) else { continue }
            let value = IOHIDEventGetFloatValue(event, Int32(temperatureEvent << 16))
            // Unused sensors report 0 or large negative values.
            guard value > 1, value < 130 else { continue }
            // Several sensors share a name (e.g. three "PMU tcal"); keep ids unique.
            let n = seen[name, default: 0]
            seen[name] = n + 1
            // Round to 0.1° so unchanged readings don't trigger redraws.
            readings.append(SensorReading(name: n == 0 ? name : "\(name) #\(n + 1)", celsius: (value * 10).rounded() / 10))
        }
        return readings.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func group(_ readings: [SensorReading]) -> [SensorGroup] {
        let tagged = readings.compactMap { r in SensorKind(sensorName: r.name).map { ($0, r) } }
        return Dictionary(grouping: tagged) { $0.0 }
            .map { SensorGroup(kind: $0.key, readings: $0.value.map { $0.1 }) }
            .sorted { $0.kind < $1.kind }
    }
}

struct Fan: Identifiable, Equatable {
    let id: Int
    let rpm: Double
    let maxRPM: Double
    var fraction: Double { maxRPM > 0 ? min(rpm / maxRPM, 1) : 0 }
}

/// Reads fan speeds and live power from the SMC.
enum SMCReader {
    static let available = smc_open() == 0

    static func fans() -> [Fan] {
        guard available, let count = bytes("FNum")?.first else { return [] }
        return (0..<Int(count)).compactMap { i in
            guard let rpm = number("F\(i)Ac") else { return nil }
            return Fan(id: i, rpm: rpm, maxRPM: number("F\(i)Mx") ?? 0)
        }
    }

    /// Total system power in watts ("PSTR"), refreshed by the SMC about once a second.
    static func systemPower() -> Double? {
        guard available, let watts = number("PSTR"), watts > 0 else { return nil }
        return watts
    }

    private static func bytes(_ key: String) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: 32)
        var size: UInt32 = 0, type: UInt32 = 0
        guard smc_read(key, &buffer, &size, &type) == 0 else { return nil }
        return Array(buffer.prefix(Int(size)))
    }

    private static func number(_ key: String) -> Double? {
        guard let b = bytes(key) else { return nil }
        switch b.count {
        case 4: return Double(b.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }) // "flt " (Apple Silicon)
        case 2: return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4                     // "fpe2" (Intel)
        default: return nil
        }
    }
}
