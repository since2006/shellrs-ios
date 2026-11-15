import Charts
import SwiftUI
import UIKit

/// How full or busy something is, as the desktop's 系统监控 colours it:
/// green, orange from 70%, red from 90%.
enum Severity {
    case normal
    case high
    case critical

    init(percent: Double) {
        self = percent >= 90 ? .critical : percent >= 70 ? .high : .normal
    }

    var color: Color {
        switch self {
        case .normal: .green
        case .high: .orange
        case .critical: .red
        }
    }
}

/// The track a share fills, the same under every meter, ring and core.
private let track = Color.secondary.opacity(0.16)

/// A share as a ring, as the desktop's 系统监控 leads with the CPU and the
/// memory: the arc coloured by how full it is, the figure inside.
struct RingGauge: View {
    /// 0 to 100; `nil` until known.
    let percent: Double?
    var diameter: CGFloat = 56
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            RingArc(percent: percent, lineWidth: lineWidth)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: percent.map { String(Int($0.rounded())) } ?? "—")
                    .font(.system(size: diameter * 0.3, weight: .semibold, design: .rounded))
                    // Digits roll rather than two figures crossfading.
                    .contentTransition(.numericText(value: percent ?? 0))
                    .animation(.snappy, value: percent.map { Int($0.rounded()) })
                if percent != nil {
                    Text(verbatim: "%")
                        .font(.system(size: diameter * 0.15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, lineWidth + 3)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(verbatim: percent.map(StatusFormat.percent) ?? "—"))
    }
}

/// A share's track and the arc of it filled, from the top, in the colour
/// of how full it is.
struct RingArc: View {
    /// 0 to 100; `nil` until known, an empty track.
    let percent: Double?
    let lineWidth: CGFloat

    var body: some View {
        let share = min(max((percent ?? 0) / 100, 0), 1)
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: share)
                .stroke(
                    Severity(percent: percent ?? 0).color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: share)
        }
        .accessibilityHidden(true)
    }
}

/// A ring with its name under it, one of the figures a host's card leads
/// with; a red one is marked as well, not by its colour alone. Always as
/// wide as its ring, so the rings of every card line up.
struct RingTile: View {
    let title: String
    let percent: Double?
    var diameter: CGFloat = 56
    /// Tapping it shows something else in its place: say so.
    var swaps = false

    var body: some View {
        VStack(spacing: 6) {
            RingGauge(percent: percent, diameter: diameter)
            TileLabel(
                title: Text(verbatim: title), critical: Severity(percent: percent ?? 0) == .critical,
                swaps: swaps)
                .frame(maxWidth: diameter + 8)
        }
        .frame(width: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: percent.map(StatusFormat.percent) ?? "—"))
    }
}

/// The load over the last one, five and fifteen minutes as three rings
/// one inside the other, the last minute outermost, each the load's share
/// of the cores: as big as a `RingTile`'s ring, the figures only for
/// VoiceOver.
struct LoadTile: View {
    let load: LoadAverage?
    /// The host's cores; 0 when unknown, and the rings stay empty.
    let cores: Int
    var diameter: CGFloat = 56
    var swaps = false

    private static let lineWidth: CGFloat = 5
    /// Between one ring and the next inside it.
    private static let gap: CGFloat = 2

    var body: some View {
        let values = load.map { [$0.one, $0.five, $0.fifteen] }
        VStack(spacing: 6) {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let size = diameter - 2 * CGFloat(index) * (Self.lineWidth + Self.gap)
                    RingArc(percent: values.flatMap { share($0[index]) }, lineWidth: Self.lineWidth)
                        .frame(width: size, height: size)
                }
            }
            .frame(width: diameter, height: diameter)
            TileLabel(
                title: Text("负载"),
                critical: Severity(percent: values.flatMap { share($0[0]) } ?? 0) == .critical,
                swaps: swaps)
                .frame(maxWidth: diameter + 8)
        }
        .frame(width: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("负载"))
        .accessibilityValue(
            values.map {
                Text(
                    "1 分钟 \(StatusFormat.load($0[0]))，5 分钟 \(StatusFormat.load($0[1]))，15 分钟 \(StatusFormat.load($0[2]))"
                )
            } ?? Text(verbatim: "—"))
    }

    /// The load as a share of the cores: 100% when each has a task.
    private func share(_ load: Double) -> Double? {
        cores > 0 ? load / Double(cores) * 100 : nil
    }
}

