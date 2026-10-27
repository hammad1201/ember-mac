import AppKit
import Charts
import ServiceManagement
import SwiftUI

// MARK: - Palette

/// Who made this; shown in the window footer.
enum Credits {
    static let name = "Muhammad Hammad"
    static let github = URL(string: "https://github.com/hammad1201")!
    static let x: URL? = URL(string: "https://x.com/hammad_1201")
}

/// Heat scale within the theme: champagne when cool, deepening to crimson when hot.
func temperatureColor(_ celsius: Double) -> Color {
    switch celsius {
    case ..<55: Theme.champagne
    case ..<75: Theme.rose
    case ..<90: Theme.wine
    default: Theme.crimson
    }
}

/// Broad temperature bands; the window's ambient glow follows these.
enum HeatBand: Equatable {
    case cool, warm, hot, critical

    init(_ celsius: Double) {
        switch celsius {
        case ..<55: self = .cool
        case ..<75: self = .warm
        case ..<90: self = .hot
        default: self = .critical
        }
    }

    /// Always burgundy; the glow gets brighter and redder as the chip heats up.
    var glow: [Color] {
        switch self {
        case .cool: [Theme.burgundy, Theme.deepWine, Theme.wine]
        case .warm: [Theme.wine, Theme.burgundy, Theme.rose]
        case .hot: [Theme.rose, Theme.wine, Theme.crimson]
        case .critical: [Theme.crimson, Theme.wine, Theme.rose]
        }
    }
}

func formatMemory(_ mb: Double) -> String {
    mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
}

// MARK: - Building blocks

/// A Liquid Glass panel with a faint wine tint.
struct GlassTile<Content: View>: View {
    var tint: Color? = nil
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(.regular.tint((tint ?? Theme.burgundy).opacity(0.16)), in: .rect(cornerRadius: 22))
    }
}

/// Soft mesh-gradient glow behind the glass, coloured by how hot the chip is.
struct AmbientBackground: View {
    let band: HeatBand

    var body: some View {
        let c = band.glow
        MeshGradient(
            width: 3, height: 3,
            points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.6, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
            colors: [
                c[0].opacity(0.85), c[1].opacity(0.60), c[2].opacity(0.70),
                c[1].opacity(0.55), Theme.deepWine.opacity(0.35), c[0].opacity(0.50),
                c[2].opacity(0.60), c[0].opacity(0.45), c[1].opacity(0.80),
            ]
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 1.5), value: band)
        .ignoresSafeArea()
    }
}

/// Accent-filled disc with a high-contrast symbol: deep wine on light accents, white on dark ones.
struct IconBadge: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Self.isLight(tint) ? Theme.deepWine : Color.white)
            .frame(width: 32, height: 32)
            .background(
                Circle().fill(LinearGradient(colors: [tint, tint.opacity(0.78)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
    }

    private static func isLight(_ color: Color) -> Bool {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return true }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent > 0.5
    }
}

struct MeterBar: View {
    let fraction: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.width * min(max(fraction, 0), 1), 5))
            }
        }
        .frame(height: 6)
    }
}

/// Min–max spread of a sensor group on a fixed 20–110 °C scale, with a dot at the average.
struct RangeBar: View {
    let low: Double
    let average: Double
    let high: Double
    private let scale = 20.0...110.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [temperatureColor(low), temperatureColor(high)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(x(high, w) - x(low, w), 8))
                    .offset(x: x(low, w))
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
                    .frame(width: 9, height: 9)
                    .offset(x: min(max(x(average, w) - 4.5, 0), w - 9))
            }
        }
        .frame(height: 9)
    }

    private func x(_ value: Double, _ width: CGFloat) -> CGFloat {
        let clamped = min(max(value, scale.lowerBound), scale.upperBound)
        return CGFloat((clamped - scale.lowerBound) / (scale.upperBound - scale.lowerBound)) * width
    }
}

