import Charts
import SwiftUI
import UIKit

/// How full or busy something is, as the desktop's 系统监控 colours it:
/// high from 70%, critical from 90%.
enum Severity {
    case normal
    case high
    case critical

    init(percent: Double) {
        self = percent >= 90 ? .critical : percent >= 70 ? .high : .normal
    }

    var color: Color {
        switch self {
        case .normal: .accentColor
        case .high: .orange
        case .critical: .red
        }
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

    /// 「0.20 · 0.18 · 0.12」: the last one, five and fifteen minutes.
    static func load(_ load: LoadAverage) -> String {
        [load.one, load.five, load.fifteen]
            .map { $0.formatted(.number.precision(.fractionLength(2))) }
            .joined(separator: " · ")
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
            // No label: the row above says it, and the linear capacity
            // style draws one over the bar even with `labelsHidden()`.
            Gauge(value: min(max(percent ?? 0, 0), 100), in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.linearCapacity)
            .tint(severity.color)
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
        VStack(alignment: .leading, spacing: 4) {
            Chart {
                ForEach(series.indices, id: \.self) { index in
                    let series = series[index]
                    ForEach(points) { point in
                        if let value = series.value(point) {
                            if self.series.count == 1 {
                                AreaMark(x: .value("时间", point.at), y: .value(series.name, value))
                                    .foregroundStyle(series.color.opacity(0.12))
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
            Text("最近 3 分钟，按住拖动查看每个时刻")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