/// The name under a tile: a red one marked, and one that swaps for
/// another on a tap with a mark of that.
private struct TileLabel: View {
    let title: Text
    let critical: Bool
    let swaps: Bool

    var body: some View {
        HStack(spacing: 3) {
            if critical {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .imageScale(.small)
            }
            title
                .lineLimit(1)
                .truncationMode(.middle)
            if swaps {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Two faces of a tile, the back's turned to like a card's: `angle` 0
/// shows the front, 180 the back, and between them it turns about its
/// upright. Where motion is reduced, the one fades into the other.
struct Flip<Front: View, Back: View>: View, Animatable {
    var angle: Double
    let front: Front
    let back: Back

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(showsBack: Bool, @ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back) {
        angle = showsBack ? 180 : 0
        self.front = front()
        self.back = back()
    }

    // Not the main actor's: a plain value of a value, as the animation
    // reads and writes it.
    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        // Past the edge, the back faces us.
        let backShows = angle >= 90
        ZStack {
            front
                .opacity(reduceMotion ? 1 - angle / 180 : backShows ? 0 : 1)
                .accessibilityHidden(backShows)
            back
                .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                .opacity(reduceMotion ? angle / 180 : backShows ? 1 : 0)
                .accessibilityHidden(!backShows)
        }
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
    }
}

/// A tile that is a button: dimmed while pressed, nothing else, so it
/// looks the same as the tiles beside it.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A share as a thin bar, filled in the colour of how full it is.
struct ThinMeter: View {
    /// 0 to 100; `nil` until known.
    let percent: Double?
    var height: CGFloat = 6

    var body: some View {
        let share = min(max((percent ?? 0) / 100, 0), 1)
        Capsule()
            .fill(track)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Severity(percent: percent ?? 0).color)
                        // A sliver still shows as a dot.
                        .frame(width: share > 0 ? max(height, proxy.size.width * share) : 0)
                }
            }
            .frame(height: height)
            .animation(.easeInOut(duration: 0.5), value: share)
            .accessibilityHidden(true)
    }
}

/// A figure as a tile: its name small above, the value below, and a mark
/// when it is worth a second look.
struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var note = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(verbatim: value)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if note {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Each core's load as a thin column filled from the bottom, as the
/// desktop draws them: as many to a row as fit, the rows evenly filled, so
/// a hundred cores take a few rows. A tap on one says which and how busy.
struct CoreBars: View {
    /// 0 to 100 each.
    let cores: [Double]
    @State private var width: CGFloat = 0
    @State private var selected: Int?

    private nonisolated static let gap: CGFloat = 3
    private nonisolated static let rowGap: CGFloat = 6
    private nonisolated static let height: CGFloat = 30
    private nonisolated static let narrowest: CGFloat = 6
    private nonisolated static let widest: CGFloat = 36

    /// How the columns lie in `width`.
    struct Geometry: Equatable {
        var bar: CGFloat
        var perRow: Int
        var rows: Int

        var height: CGFloat {
            CGFloat(rows) * CoreBars.height + CGFloat(max(rows - 1, 0)) * CoreBars.rowGap
        }
    }

    static func geometry(width: CGFloat, count: Int) -> Geometry {
        guard count > 0, width > 0 else {
            return Geometry(bar: narrowest, perRow: max(count, 1), rows: 1)
        }
        let fitting = max(1, Int((width + gap) / (narrowest + gap)))
        // 100 cores at 41 a row are rows of 34, not 41, 41 and 18.
        let rows = (count + fitting - 1) / fitting
        let perRow = (count + rows - 1) / rows
        let bar = min(widest, (width + gap) / CGFloat(perRow) - gap)
        return Geometry(bar: max(bar, 1), perRow: perRow, rows: rows)
    }

    var body: some View {
        let geometry = Self.geometry(width: width, count: cores.count)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("每个核")
                Spacer(minLength: 8)
                Text(verbatim: caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.subheadline)
            Canvas { context, _ in
                for (index, load) in cores.enumerated() {
                    let column = index % geometry.perRow
                    let row = index / geometry.perRow
                    let frame = CGRect(
                        x: CGFloat(column) * (geometry.bar + Self.gap),
                        y: CGFloat(row) * (Self.height + Self.rowGap),
                        width: geometry.bar, height: Self.height)
                    let radius = min(2, geometry.bar / 2)
                    let color = Severity(percent: load).color
                    let faded = selected.map { $0 != index } ?? false
                    context.opacity = faded ? 0.3 : 1
                    context.fill(
                        Path(roundedRect: frame, cornerRadius: radius), with: .color(color.opacity(0.2)))
                    let filled = frame.height * min(max(load / 100, 0), 1)
                    if filled > 0 {
                        let bar = CGRect(
                            x: frame.minX, y: frame.maxY - filled, width: frame.width, height: filled)
                        context.fill(Path(roundedRect: bar, cornerRadius: radius), with: .color(color))
                    }
                }
            }
            .frame(height: geometry.height)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let index = Self.index(at: location, in: geometry, count: cores.count)
                selected = index == selected ? nil : index
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("每个核"))
        .accessibilityValue(Text(verbatim: summary))
    }

    static func index(at point: CGPoint, in geometry: Geometry, count: Int) -> Int? {
        let column = Int(point.x / (geometry.bar + gap))
        let row = Int(point.y / (height + rowGap))
        let index = row * geometry.perRow + column
        guard point.x >= 0, point.y >= 0, column < geometry.perRow, index < count else {
            return nil
        }
        return index
    }

    /// The core tapped, or the busiest.
    private var caption: String {
        if let selected, cores.indices.contains(selected) {
            String(localized: "核 \(String(selected)) · \(StatusFormat.percent(cores[selected]))")
        } else {
            summary
        }
    }

    /// 「最忙 核 5 · 98.0%」.
    private var summary: String {
        guard let busiest = cores.indices.max(by: { cores[$0] < cores[$1] }) else {
            return ""
        }
        return String(
            localized: "最忙 核 \(String(busiest)) · \(StatusFormat.percent(cores[busiest]))")
    }
}