/// 270° gauge for the hottest chip sensor, with a crimson tick where Apple Silicon starts throttling.
struct TemperatureRing: View {
    let value: Double
    var lineWidth: CGFloat = 16
    var showsThrottleMark = true
    private static let range = 30.0...105.0

    private static func fraction(_ celsius: Double) -> Double {
        min(max((celsius - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    var body: some View {
        let fraction = Self.fraction(value)
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            // Keep strokes and the tick inside the frame; drawingGroup crops anything outside it.
            let inset = lineWidth / 2 + 5
            ZStack {
                Circle()
                    .inset(by: inset)
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .inset(by: inset)
                    .trim(from: 0, to: 0.75 * fraction)
                    .stroke(
                        AngularGradient(colors: [Theme.champagne, Theme.champagne, Theme.rose, Theme.wine, Theme.crimson],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(135))
                if showsThrottleMark {
                    // A radial tick drawn at 12 o'clock, then rotated to the 95 °C point on the arc.
                    Capsule()
                        .fill(Theme.crimson)
                        .frame(width: 3, height: lineWidth + 8)
                        .offset(y: -(side / 2 - inset))
                        .rotationEffect(.degrees(135 + 270 * Self.fraction(95) + 90))
                }
            }
            .frame(width: side, height: side)
            // Rasterise on the GPU; the conic gradient is expensive to shade on the CPU.
            .drawingGroup()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // No implicit animation: readings move a degree at a time, and animating would re-render
        // the ring ~50 times per update.
    }
}

struct AppIcon: View {
    let path: String?
    private static var cache: [String: NSImage] = [:]

    var body: some View {
        if let path, let image = Self.icon(path) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .overlay(Image(systemName: "gearshape.fill").font(.system(size: 11)).foregroundStyle(.secondary))
        }
    }

    private static func icon(_ path: String) -> NSImage? {
        if let cached = cache[path] { return cached }
        // Background agents such as NotificationCenter ship no icon and would render as a blank tile.
        guard let info = Bundle(path: path)?.infoDictionary,
              info["CFBundleIconFile"] != nil || info["CFBundleIconName"] != nil || info["CFBundleIcons"] != nil
        else { return nil }
        // Rasterise once at row size (24 pt @2x) so scrolling never samples the 1024 px representations.
        let full = NSWorkspace.shared.icon(forFile: path)
        let size = NSSize(width: 24, height: 24)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 48, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return full }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        full.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        cache[path] = image
        return image
    }
}

/// Reports whether the hosting window is actually on screen (not closed, minimised or fully covered).
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) {}

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { onChange?(false); return }
            let names = [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    self?.report(closing: note.name == NSWindow.willCloseNotification)
                })
            }
            report(closing: false)
        }

        private func report(closing: Bool) {
            guard let window else { return }
            onChange?(!closing && window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible))
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

// MARK: - Main window

struct ContentView: View {
    @Environment(Monitor.self) private var monitor
    @State private var scrolling = false

    var body: some View {
        ScrollView {
            Dashboard()
                .padding(.horizontal, 24)
                .padding(.top, 34)
                .padding(.bottom, 20)
                // Content sliding under a still pointer would otherwise fire hover on every row and
                // move the charts' hover selection, re-rendering a whole chart mid-scroll.
                .allowsHitTesting(!scrolling)
        }
        .scrollIndicators(.never)
        // EMBER_SCROLL_ANCHOR=bottom opens scrolled down; used to capture README screenshots.
        .defaultScrollAnchor(ProcessInfo.processInfo.environment["EMBER_SCROLL_ANCHOR"] == "bottom" ? .bottom : .top)
        .onScrollPhaseChange { _, phase in
            scrolling = phase.isScrolling
            monitor.setScrolling(phase.isScrolling)
        }
        .frame(minWidth: 900, minHeight: 640)
        .containerBackground(for: .window) {
            AmbientBackground(band: HeatBand(monitor.chip?.maximum ?? 40))
        }
        .background(WindowVisibilityReader { monitor.setDashboardVisible($0) })
        .tint(Theme.wine)
    }
}

