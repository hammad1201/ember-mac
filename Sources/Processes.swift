import Foundation

struct ProcessUsage: Identifiable, Equatable {
    let pid: Int32
    let name: String
    /// The app bundle this process belongs to (helpers roll up to their parent app).
    let appName: String?
    let appPath: String?
    let cpu: Double
    /// macOS "Energy Impact", the same figure Activity Monitor shows.
    let power: Double
    let memoryMB: Double
    var id: Int32 { pid }
}

/// One row of the "What's using power" table: either an app or a single process.
struct UsageRow: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String?
    let iconPath: String?
    let cpu: Double
    let power: Double
    let memoryMB: Double
}

/// Keeps one `top` running in logging mode and parses each sample as it streams in.
///
/// Spawning `top -l 2` on every refresh scans every process twice and discards the first
/// pass; a single long-lived `top` scans once per interval, which is far cheaper.
final class ProcessStream {
    /// Seconds between samples; Activity Monitor's default too.
    static let interval = 5

    /// Called on the main queue with each new sample.
    var onSample: (([ProcessUsage]) -> Void)?

    private var process: Process?
    private let queue = DispatchQueue(label: "Ember.ProcessStream")
    private var buffer = ""
    private var samplesSeen = 0
    private var pathCache: [Int32: String] = [:]

    var isRunning: Bool { process != nil }

    func start() {
        guard process == nil else { return }
        let top = Process()
        top.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        top.arguments = ["-l", "0", "-s", "\(Self.interval)", "-o", "power", "-n", "40",
                         "-stats", "pid,cpu,power,mem,command"]
        let pipe = Pipe()
        top.standardOutput = pipe
        top.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.queue.async { self?.consume(text, topPID: top.processIdentifier) }
        }
        do {
            try top.run()
            process = top
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    func stop() {
        guard let top = process else { return }
        (top.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        top.terminate()
        process = nil
        queue.async {
            self.buffer = ""
            self.samplesSeen = 0
        }
    }

    deinit { process?.terminate() }

    // Each sample starts with a "Processes:" line; a block is complete once the next one begins.
    private func consume(_ text: String, topPID: Int32) {
        buffer += text
        while let start = buffer.range(of: "Processes:"),
              let next = buffer.range(of: "Processes:", range: start.upperBound..<buffer.endIndex) {
            let block = String(buffer[start.lowerBound..<next.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<next.lowerBound)
            samplesSeen += 1
            // The first sample has no CPU or power deltas yet.
            guard samplesSeen > 1 else { continue }
            let sample = parse(block, topPID: topPID)
            DispatchQueue.main.async { self.onSample?(sample) }
        }
    }

    private func parse(_ block: String, topPID: Int32) -> [ProcessUsage] {
        let lines = block.split(separator: "\n")
        guard let header = lines.firstIndex(where: { $0.hasPrefix("PID") }) else { return [] }
        let ownBundle = Bundle.main.bundlePath.hasSuffix(".app") ? Bundle.main.bundlePath : nil
        var alive = Set<Int32>()

        let rows: [ProcessUsage] = lines[(header + 1)...].compactMap { line in
            // Command goes last because it can contain spaces.
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count == 5, let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]), let power = Double(parts[2]) else { return nil }
            alive.insert(pid)
            let path = executablePath(pid)
            // Our own `top` shows up in its output; count it as Ember's cost.
            let app = pid == topPID
                ? ("Ember", ownBundle)
                : path.flatMap(Self.appBundle).map { ($0.name, Optional($0.path)) }
            return ProcessUsage(
                pid: pid,
                name: pid == topPID ? "top (Ember sampler)"
                    : path.map { ($0 as NSString).lastPathComponent } ?? String(parts[4]).trimmingCharacters(in: .whitespaces),
                appName: app?.0,
                appPath: app?.1,
                cpu: cpu,
                power: power,
                memoryMB: Self.megabytes(parts[3])
            )
        }
        pathCache = pathCache.filter { alive.contains($0.key) }
        return rows
    }

    private func executablePath(_ pid: Int32) -> String? {
        if let cached = pathCache[pid] { return cached }
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        pathCache[pid] = path
        return path
    }

    private static func appBundle(for path: String) -> (name: String, path: String)? {
        if path.contains("/CoreSimulator/") || path.contains("SimulatorRuntime") {
            return ("iOS Simulator", "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app")
        }
        guard let range = path.range(of: ".app/") else { return nil }
        let bundle = String(path[..<range.lowerBound]) + ".app"
        let name = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
        return (name, bundle)
    }

    private static func megabytes(_ field: Substring) -> Double {
        var s = field.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        guard let unit = s.popLast(), let value = Double(s) else { return 0 }
        switch unit {
        case "K": return value / 1024
        case "M": return value
        case "G": return value * 1024
        case "B": return value / 1_048_576
        default: return 0
        }
    }
}

enum UsageRows {
    static func apps(_ processes: [ProcessUsage]) -> [UsageRow] {
        Dictionary(grouping: processes) { $0.appName ?? $0.name }
            .map { name, procs in
                UsageRow(
                    id: name,
                    name: name,
                    subtitle: procs.count > 1 ? "\(procs.count) processes" : nil,
                    iconPath: procs.lazy.compactMap(\.appPath).first,
                    cpu: procs.reduce(0) { $0 + $1.cpu },
                    power: procs.reduce(0) { $0 + $1.power },
                    memoryMB: procs.reduce(0) { $0 + $1.memoryMB }
                )
            }
            .sorted { ($0.power, $0.cpu) > ($1.power, $1.cpu) }
    }

    static func processes(_ processes: [ProcessUsage]) -> [UsageRow] {
        processes
            .map { p in
                let owner = p.appName.flatMap { $0 == p.name ? nil : $0 }
                return UsageRow(
                    id: "\(p.pid)",
                    name: p.name,
                    subtitle: [owner, "PID \(p.pid)"].compactMap { $0 }.joined(separator: " · "),
                    iconPath: p.appPath,
                    cpu: p.cpu,
                    power: p.power,
                    memoryMB: p.memoryMB
                )
            }
            .sorted { ($0.power, $0.cpu) > ($1.power, $1.cpu) }
    }
}