/// Figures as 状态 shows them.
enum StatusFormat {
    /// 「43.3%」.
    static func percent(_ percent: Double) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(1)))
    }

    /// Memory and network in powers of 1024, as the desktop shows them.
    static func bytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }

    /// 「5.4 KB/s」.
    static func rate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else {
            return "—"
        }
        return bytes(UInt64(max(bytesPerSecond, 0).rounded())) + "/s"
    }

    /// The units of `compactRate`.
    static let rateUnits = ["B/s", "K/s", "M/s", "G/s", "T/s"]

    /// 「900」「B/s」, 「2」「K/s」, 「10.7」「M/s」: a rate in powers of 1024
    /// as `rate`, in at most four characters, its unit apart to be shown
    /// smaller. Whole bytes; one decimal under 100, none from it.
    static func compactRate(_ bytesPerSecond: Double?) -> (number: String, unit: String) {
        guard let bytesPerSecond else {
            return ("—", rateUnits[0])
        }
        var value = max(bytesPerSecond, 0)
        var unit = 0
        // 999.5 rounds to 1000, a fifth character.
        while value >= 999.5, unit < rateUnits.count - 1 {
            value /= 1024
            unit += 1
        }
        let decimals = unit > 0 && value < 99.95 ? 0...1 : 0...0
        return (value.formatted(.number.precision(.fractionLength(decimals))), rateUnits[unit])
    }


    /// Disks as the Files app sizes them.
    static func size(_ bytes: UInt64) -> String {
        Format.size(bytes)
    }

    /// 「62 天 3 小时」.
    static func uptime(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int64(seconds)).formatted(
            .units(
                allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    /// 「12d 6h」「15h 8m」「8m」: an uptime short enough for a card's line,
    /// whole, in its two biggest units, the second left out when 0.
    static func shortUptime(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(seconds, 0)) / 60
        let days = minutes / (24 * 60)
        let hours = minutes / 60 % 24
        let rest = minutes % 60
        func pair(_ big: Int, _ bigUnit: String, _ small: Int, _ smallUnit: String) -> String {
            small > 0 ? "\(big)\(bigUnit) \(small)\(smallUnit)" : "\(big)\(bigUnit)"
        }
        if days > 0 {
            return pair(days, "d", hours, "h")
        }
        if hours > 0 {
            return pair(hours, "h", rest, "m")
        }
        return "\(rest)m"
    }

    /// 「0.20」: a load average, as `uptime` gives it.
    static func load(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }
}

extension Color {
    /// The two series of a network chart: the reference palette's first two
    /// categorical slots, stepped for each mode.
    static let received = Color(light: 0x2A78D6, dark: 0x3987E5)
    static let transmitted = Color(light: 0xEB6834, dark: 0xD95926)

