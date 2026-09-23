import SwiftUI

struct EconoCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
    }
}

struct AmountDial: View {
    @Binding var amount: Decimal
    var planned: Decimal?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Money.string(amount))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Valor do aporte \(Money.string(amount))")

            HStack(spacing: 10) {
                stepButton("−10", delta: -10)
                stepButton("−1", delta: -1)
                stepButton("+1", delta: 1)
                stepButton("+10", delta: 10)
            }

            HStack(spacing: 8) {
                chip("Dia zero") { amount = 0 }
                if let planned {
                    chip("Metade") { amount = Money.half(planned) }
                    chip("Plano") { amount = planned }
                }
            }
        }
    }

    private func stepButton(_ title: String, delta: Decimal) -> some View {
        Button(title) {
            amount = Money.bump(amount, by: delta)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .buttonStyle(.plain)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .buttonStyle(.plain)
    }
}

struct VaultProgressRow: View {
    var vault: Vault

    private var projection: GoalProjection {
        Insights.projection(for: vault)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: vault.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(vault.name)
                        .font(.body.weight(.semibold))
                    Spacer()
                    Text(percentText)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: projection.progress)
                    .tint(Color.accentColor)
                Text(Money.string(vault.currentAmount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var percentText: String {
        guard vault.effectiveTarget > 0 else { return "—" }
        return "\(Int((projection.progress * 100).rounded()))%"
    }
}
