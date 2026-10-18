import SwiftUI

/// Areas drawn on the front / back body map.
enum MuscleRegion: String, CaseIterable {
    case neck, traps, frontDelts, rearDelts, chest, biceps, triceps, forearms
    case abs, obliques, hipFlexors, lats, upperBack, lowerBack
    case glutes, abductors, adductors, quads, hamstrings, calves, shins

    var label: String {
        switch self {
        case .neck: return "Neck"
        case .traps: return "Traps"
        case .frontDelts: return "Front shoulders"
        case .rearDelts: return "Rear shoulders"
        case .chest: return "Chest"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .abs: return "Abs"
        case .obliques: return "Obliques"
        case .hipFlexors: return "Hip flexors"
        case .lats: return "Lats"
        case .upperBack: return "Upper back"
        case .lowerBack: return "Lower back"
        case .glutes: return "Glutes"
        case .abductors: return "Outer hips"
        case .adductors: return "Inner thighs"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .calves: return "Calves"
        case .shins: return "Shins"
        }
    }

    /// Regions a muscle name from the exercise library lights up.
    static func regions(forMuscle muscle: String) -> [MuscleRegion] {
        switch muscle.lowercased() {
        case "pectorals", "chest", "upper chest", "lower chest": return [.chest]
        case "serratus anterior", "obliques": return [.obliques]
        case "delts", "deltoids", "shoulders": return [.frontDelts, .rearDelts]
        case "front deltoids", "anterior deltoids": return [.frontDelts]
        case "rear deltoids", "rotator cuff", "posterior deltoids": return [.rearDelts]
        case "biceps", "brachialis": return [.biceps]
        case "triceps": return [.triceps]
        case "forearms", "wrist flexors", "wrist extensors", "grip muscles", "wrists", "hands": return [.forearms]
        case "abs", "abdominals", "lower abs", "upper abs": return [.abs]
        case "core": return [.abs, .obliques]
        case "hip flexors": return [.hipFlexors]
        case "lats", "latissimus dorsi": return [.lats]
        case "upper back", "rhomboids": return [.upperBack]
        case "traps", "trapezius": return [.traps]
        case "levator scapulae", "sternocleidomastoid", "neck": return [.neck]
        case "spine", "erector spinae", "lower back": return [.lowerBack]
        case "back": return [.lats, .upperBack]
        case "glutes": return [.glutes]
        case "abductors": return [.abductors]
        case "adductors", "inner thighs", "groin": return [.adductors]
        case "quads", "quadriceps": return [.quads]
        case "hamstrings": return [.hamstrings]
        case "calves", "soleus", "ankles", "ankle stabilizers", "feet": return [.calves]
        case "shins", "tibialis anterior": return [.shins]
        default: return []
        }
    }

    /// How hard each region is worked, 0...1 relative to the busiest one.
    static func intensities(_ loads: [MuscleLoad]) -> [MuscleRegion: Double] {
        var raw: [MuscleRegion: Double] = [:]
        for load in loads {
            for region in regions(forMuscle: load.muscle) { raw[region, default: 0] += load.score }
        }
        let top = raw.values.max() ?? 0
        guard top > 0 else { return [:] }
        return raw.mapValues { $0 / top }
    }
}

/// Front and back body outlines with the worked muscles highlighted.
/// Brighter red means more sets for that area.
struct MuscleMapView: View {
    var loads: [MuscleLoad]

    var body: some View {
        let levels = MuscleRegion.intensities(loads)
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                figure(title: "Front", side: .front, levels: levels)
                figure(title: "Back", side: .back, levels: levels)
            }
            legend
            let worked = levels.sorted { $0.value > $1.value }.map(\.key)
            if !worked.isEmpty {
                Text(worked.prefix(6).map(\.label).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(levels))
    }

    private func figure(title: String, side: BodySide, levels: [MuscleRegion: Double]) -> some View {
        VStack(spacing: 4) {
            BodyFigure(side: side, levels: levels)
                .aspectRatio(200.0 / 420.0, contentMode: .fit)
                .frame(maxHeight: 260)
            Text(title).font(.caption.bold()).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Light").font(.caption2).foregroundStyle(Theme.secondaryText)
            LinearGradient(colors: [BodyFigure.heat(0.05), BodyFigure.heat(0.5), BodyFigure.heat(1)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 120, height: 8)
                .clipShape(Capsule())
            Text("Most worked").font(.caption2).foregroundStyle(Theme.secondaryText)
        }
    }

    private func accessibilityText(_ levels: [MuscleRegion: Double]) -> String {
        let worked = levels.sorted { $0.value > $1.value }.map(\.key.label)
        return worked.isEmpty ? "Muscle map: no muscles yet" : "Muscles worked: " + worked.joined(separator: ", ")
    }
}

enum BodySide { case front, back }

/// One body outline drawn in a 200 × 420 space. Shapes are defined for the
/// figure's left half and mirrored for the right.
struct BodyFigure: View {
    var side: BodySide
    var levels: [MuscleRegion: Double]

    static let base = Color.white.opacity(0.10)
    static let idle = Color.white.opacity(0.24)

    /// Orange to bright red as the work goes up.
    static func heat(_ level: Double) -> Color {
        let t = min(max(level, 0), 1)
        return Color(red: 1.0, green: 0.62 - 0.45 * t, blue: 0.20 - 0.10 * t).opacity(0.55 + 0.45 * t)
    }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 200, size.height / 420)
            context.translateBy(x: (size.width - 200 * scale) / 2, y: (size.height - 420 * scale) / 2)
            context.scaleBy(x: scale, y: scale)

