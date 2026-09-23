import SwiftUI
import UIKit
import WidgetKit

struct FlexEntry: TimelineEntry {
    let date: Date
    let plannedAmount: Double
    let totalSaved: Double
    let streak: Int
    let checkedIn: Bool
    let weekdayName: String
    let businessName: String
    let hasPlan: Bool
}

struct FlexProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlexEntry {
        makeEntry(at: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (FlexEntry) -> Void) {
        completion(makeEntry(at: .now, snapshot: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlexEntry>) -> Void) {
        let snapshot = load()
        let entry = makeEntry(at: .now, snapshot: snapshot)
        let calendar = Calendar.current
        let refresh = calendar.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) ?? .now.addingTimeInterval(60 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry(at date: Date, snapshot: WidgetSnapshot) -> FlexEntry {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "pt_BR")
        return FlexEntry(
            date: date,
            plannedAmount: snapshot.plannedAmount(on: date, calendar: calendar),
            totalSaved: snapshot.totalSaved,
            streak: snapshot.visibleStreak(on: date, calendar: calendar),
            checkedIn: snapshot.checkedInToday(on: date, calendar: calendar),
            weekdayName: weekdayName(on: date, calendar: calendar),
            businessName: snapshot.businessName,
            hasPlan: snapshot.hasPlan
        )
    }

    private func load() -> WidgetSnapshot {
        guard
            let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID),
            let data = defaults.data(forKey: WidgetSnapshot.storageKey),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    private func weekdayName(on date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)
        let symbols = calendar.weekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "" }
        let text = symbols[index]
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

struct EconoZarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: FlexEntry

    var body: some View {
        switch family {
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Aporte Flex", systemImage: entry.checkedIn ? "checkmark.circle.fill" : "leaf.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.econo)
            if entry.hasPlan {
                Text(entry.weekdayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(entry.plannedAmount, format: .currency(code: "BRL").locale(Locale(identifier: "pt_BR")))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(entry.streak == 1 ? "1 dia" : "\(entry.streak) dias")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Spacer(minLength: 0)
                Text("Hora do aporte")
                    .font(.headline)
                Text("Toque para registrar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.hasPlan ? entry.weekdayName : "EconoZar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if entry.hasPlan {
                    Text(entry.plannedAmount, format: .currency(code: "BRL").locale(Locale(identifier: "pt_BR")))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                } else {
                    Text("Hora do Aporte Flex")
                        .font(.title3.weight(.semibold))
                }
                Text(entry.checkedIn ? "Aporte de hoje registrado" : "Toque para registrar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(entry.checkedIn ? Color.econo : .secondary)
            }
            Spacer(minLength: 0)
            if entry.hasPlan {
                VStack(alignment: .trailing, spacing: 8) {
                    Text("Guardado")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.totalSaved, format: .currency(code: "BRL").locale(Locale(identifier: "pt_BR")))
                        .font(.headline.monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(entry.businessName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct EconoZarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EconoZarWidget", provider: FlexProvider()) { entry in
            EconoZarWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
                .widgetURL(URL(string: "econozar://checkin"))
        }
        .configurationDisplayName("Aporte Flex")
        .description("Valor sugerido de hoje, sequência e total guardado.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct EconoZarWidgetBundle: WidgetBundle {
    var body: some Widget {
        EconoZarWidget()
    }
}

private extension Color {
    static let econo = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.404, green: 0.839, blue: 0.659, alpha: 1)
        }
        return UIColor(red: 0.086, green: 0.502, blue: 0.373, alpha: 1)
    })
}
