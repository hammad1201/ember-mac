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
        if Date.now.timeIntervalSince(date) > 15 * 60 {
            Text("Ember isn't running").font(.system(size: 9)).foregroundStyle(Theme.blush)
        } else {
            Text(date, style: .relative).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
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
            HStack {
                Text(snapshot.state.detail).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                Spacer()
            }
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
            .frame(width: 112)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label {
                        Text(snapshot.state.detail).foregroundStyle(.white)
                    } icon: {
                        Image(systemName: snapshot.state.symbol).foregroundStyle(snapshot.state.color)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    UpdatedLabel(date: snapshot.date)
                }
                HStack(spacing: 14) {
                    Stat(label: "Fans", value: snapshot.fanRPM.map { "\(Int($0))" } ?? "—", unit: "rpm")
                    Stat(label: "Power", value: snapshot.watts.map { String(format: "%.1f", $0) } ?? "—", unit: "W")
                    Stat(label: "Battery", value: snapshot.batteryPercent.map { "\($0)" } ?? "—", unit: "%")
                }
                Sparkline(values: snapshot.history)
                    .frame(height: 26)
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
                            y: geo.size.height * (1 - CGFloat((v - lo) / span)))
                }
                Path { p in p.addLines(points) }
                    .stroke(LinearGradient(colors: [Theme.champagne, Theme.rose], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .widgetAccentable()
            }
        }
    }
}