struct Dashboard: View {
    // No GlassEffectContainer here: it composites every panel into one glass layer, which
    // has to be re-sampled on every scroll frame. The panels never morph, so they don't need it.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header()
            HStack(alignment: .top, spacing: 16) {
                HeroTile().frame(width: 300)
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        FanTile()
                        PowerTile()
                    }
                    GridRow {
                        BatteryTile()
                        SystemTile()
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                TemperatureChart()
                PowerChart()
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 16) {
                SensorsPanel().frame(width: 330)
                UsagePanel()
            }
            Footer()
        }
    }
}

struct Header: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Ember")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.primary, .primary.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                Text("\(SystemStats.chipName) · live every 2 s")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            ThermalStatusBadge(state: monitor.thermalState, hottest: monitor.chip?.maximum)

            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            } label: {
                Label("Activity Monitor", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }
}

/// Header status: state icon in a tinted disc, a small label, and the plain-language state.
struct ThermalStatusBadge: View {
    let state: ProcessInfo.ThermalState
    let hottest: Double?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(state.color)
                .frame(width: 30, height: 30)
                .background(Circle().fill(state.color.opacity(0.18)))
                .overlay(Circle().strokeBorder(state.color.opacity(0.35), lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text("Thermal state")
                    .font(.system(size: 9.5, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(state.detail).font(.callout.weight(.semibold))
                    if let hottest {
                        Text(String(format: "%.0f°C", hottest))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.leading, 5).padding(.trailing, 16).padding(.vertical, 5)
        .glassEffect(.regular.tint(state.color.opacity(0.14)).interactive(), in: .capsule)
        .help("macOS thermal pressure: \(state.title). Apple Silicon throttles around 95–105 °C.")
    }
}

struct Footer: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Made with")
            Image(systemName: "heart.fill").foregroundStyle(.white)
            Text("by \(Credits.name)")
            Text("·").foregroundStyle(.tertiary)
            Link(destination: Credits.github) {
                Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            if let x = Credits.x {
                Text("·").foregroundStyle(.tertiary)
                Link("𝕏", destination: x)
            }
            Text("·").foregroundStyle(.tertiary)
            Text("Open source, MIT")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .tint(Theme.blush)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

struct HeroTile: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let chip = monitor.chip
        let hottest = chip?.maximum ?? 0
        GlassTile(tint: temperatureColor(hottest)) {
            VStack(spacing: 10) {
                HStack {
                    IconBadge(symbol: "cpu", tint: temperatureColor(hottest))
                    Text("Chip").font(.headline)
                    Spacer()
                    Text("\(chip?.readings.count ?? 0) sensors").font(.caption).foregroundStyle(.secondary)
                }
                ZStack {
                    TemperatureRing(value: hottest, lineWidth: 18)
                        .padding(14)
                    VStack(spacing: -2) {
                        Text(chip.map { String(format: "%.0f", $0.maximum) } ?? "—")
                            .font(.system(size: 58, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("°C hottest").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    }
                    VStack {
                        Spacer()
                        HStack {
                            Text("30°")
                            Spacer()
                            Text("105°")
                        }
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.horizontal, 44)
                    }
                }
                .frame(height: 210)
                HStack(spacing: 8) {
                    StatChip(label: "Average", value: chip.map { String(format: "%.0f°", $0.average) } ?? "—")
                    StatChip(label: "Coolest", value: chip.map { String(format: "%.0f°", $0.minimum) } ?? "—")
                    StatChip(label: "Throttle", value: "~95°")
                }
            }
        }
    }
}

struct StatChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

struct StatTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    let unit: String
    let caption: String
    var fraction: Double? = nil

    var body: some View {
        GlassTile {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    IconBadge(symbol: symbol, tint: tint)
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if !unit.isEmpty {
                        Text(unit).font(.title3.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let fraction {
                    MeterBar(fraction: fraction, colors: [Theme.wine, tint])
                }
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }
}

struct FanTile: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let fans = monitor.fans
        if fans.isEmpty {
            StatTile(title: "Fans", symbol: "fan", tint: Theme.blush, value: "—", unit: "", caption: "No fans reported")
        } else {
            let rpm = fans.map(\.rpm).reduce(0, +) / Double(fans.count)
            let fraction = fans.map(\.fraction).reduce(0, +) / Double(fans.count)
            StatTile(
                title: fans.count == 1 ? "Fan" : "Fans", symbol: "fan", tint: Theme.blush,
                value: rpm.formatted(.number.precision(.fractionLength(0))), unit: "rpm",
                caption: String(format: "%d fan%@ · %.0f%% of max", fans.count, fans.count == 1 ? "" : "s", fraction * 100),
                fraction: fraction
            )
        }
    }
}

struct PowerTile: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let watts = monitor.power?.systemWatts
        StatTile(
            title: "Power draw", symbol: "bolt.fill", tint: Theme.champagne,
            value: watts.map { String(format: "%.1f", $0) } ?? "—", unit: "W",
            caption: monitor.power.map { $0.onAdapter ? "From power adapter" : "From battery" } ?? "No battery telemetry",
            fraction: watts.map { $0 / 100 }
        )
    }
}

struct BatteryTile: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        if let p = monitor.power {
            StatTile(
                title: "Battery", symbol: Self.symbol(p), tint: p.batteryPercent > 20 ? Theme.rose : Theme.crimson,
                value: "\(p.batteryPercent)", unit: "%",
                caption: Self.caption(p), fraction: Double(p.batteryPercent) / 100
            )
        } else {
            StatTile(title: "Battery", symbol: "powerplug", tint: Theme.rose, value: "—", unit: "", caption: "No battery")
        }
    }

    private static func symbol(_ p: PowerInfo) -> String {
        if p.isCharging { return "battery.100percent.bolt" }
        return p.batteryPercent > 60 ? "battery.75percent" : p.batteryPercent > 25 ? "battery.50percent" : "battery.25percent"
    }

    private static func caption(_ p: PowerInfo) -> String {
        var caption = p.isCharging ? "Charging" : p.onAdapter ? "On adapter" : "On battery"
        if let m = p.minutesRemaining { caption += " · \(m / 60):" + String(format: "%02d", m % 60) + " left" }
        if let cycles = p.cycleCount { caption += " · \(cycles) cycles" }
        return caption
    }
}