    init(light: UInt32, dark: UInt32) {
        self.init(
            uiColor: UIColor { traits in
                let rgb = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: CGFloat((rgb >> 16) & 0xff) / 255,
                    green: CGFloat((rgb >> 8) & 0xff) / 255,
                    blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
            })
    }
}

/// A share as a row of a meter list: its name, a bar coloured by how full
/// it is, and the figure.
struct MeterRow: View {
    let title: String
    /// 0 to 100; `nil` until known.
    let percent: Double?
    /// What goes after the percentage: 「3.1 GB / 9.2 GB」.
    var detail: String?

    var body: some View {
        let severity = Severity(percent: percent ?? 0)
        VStack(alignment: .leading, spacing: 4) {
            // The detail beside the percentage where there is room, under
            // the title where a long mount point leaves none.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    titleText
                    Spacer(minLength: 8)
                    value(severity)
                    detailText
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        titleText
                        Spacer(minLength: 8)
                        value(severity)
                    }
                    detailText
                        .font(.footnote)
                }
            }
            ThinMeter(percent: percent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(
            Text(verbatim: [percent.map(StatusFormat.percent) ?? "—", detail ?? ""].joined(separator: " ")))
    }

    private var titleText: some View {
        Text(title)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func value(_ severity: Severity) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if severity == .critical {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(severity.color)
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            Text(percent.map(StatusFormat.percent) ?? "—")
                .monospacedDigit()
        }
        .fixedSize()
    }

    @ViewBuilder
    private var detailText: some View {
        if let detail {
            Text(detail)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// A host's last minutes as lines over time, one per series on one axis;
/// drag across to read a moment.
struct HistoryChart: View {
    struct Series {
        let name: String
        let color: Color
        let value: (HostMonitor.Point) -> Double?
    }

    let points: [HostMonitor.Point]
    let series: [Series]
    /// A percentage's 0 to 100; `nil` from 0 to what the data reach.
    var percent = false
    let format: (Double) -> String
    @State private var selected: Date?

    var body: some View {
        Chart {
            ForEach(series.indices, id: \.self) { index in
                let series = series[index]
                ForEach(points) { point in
                    if let value = series.value(point) {
                        if self.series.count == 1 {
                            AreaMark(x: .value("时间", point.at), y: .value(series.name, value))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [series.color.opacity(0.28), series.color.opacity(0.02)],
                                        startPoint: .top, endPoint: .bottom)
                                )
                                .interpolationMethod(.monotone)
                        }
                        LineMark(
                            x: .value("时间", point.at), y: .value(series.name, value),
                            series: .value("系列", series.name)
                        )
                        .foregroundStyle(by: .value("系列", series.name))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                    }
                }
            }
            if let point = selectedPoint {
                RuleMark(x: .value("时间", point.at))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top, spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        tooltip(point)
                    }
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
        .chartLegend(series.count > 1 ? .visible : .hidden)
        .chartLegend(position: .top, alignment: .leading)
        .chartXAxis(.hidden)
        .chartXSelection(value: $selected)
        .chartYScale(domain: percent ? 0...100 : 0...max(peak, 1))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.25))
                AxisValueLabel {
                    if let value = value.as(Double.self) {
                        // 0%, 50%, 100%: the axis's steps are round.
                        Text(
                            percent
                                ? (value / 100).formatted(.percent.precision(.fractionLength(0)))
                                : format(value))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 120)
        .accessibilityLabel(Text(verbatim: series.map(\.name).joined(separator: ", ")))
        .padding(.vertical, 4)
    }

    /// The highest value of any series, with room above it.
    private var peak: Double {
        let values = points.flatMap { point in series.compactMap { $0.value(point) } }
        return (values.max() ?? 0) * 1.15
    }

    private var selectedPoint: HostMonitor.Point? {
        guard let selected else { return nil }
        return points.min {
            abs($0.at.timeIntervalSince(selected)) < abs($1.at.timeIntervalSince(selected))
        }
    }

    private func tooltip(_ point: HostMonitor.Point) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.at.formatted(date: .omitted, time: .standard))
                .foregroundStyle(.secondary)
            ForEach(series.indices, id: \.self) { index in
                let series = series[index]
                HStack(spacing: 4) {
                    if self.series.count > 1 {
                        Circle()
                            .fill(series.color)
                            .frame(width: 8, height: 8)
                    }
                    Text(verbatim: "\(series.name) \(series.value(point).map(format) ?? "—")")
                        .monospacedDigit()
                }
            }
        }
        .font(.caption)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
