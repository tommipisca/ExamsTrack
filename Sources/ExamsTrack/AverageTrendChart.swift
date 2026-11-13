import SwiftUI
import Charts
import ExamsCore

/// Media pesata dopo ogni esame superato. Una sola serie: niente legenda, il titolo della sezione la nomina.
/// Tenendo premuto o trascinando si vede il dettaglio dell'esame più vicino.
struct AverageTrendChart: View {
    let points: [TrendPoint]
    /// Più alto quando c'è spazio (colonna di dettaglio su iPad).
    var height: CGFloat = 180
    @State private var selectedDate: Date?

    private var selected: TrendPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.average)
        let low = max(18, ((values.min() ?? 18) - 1).rounded(.down))
        let high = min(30, ((values.max() ?? 30) + 1).rounded(.up))
        return low...max(high, low + 1)
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Data", point.date), y: .value("Media", point.average))
                    .foregroundStyle(Theme.chartLine)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Data", point.date), y: .value("Media", point.average))
                    .symbol {
                        // Punto di 8 pt con anello del colore della superficie.
                        Circle()
                            .fill(Theme.chartLine)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                    }
                    .accessibilityLabel(point.examName)
                    .accessibilityValue("Voto \(point.grade), media \(CareerStatsRow.averageText(point.average))")
            }
            if let selected {
                RuleMark(x: .value("Data", selected.date))
                    .foregroundStyle(Theme.stroke)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.examName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text("Voto \(selected.grade) · media \(CareerStatsRow.averageText(selected.average))")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.elevated))
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.stroke)
                AxisValueLabel().foregroundStyle(Theme.textSecondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(height: height)
        .padding(.top, 28)
        .padding(.vertical, 6)
    }
}
