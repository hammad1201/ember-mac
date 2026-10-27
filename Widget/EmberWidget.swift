import SwiftUI
import WidgetKit

// The widget never reads sensors itself (it runs sandboxed). Ember writes a snapshot about once
// a minute and the widget redraws from it every 5 minutes, so it costs next to nothing.

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let snapshot = Snapshot.load()
        completion(Entry(date: .now, snapshot: snapshot ?? (context.isPreview ? .placeholder : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: .now, snapshot: Snapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(5 * 60))))
    }
}

@main
struct EmberWidgets: WidgetBundle {
    var body: some Widget {
        EmberWidget()
    }
}

struct EmberWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EmberWidget", provider: Provider()) { entry in
            EmberWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Theme.burgundy, Theme.deepWine], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Ember")
        .description("Chip temperature, fans and power at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Views

struct EmberWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemMedium: MediumView(snapshot: snapshot)
            default: SmallView(snapshot: snapshot)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "thermometer.medium").font(.title2).foregroundStyle(Theme.champagne)
                Text("Open Ember to start monitoring")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

private struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.9)
            .foregroundStyle(.white.opacity(0.6))
    }
}

/// Same 270° gauge as the app, drawn without a GPU pass so it archives cleanly for the widget.
private struct Gauge: View {
    let value: Double
    var lineWidth: CGFloat = 9

    var body: some View {
        let fraction = min(max((value - 30) / 75, 0), 1)
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: 0.75 * fraction)
                .stroke(
                    AngularGradient(colors: [Theme.champagne, Theme.champagne, Theme.rose, Theme.wine, Theme.crimson],
                                    center: .center, startAngle: .degrees(0), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .widgetAccentable()
            Text(String(format: "%.0f°", value))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}

private struct UpdatedLabel: View {
    let date: Date

    var body: some View {
        // Ember writes every minute; anything much older means the app isn't running.
        // A clock time, not a relative one: `.relative` ticks every second ("1 min, 4 sec").
        if Date.now.timeIntervalSince(date) > 15 * 60 {
            Text("Ember isn't running").font(.system(size: 9)).foregroundStyle(Theme.blush)
        } else {
            Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
        }
    }
}

private struct SmallView: View {
    let snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Eyebrow(text: "Ember")
                Spacer()
                Image(systemName: snapshot.state.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(snapshot.state.color)
            }
            Gauge(value: snapshot.chipMax)
                .frame(maxWidth: .infinity)
            Text(snapshot.state.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            UpdatedLabel(date: snapshot.date)
        }
    }
}

private struct MediumView: View {
    let snapshot: Snapshot

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                Gauge(value: snapshot.chipMax, lineWidth: 10)
                Text("Chip · hottest").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: 104)

            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(snapshot.state.detail).foregroundStyle(.white)
                } icon: {
                    Image(systemName: snapshot.state.symbol).foregroundStyle(snapshot.state.color)
                }
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                HStack(alignment: .top, spacing: 12) {
                    Stat(label: "Fans", value: snapshot.fanRPM.map { Int($0).formatted() } ?? "—", unit: "rpm")
                    Stat(label: "Power", value: snapshot.watts.map { String(format: "%.1f", $0) } ?? "—", unit: "W")
                    Stat(label: "Battery", value: snapshot.batteryPercent.map { "\($0)" } ?? "—", unit: "%")
                }

                Sparkline(values: snapshot.history)
                    .frame(height: 22)

                HStack {
                    Text("Last 30 min").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    UpdatedLabel(date: snapshot.date)
                }
            }
        }
    }
}

private struct Stat: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Eyebrow(text: label)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(unit).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
        }
    }
}

/// Chip temperature over the last ~30 minutes.
private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            if values.count > 1, let lo = values.min(), let hi = values.max() {
                let span = max(hi - lo, 4)
                let points = values.enumerated().map { i, v in
                    CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(values.count - 1),
                            y: 2 + (geo.size.height - 4) * (1 - CGFloat((v - lo) / span)))
                }
                let line = Path { curve(through: points, in: &$0) }
                let area = Path { p in
                    curve(through: points, in: &p)
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.closeSubpath()
                }
                area.fill(LinearGradient(colors: [Theme.rose.opacity(0.28), Theme.rose.opacity(0)], startPoint: .top, endPoint: .bottom))
                line
                    .stroke(LinearGradient(colors: [Theme.champagne, Theme.rose], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .widgetAccentable()
            }
        }
    }

    /// Curves through the midpoints so a handful of samples doesn't look jagged.
    private func curve(through points: [CGPoint], in p: inout Path) {
        p.move(to: points[0])
        for i in 1..<points.count {
            let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
            p.addQuadCurve(to: mid, control: points[i - 1])
        }
        p.addLine(to: points[points.count - 1])
    }
}
