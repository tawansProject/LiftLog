import SwiftUI
import UIKit

/// Wrapping row of muscle chips. Target muscles are filled, secondary ones outlined.
struct MuscleChips: View {
    var target: [String]
    var secondary: [String] = []
    var compact = false

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(target, id: \.self) { muscle in
                chip(muscle, filled: true)
            }
            ForEach(secondary.filter { !target.contains($0) }, id: \.self) { muscle in
                chip(muscle, filled: false)
            }
        }
    }

    private func chip(_ muscle: String, filled: Bool) -> some View {
        let color = MuscleGroup.group(forMuscle: muscle).color
        return Text(muscle.capitalized)
            .font(compact ? .caption2 : .caption)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 4)
            .foregroundStyle(filled ? Color.white : color)
            .background(filled ? color : color.opacity(0.22), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(filled ? 0 : 0.85), lineWidth: 1))
    }
}

/// Simple flow layout that wraps children onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Card showing the progressive-overload suggestion, with an optional Apply button.
struct SuggestionCard: View {
    var suggestion: OverloadSuggestion
    var lastSummary: String?
    var applyTitle: String = "Apply"
    var onApply: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let lastSummary {
                Text("Last time: \(lastSummary)")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }
            HStack(alignment: .top) {
                Image(systemName: suggestion.action.symbol)
                    .foregroundStyle(color)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.headline).font(.subheadline.bold())
                    Text(suggestion.reason).font(.caption).foregroundStyle(Theme.subtext)
                }
                Spacer(minLength: 0)
                if let onApply, suggestion.isChange {
                    Button(applyTitle, action: onApply)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.45), lineWidth: 1))
    }

    private var color: Color {
        switch suggestion.action {
        case .increaseWeight, .increaseReps: return .green
        case .hold: return .blue
        case .decrease, .deload: return .orange
        case .recover: return .red
        }
    }
}

/// Bar list of muscle groups and muscles for a session.
struct MuscleOverview: View {
    var loads: [MuscleLoad]

    var body: some View {
        let groups = MuscleAnalysis.groupTotals(loads)
        let maxGroup = groups.map(\.score).max() ?? 1
        VStack(alignment: .leading, spacing: 14) {
            if groups.isEmpty {
                Text("No muscles yet. Add an exercise.").foregroundStyle(Theme.subtext)
            }
            ForEach(groups) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(entry.group.label, systemImage: entry.group.symbol)
                            .font(.subheadline.bold())
                            .foregroundStyle(entry.group.color)
                        Spacer()
                        Text("\(Format.number(entry.score)) sets")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.subtext)
                    }
                    GeometryReader { geo in
                        Capsule().fill(entry.group.color.opacity(0.25))
                            .overlay(alignment: .leading) {
                                Capsule().fill(entry.group.color)
                                    .frame(width: geo.size.width * entry.score / maxGroup)
                            }
                    }
                    .frame(height: 8)
                    let muscles = loads.filter { $0.group == entry.group }
                    Text(muscles.map { "\($0.muscle.capitalized) \(Format.number($0.score))" }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
            }
            if !groups.isEmpty {
                Text("Counts working sets: target muscles count 1, secondary muscles count ½.")
                    .font(.caption2)
                    .foregroundStyle(Theme.faint)
            }
        }
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var detail: String?
    var symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(Theme.subtext)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.outline, lineWidth: 1))
    }
}

extension LoggedExercise {
    /// "30 kg × 12, 12, 10" summary of completed sets.
    var performedSummary: String {
        let done = doneSets.filter { $0.kind != .warmup }
        guard !done.isEmpty else { return "No sets done" }
        let byWeight = Dictionary(grouping: done, by: \.weight)
        return byWeight.keys.sorted(by: >).map { weight in
            "\(Format.weight(weight)) × " + (byWeight[weight] ?? []).map { "\($0.reps)" }.joined(separator: ", ")
        }.joined(separator: " · ")
    }
}

/// Effort scale shared by the effort sheet and history.
enum EffortScale {
    static func label(_ effort: Int) -> String {
        switch effort {
        case ...3: return "Easy"
        case 4...6: return "Moderate"
        case 7...8: return "Hard"
        case 9: return "Very hard"
        default: return "Max effort"
        }
    }

    static func color(_ effort: Int) -> Color {
        switch effort {
        case ...3: return .green
        case 4...6: return .mint
        case 7...8: return .orange
        default: return .red
        }
    }
}