struct SystemTile: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        StatTile(
            title: "Thermal state", symbol: "gauge.with.dots.needle.33percent", tint: monitor.thermalState.color,
            value: monitor.thermalState.title, unit: "",
            caption: String(format: "Load %.1f · Swap %.1f GB", monitor.loadAverage, monitor.swapUsedGB)
        )
    }
}

// MARK: - Charts

/// Minute labels once there's enough history; seconds before that so labels aren't all identical.
func timeAxis(_ history: [HistorySample]) -> some AxisContent {
    let span = (history.last?.date ?? .now).timeIntervalSince(history.first?.date ?? .now)
    let format: Date.FormatStyle = span < 180 ? .dateTime.minute().second() : .dateTime.hour().minute()
    return AxisMarks(values: .automatic(desiredCount: 4)) { _ in
        AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
        AxisValueLabel(format: format)
    }
}

func nearestSample(to date: Date?, in history: [HistorySample]) -> HistorySample? {
    guard let date else { return nil }
    return history.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
}

struct ChartHeader: View {
    let title: String
    let symbol: String
    let tint: Color
    let readout: String?

    var body: some View {
        HStack(spacing: 9) {
            IconBadge(symbol: symbol, tint: tint)
            Text(title).font(.headline)
            Spacer()
            Text(readout ?? "Last 10 minutes")
                .font(.caption.weight(readout == nil ? .regular : .semibold))
                .monospacedDigit()
                .foregroundStyle(readout == nil ? .secondary : .primary)
        }
    }
}

struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TemperatureChart: View {
    @Environment(Monitor.self) private var monitor
    @State private var hovered: Date?

    var body: some View {
        let history = monitor.history
        let selected = nearestSample(to: hovered, in: history)
        let floor = monitor.temperatureDomain.lowerBound
        GlassTile {
            VStack(alignment: .leading, spacing: 12) {
                ChartHeader(
                    title: "Chip temperature", symbol: "thermometer.medium", tint: Theme.rose,
                    readout: selected.map { String(format: "%@ · %.1f° hottest · %.1f° avg", $0.date.formatted(date: .omitted, time: .standard), $0.chipMax, $0.chipAverage) }
                )
                Chart {
                    ForEach(history) { s in
                        AreaMark(x: .value("Time", s.date), yStart: .value("Floor", floor), yEnd: .value("°C", s.chipMax))
                            .foregroundStyle(LinearGradient(colors: [Theme.rose.opacity(0.45), Theme.rose.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", s.date), y: .value("°C", s.chipMax), series: .value("Series", "Hottest"))
                            .foregroundStyle(LinearGradient(colors: [Theme.champagne, Theme.rose, Theme.crimson], startPoint: .bottom, endPoint: .top))
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", s.date), y: .value("°C", s.chipAverage), series: .value("Series", "Average"))
                            .foregroundStyle(Theme.blush.opacity(0.9))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3]))
                            .interpolationMethod(.monotone)
                    }
                    if let selected {
                        RuleMark(x: .value("Time", selected.date)).foregroundStyle(Color.primary.opacity(0.25))
                        PointMark(x: .value("Time", selected.date), y: .value("°C", selected.chipMax))
                            .foregroundStyle(Theme.rose).symbolSize(70)
                    }
                }
                .chartYScale(domain: monitor.temperatureDomain)
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel { Text("\(v.as(Double.self) ?? 0, specifier: "%.0f")°") }
                    }
                }
                .chartXAxis { timeAxis(history) }
                .chartXSelection(value: $hovered)
                .frame(height: 160)
                .overlay { if history.count < 2 { Text("Collecting…").font(.caption).foregroundStyle(.secondary) } }
                HStack(spacing: 14) {
                    LegendDot(color: Theme.rose, label: "Hottest sensor")
                    LegendDot(color: Theme.blush, label: "Average")
                }
            }
        }
    }
}

struct PowerChart: View {
    @Environment(Monitor.self) private var monitor
    @State private var hovered: Date?

