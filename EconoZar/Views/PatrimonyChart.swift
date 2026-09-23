import Charts
import SwiftUI

struct PatrimonyChart: View {
    var points: [PatrimonyPoint]
    @State private var selectedMonth: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Evolução do patrimônio")
                .font(.headline)

            if points.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Text("Os aportes vão desenhar essa curva.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                Chart(points) { point in
                    AreaMark(
                        x: .value("Mês", point.month, unit: .month),
                        y: .value("Total", point.total)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.32), Color.accentColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(points.count > 2 ? .catmullRom : .linear)

                    LineMark(
                        x: .value("Mês", point.month, unit: .month),
                        y: .value("Total", point.total)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(points.count > 2 ? .catmullRom : .linear)

                    if let selectedMonth, Calendar.current.isDate(selectedMonth, equalTo: point.month, toGranularity: .month) {
                        RuleMark(x: .value("Mês", point.month, unit: .month))
                            .foregroundStyle(Color.accentColor.opacity(0.45))
                        PointMark(
                            x: .value("Mês", point.month, unit: .month),
                            y: .value("Total", point.total)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(height: 180)
                .chartXSelection(value: $selectedMonth)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number, format: .number.notation(.compactName))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                            .font(.caption2)
                    }
                }

                Text(selectionCaption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectionCaption: String {
        guard
            let selectedMonth,
            let point = points.first(where: { Calendar.current.isDate($0.month, equalTo: selectedMonth, toGranularity: .month) })
        else {
            return "Arraste no gráfico para ver um mês."
        }
        let month = point.month.formatted(.dateTime.month(.wide).year())
        let value = Decimal(point.total).formatted(.currency(code: "BRL").locale(Money.locale))
        return "\(month.capitalized) · \(value)"
    }
}