            // Silhouette under the muscles.
            for path in silhouette { context.fill(path, with: .color(Self.base)) }
            for (region, path) in regions {
                let fill = levels[region].map(Self.heat) ?? Self.idle
                context.fill(path, with: .color(fill))
                context.stroke(path, with: .color(Theme.background.opacity(0.9)), lineWidth: 1.2)
            }
        }
    }

    // MARK: Geometry

    private static let mirror = CGAffineTransform(translationX: 200, y: 0).scaledBy(x: -1, y: 1)

    private static func pair(_ path: Path) -> Path {
        var both = path
        both.addPath(path.applying(mirror))
        return both
    }

    private static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, angle: Double = 0) -> Path {
        let rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        let rotate = CGAffineTransform(translationX: cx, y: cy)
            .rotated(by: angle * .pi / 180)
            .translatedBy(x: -cx, y: -cy)
        return Path(ellipseIn: rect).applying(rotate)
    }

    private static func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
        path.closeSubpath()
        return path
    }

    private var silhouette: [Path] {
        [
            Self.ellipse(100, 30, 36, 44),                                   // head
            Path(roundedRect: CGRect(x: 89, y: 46, width: 22, height: 24), cornerRadius: 6),
            Self.polygon([(76, 64), (124, 64), (134, 80), (127, 122), (119, 186), (124, 210),
                          (76, 210), (81, 186), (73, 122), (66, 80)]),               // torso
            Self.pair(Self.ellipse(55, 125, 20, 66, angle: 8)),              // upper arms
            Self.pair(Self.ellipse(47, 172, 17, 56, angle: 10)),             // forearms
            Self.pair(Self.ellipse(42, 207, 14, 18)),                        // hands
            Self.pair(Self.ellipse(84, 265, 34, 118, angle: -3)),            // thighs
            Self.pair(Self.ellipse(84, 362, 22, 84)),                        // lower legs
            Self.pair(Self.ellipse(86, 408, 24, 10))                         // feet
        ]
    }

    private var regions: [(MuscleRegion, Path)] {
        switch side {
        case .front: return Self.frontRegions
        case .back: return Self.backRegions
        }
    }

    private static let frontRegions: [(MuscleRegion, Path)] = [
        (.neck, polygon([(92, 52), (108, 52), (106, 68), (94, 68)])),
        (.traps, pair(polygon([(91, 60), (72, 72), (88, 72)]))),
        (.frontDelts, pair(ellipse(64, 84, 26, 30, angle: 15))),
        (.chest, pair({
            var p = Path()
            p.move(to: CGPoint(x: 99, y: 74))
            p.addLine(to: CGPoint(x: 80, y: 74))
            p.addQuadCurve(to: CGPoint(x: 72, y: 98), control: CGPoint(x: 71, y: 80))
            p.addQuadCurve(to: CGPoint(x: 86, y: 114), control: CGPoint(x: 74, y: 112))
            p.addLine(to: CGPoint(x: 99, y: 114))
            p.closeSubpath()
            return p
        }())),
        (.biceps, pair(ellipse(56, 122, 15, 40, angle: 8))),
        (.forearms, pair(ellipse(47, 172, 14, 48, angle: 10))),
        (.abs, Path(roundedRect: CGRect(x: 87, y: 118, width: 26, height: 70), cornerRadius: 8)),
        (.obliques, pair(polygon([(85, 118), (73, 120), (75, 168), (85, 186)]))),
        (.hipFlexors, pair(polygon([(76, 186), (99, 198), (99, 210), (80, 204)]))),
        (.quads, pair(ellipse(80, 262, 26, 94, angle: -4))),
        (.adductors, pair(ellipse(95, 236, 9, 52, angle: -6))),
        (.shins, pair(ellipse(86, 362, 9, 62))),
        (.calves, pair(ellipse(77, 356, 9, 50, angle: 3)))
    ]

    private static let backRegions: [(MuscleRegion, Path)] = [
        (.neck, polygon([(93, 50), (107, 50), (106, 60), (94, 60)])),
        (.traps, polygon([(100, 54), (72, 74), (86, 86), (100, 94), (114, 86), (128, 74)])),
        (.rearDelts, pair(ellipse(64, 84, 26, 30, angle: 15))),
        (.upperBack, pair(polygon([(98, 96), (86, 89), (82, 112), (98, 122)]))),
        (.lats, pair(polygon([(81, 96), (71, 104), (75, 142), (92, 170), (95, 150), (84, 120)]))),
        (.triceps, pair(ellipse(56, 122, 15, 40, angle: 8))),
        (.forearms, pair(ellipse(47, 172, 14, 48, angle: 10))),
        (.lowerBack, Path(roundedRect: CGRect(x: 89, y: 138, width: 22, height: 52), cornerRadius: 8)),
        (.abductors, pair(ellipse(71, 206, 10, 26))),
        (.glutes, pair(ellipse(87, 214, 26, 32))),
        (.hamstrings, pair(ellipse(84, 274, 26, 84, angle: -3))),
        (.calves, pair(ellipse(84, 352, 20, 56)))
    ]
}

#Preview {
    MuscleMapView(loads: [
        MuscleLoad(muscle: "pectorals", group: .chest, primarySets: 4, secondarySets: 0),
        MuscleLoad(muscle: "triceps", group: .arms, primarySets: 0, secondarySets: 4),
        MuscleLoad(muscle: "delts", group: .shoulders, primarySets: 0, secondarySets: 4)
    ])
    .padding()
    .background(Theme.card)
}