    var body: some View {
        let samples = monitor.history.filter { $0.watts != nil }
        let selected = nearestSample(to: hovered, in: samples)
        GlassTile {
            VStack(alignment: .leading, spacing: 12) {
                ChartHeader(
                    title: "System power", symbol: "bolt.fill", tint: Theme.champagne,
                    readout: selected.map { String(format: "%@ · %.1f W", $0.date.formatted(date: .omitted, time: .standard), $0.watts ?? 0) }
                )
                Chart {
                    ForEach(samples) { s in
                        AreaMark(x: .value("Time", s.date), y: .value("W", s.watts ?? 0))
                            .foregroundStyle(LinearGradient(colors: [Theme.champagne.opacity(0.45), Theme.champagne.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", s.date), y: .value("W", s.watts ?? 0))
                            .foregroundStyle(LinearGradient(colors: [Theme.champagne, Theme.rose], startPoint: .bottom, endPoint: .top))
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                    if let selected {
                        RuleMark(x: .value("Time", selected.date)).foregroundStyle(Color.primary.opacity(0.25))
                        PointMark(x: .value("Time", selected.date), y: .value("W", selected.watts ?? 0))
                            .foregroundStyle(Theme.champagne).symbolSize(70)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel { Text("\(v.as(Double.self) ?? 0, specifier: "%.0f") W") }
                    }
                }
                .chartXAxis { timeAxis(samples) }
                .chartXSelection(value: $hovered)
                .frame(height: 160)
                .overlay {
                    if samples.count < 2 {
                        Text(monitor.power == nil ? "No power telemetry on this Mac" : "Collecting…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 14) {
                    LegendDot(color: Theme.champagne, label: "Whole-system draw")
                    Spacer()
                    if let health = monitor.power?.healthPercent {
                        Text("Battery health \(health)%").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Sensors

struct SensorsPanel: View {
    @Environment(Monitor.self) private var monitor
    @State private var expanded: Set<SensorKind> = []

    var body: some View {
        GlassTile {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    IconBadge(symbol: "sensor.fill", tint: Theme.blush)
                    Text("Sensors").font(.headline)
                    Spacer()
                    Text("\(monitor.readings.count) readings").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(monitor.groups) { group in
                    SensorGroupRow(group: group, isExpanded: expanded.contains(group.kind)) {
                        withAnimation(.snappy(duration: 0.25)) {
                            if expanded.contains(group.kind) { expanded.remove(group.kind) } else { expanded.insert(group.kind) }
                        }
                    }
                }
                if monitor.groups.isEmpty {
                    Text("No temperature sensors found.").foregroundStyle(.secondary)
                }
                if !monitor.fans.isEmpty {
                    Divider().opacity(0.5)
                    ForEach(monitor.fans) { fan in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "fan").foregroundStyle(Theme.blush).frame(width: 18)
                                Text(monitor.fans.count == 1 ? "Fan" : (fan.id == 0 ? "Left fan" : fan.id == 1 ? "Right fan" : "Fan \(fan.id + 1)"))
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(fan.rpm)) / \(Int(fan.maxRPM)) rpm").font(.callout).monospacedDigit()
                            }
                            MeterBar(fraction: fan.fraction, colors: [Theme.wine, Theme.blush])
                        }
                    }
                }
                Text("Apple Silicon throttles around 95–105 °C. Anything under ~85 °C is normal under load.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SensorGroupRow: View {
    let group: SensorGroup
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: group.kind.symbol)
                        .foregroundStyle(temperatureColor(group.maximum))
                        .frame(width: 18)
                    Text(group.kind.title).fontWeight(.medium)
                    if group.readings.count > 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    Spacer()
                    Text(group.readings.count > 1
                         ? String(format: "%.0f° avg · %.0f° max", group.average, group.maximum)
                         : String(format: "%.1f°", group.maximum))
                        .font(.callout).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            RangeBar(low: group.minimum, average: group.average, high: group.maximum)

            if isExpanded {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 4) {
                    ForEach(group.readings) { r in
                        HStack {
                            Text(r.name.replacingOccurrences(of: "PMU ", with: "")).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(String(format: "%.1f°", r.celsius)).monospacedDigit()
                                .foregroundStyle(r.celsius < 75 ? Color.primary : Theme.crimson)
                        }
                        .font(.caption)
                    }
                }
                .padding(.leading, 26)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(hovering ? 0.05 : 0)))
        .padding(-8)
        .onHover { hovering = $0 }
    }
}

// MARK: - Power users

struct UsagePanel: View {
    @Environment(Monitor.self) private var monitor
    @State private var mode = Mode.apps

    enum Mode: String, CaseIterable { case apps = "Apps", processes = "Processes" }

    var body: some View {
        let rows = Array((mode == .apps ? monitor.appRows : monitor.processRows).prefix(14))
        let maxPower = max(rows.map(\.power).max() ?? 1, 1)
        GlassTile {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    IconBadge(symbol: "flame.fill", tint: Theme.rose)
                    Text("What's using power").font(.headline)
                    Spacer()
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.bottom, 4)
                HStack(spacing: 10) {
                    Text(mode == .apps ? "App" : "Process").frame(maxWidth: .infinity, alignment: .leading)
                    Text("CPU").frame(width: 52, alignment: .trailing)
                    Text("Memory").frame(width: 66, alignment: .trailing)
                    Text("Energy impact").frame(width: 160, alignment: .leading)
                }
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8)

                if rows.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Sampling processes…").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    UsageRowView(row: row, rank: index, maxPower: maxPower)
                }
                Text("Energy impact is macOS's relative power estimate, the same number Activity Monitor shows. Updates every \(ProcessStream.interval) s.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }
}

struct UsageRowView: View {
    let row: UsageRow
    let rank: Int
    let maxPower: Double
    @State private var hovering = false

    var body: some View {
        let heat: [Color] = rank == 0 ? [Theme.rose, Theme.crimson] : [Theme.wine, Theme.rose]
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                AppIcon(path: row.iconPath).frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name).lineLimit(1).truncationMode(.middle).fontWeight(rank < 3 ? .semibold : .regular)
                    if let subtitle = row.subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.0f%%", row.cpu)).monospacedDigit().frame(width: 52, alignment: .trailing)
            Text(formatMemory(row.memoryMB)).monospacedDigit().foregroundStyle(.secondary).frame(width: 66, alignment: .trailing)
            HStack(spacing: 8) {
                MeterBar(fraction: row.power / maxPower, colors: heat)
                Text(String(format: "%.1f", row.power)).monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            .frame(width: 160)
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .frame(minHeight: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .onHover { hovering = $0 }
    }
}

// MARK: - Menu bar

struct MenuBarLabel: View {
    let monitor: Monitor

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "thermometer.medium")
            Text(monitor.menuTemperature.map { "\($0)°" } ?? "--°").monospacedDigit()
        }
    }
}

struct MenuBarPanel: View {
    @Environment(Monitor.self) private var monitor
    @Environment(\.openWindow) private var openWindow
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        let hottest = monitor.chip?.maximum ?? 0
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        TemperatureRing(value: hottest, lineWidth: 9, showsThrottleMark: false)
                            .padding(5)
                        VStack(spacing: -2) {
                            Text(String(format: "%.0f°", hottest))
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("chip").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 96, height: 96)

                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text(monitor.thermalState.detail).fontWeight(.semibold).foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: monitor.thermalState.symbol).foregroundStyle(monitor.thermalState.color)
                        }
                        if !monitor.fans.isEmpty {
                            Label(monitor.fans.map { "\(Int($0.rpm))" }.joined(separator: " · ") + " rpm", systemImage: "fan")
                        }
                        if let watts = monitor.power?.systemWatts {
                            Label(String(format: "%.1f W", watts), systemImage: "bolt.fill")
                        }
                        if let p = monitor.power {
                            Label("\(p.batteryPercent)%" + (p.isCharging ? " · charging" : ""), systemImage: "battery.75percent")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Top energy use").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if monitor.processes.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Sampling…").foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                    ForEach(monitor.appRows.prefix(5)) { row in
                        HStack(spacing: 8) {
                            AppIcon(path: row.iconPath).frame(width: 18, height: 18)
                            Text(row.name).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.0f%%", row.cpu)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(Theme.burgundy.opacity(0.14)), in: .rect(cornerRadius: 16))

                Toggle(isOn: $opensAtLogin) {
                    Text("Open at login (keeps the widget fresh)").font(.callout)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: opensAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        opensAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

                HStack {
                    Button {
                        openWindow(id: "main")
                        NSApp.activate()
                    } label: {
                        Label("Open Ember", systemImage: "macwindow")
                    }
                    .buttonStyle(.glassProminent)
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                        .buttonStyle(.glass)
                }
            }
        }
        .padding(14)
        .frame(width: 330)
        .tint(Theme.wine)
        // onAppear fires when SwiftUI builds the panel at launch, not when it opens, so track the
        // panel window's real visibility instead.
        .background(WindowVisibilityReader { monitor.setMenuOpen($0) })
    }
}
