import SwiftUI

/// Muscle regions drawn on the front / back body figures.
enum BodyRegion: String, CaseIterable {
    case traps, frontDelts, rearDelts, chest, biceps, triceps, forearms, abs, obliques
    case upperBack, lats, lowerBack, glutes, quads, adductors, hamstrings, calves, shins

    var label: String {
        switch self {
        case .traps: return "Traps"
        case .frontDelts: return "Front shoulders"
        case .rearDelts: return "Rear shoulders"
        case .chest: return "Chest"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .abs: return "Abs"
        case .obliques: return "Obliques"
        case .upperBack: return "Upper back"
        case .lats: return "Lats"
        case .lowerBack: return "Lower back"
        case .glutes: return "Glutes"
        case .quads: return "Quads"
        case .adductors: return "Inner thighs"
        case .hamstrings: return "Hamstrings"
        case .calves: return "Calves"
        case .shins: return "Shins"
        }
    }

    /// ExerciseDB muscle names onto the drawn regions.
    static func regions(forMuscle muscle: String) -> [BodyRegion] {
        switch muscle.lowercased() {
        case "pectorals", "chest", "upper chest", "lower chest": return [.chest]
        case "serratus anterior": return [.obliques]
        case "deltoids", "delts", "shoulders": return [.frontDelts, .rearDelts]
        case "front deltoids", "anterior deltoids": return [.frontDelts]
        case "rear deltoids", "posterior deltoids": return [.rearDelts]
        case "rotator cuff": return [.rearDelts, .upperBack]
        case "biceps", "brachialis": return [.biceps]
        case "triceps": return [.triceps]
        case "forearms", "wrist flexors", "wrist extensors", "grip muscles", "wrists", "hands": return [.forearms]
        case "abdominals", "abs", "core", "lower abs": return [.abs]
        case "obliques": return [.obliques]
        case "hip flexors", "adductors", "groin", "inner thighs": return [.adductors]
        case "quadriceps", "quads": return [.quads]
        case "hamstrings": return [.hamstrings]
        case "glutes", "abductors": return [.glutes]
        case "calves", "soleus", "gastrocnemius": return [.calves, .shins]
        case "tibialis anterior", "shins", "ankles", "ankle stabilizers", "feet": return [.shins]
        case "latissimus dorsi", "lats": return [.lats]
        case "upper back", "rhomboids", "teres major": return [.upperBack]
        case "trapezius", "traps", "levator scapulae": return [.traps]
        case "erector spinae", "lower back", "spine": return [.lowerBack]
        case "back": return [.lats, .upperBack]
        default: return []
        }
    }
}

/// How hard each region is worked, from a session's muscle loads.
struct BodyHeat {
    private(set) var primary: [BodyRegion: Double] = [:]
    private(set) var secondary: [BodyRegion: Double] = [:]
    private(set) var maxScore: Double = 0

    init(loads: [MuscleLoad]) {
        for load in loads {
            for region in BodyRegion.regions(forMuscle: load.muscle) {
                primary[region, default: 0] += load.primarySets
                secondary[region, default: 0] += load.secondarySets
            }
        }
        maxScore = BodyRegion.allCases.map { score($0) }.max() ?? 0
    }

    func score(_ region: BodyRegion) -> Double {
        (primary[region] ?? 0) + (secondary[region] ?? 0) * 0.5
    }

    func color(for region: BodyRegion) -> Color {
        let share = maxScore > 0 ? score(region) / maxScore : 0
        if (primary[region] ?? 0) > 0 { return Theme.muscleHot.opacity(0.55 + 0.45 * share) }
        if (secondary[region] ?? 0) > 0 { return Theme.muscleWarm.opacity(0.55 + 0.35 * share) }
        return Theme.muscleIdle
    }

    var workedRegions: [BodyRegion] {
        BodyRegion.allCases.filter { score($0) > 0 }.sorted { score($0) > score($1) }
    }
}

/// Front and back body figures with the worked muscles highlighted.
struct BodyMapView: View {
    var loads: [MuscleLoad]
    var height: CGFloat = 250

    var body: some View {
        let heat = BodyHeat(loads: loads)
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                figure(.front, heat: heat)
                figure(.back, heat: heat)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 14) {
                legendDot(Theme.muscleHot, "Main target")
                legendDot(Theme.muscleWarm, "Also worked")
                legendDot(Theme.muscleIdle, "Not worked")
            }
            .font(.caption2)
            .foregroundStyle(Theme.subtext)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(heat))
    }

    private func figure(_ side: BodyFigure.Side, heat: BodyHeat) -> some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                BodyFigure.draw(side, heat: heat, in: &context, size: size)
            }
            .aspectRatio(BodyFigure.size.width / BodyFigure.size.height, contentMode: .fit)
            .frame(height: height)
            Text(side == .front ? "Front" : "Back")
                .font(.caption.bold())
                .foregroundStyle(Theme.faint)
        }
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }

    private func accessibilityText(_ heat: BodyHeat) -> String {
        let worked = heat.workedRegions.map(\.label)
        return worked.isEmpty ? "Body map: no muscles yet" : "Body map. Worked: " + worked.joined(separator: ", ")
    }
}

/// Stylised anatomy drawn in a 200 × 420 space. Shapes are given for the
/// figure's left half and mirrored; points on the centre line join up.
enum BodyFigure {
    enum Side { case front, back }

    static let size = CGSize(width: 200, height: 420)

    private enum Outline {
        case blob([CGPoint])
        case oval(CGRect)
    }

    private struct Part {
        var region: BodyRegion?
        var shape: Outline
        var mirrored = true
    }

    static func draw(_ side: Side, heat: BodyHeat, in context: inout GraphicsContext, size canvas: CGSize) {
        let scale = min(canvas.width / size.width, canvas.height / size.height)
        context.translateBy(x: (canvas.width - size.width * scale) / 2, y: (canvas.height - size.height * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        let idleBody = Theme.muscleIdle.opacity(0.7)
        let gap = StrokeStyle(lineWidth: 1.6, lineJoin: .round)
        context.fill(path(.blob(silhouette)), with: .color(Theme.muscleIdle.opacity(0.38)))

        for part in side == .front ? front : back {
            let fill = part.region.map(heat.color(for:)) ?? idleBody
            for path in paths(for: part) {
                context.fill(path, with: .color(fill))
                // Navy edge separates neighbouring muscles.
                context.stroke(path, with: .color(Theme.background), style: gap)
            }
        }
    }

    private static func paths(for part: Part) -> [Path] {
        var result = [path(part.shape)]
        if part.mirrored { result.append(path(mirror(part.shape))) }
        return result
    }

    private static func mirror(_ shape: Outline) -> Outline {
        switch shape {
        case .blob(let points):
            return .blob(points.map { CGPoint(x: size.width - $0.x, y: $0.y) })
        case .oval(let rect):
            return .oval(CGRect(x: size.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height))
        }
    }

    private static func path(_ shape: Outline) -> Path {
        switch shape {
        case .oval(let rect):
            return Path(ellipseIn: rect)
        case .blob(let points):
            // Smooth closed curve through the midpoints, using each point as the control.
            var path = Path()
            guard points.count > 2 else { return path }
            func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
            path.move(to: mid(points[points.count - 1], points[0]))
            for i in points.indices {
                path.addQuadCurve(to: mid(points[i], points[(i + 1) % points.count]), control: points[i])
            }
            path.closeSubpath()
            return path
        }
    }

    private static func blob(_ region: BodyRegion?, _ coords: [(CGFloat, CGFloat)], mirrored: Bool = true) -> Part {
        Part(region: region, shape: .blob(coords.map { CGPoint(x: $0.0, y: $0.1) }), mirrored: mirrored)
    }

    private static func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, mirrored: Bool = true) -> Part {
        Part(region: nil, shape: .oval(CGRect(x: x, y: y, width: w, height: h)), mirrored: mirrored)
    }

    /// Whole-body outline under the muscles: the left edge from the neck to
    /// between the feet, then the same edge mirrored back up.
    private static let silhouette: [CGPoint] = {
        let left: [(CGFloat, CGFloat)] = [
            (100, 48), (89, 50), (88, 64), (70, 70), (53, 77), (46, 96), (44, 130), (43, 152), (37, 184),
            (34, 208), (31, 230), (38, 243), (47, 238), (49, 214), (55, 190), (61, 166), (63, 134), (66, 126),
            (66, 142), (70, 168), (66, 192), (62, 224), (64, 262), (69, 292), (64, 320), (63, 345), (67, 382),
            (61, 402), (64, 414), (87, 414), (86, 390), (86, 350), (87, 315), (88, 296), (92, 262), (95, 236), (100, 216)
        ]
        let points = left.map { CGPoint(x: $0.0, y: $0.1) }
        return points + points.reversed().dropFirst().dropLast().map { CGPoint(x: size.width - $0.x, y: $0.y) }
    }()

    // Shared head, neck, hands, knees and feet.
    private static let bodyFrame: [Part] = [
        oval(80, 6, 40, 48, mirrored: false),
        blob(nil, [(92, 50), (108, 50), (110, 66), (90, 66)], mirrored: false),
        oval(34, 214, 14, 26),
        oval(69, 293, 18, 17),
        blob(nil, [(70, 388), (62, 404), (66, 412), (86, 412), (85, 390)])
    ]

    private static let forearm = blob(.forearms, [(46, 164), (40, 184), (37, 208), (44, 212), (53, 192), (59, 166)])

    private static let front: [Part] = bodyFrame + [
        blob(.traps, [(91, 60), (74, 70), (69, 76), (88, 74)]),
        blob(.frontDelts, [(70, 74), (56, 80), (49, 96), (53, 113), (64, 104), (72, 88)]),
        blob(.chest, [(98, 78), (76, 78), (66, 94), (68, 112), (82, 120), (98, 116)]),
        blob(.biceps, [(52, 116), (46, 132), (45, 150), (52, 161), (60, 148), (62, 124)]),
        forearm,
        blob(.abs, [(86, 122), (98, 122), (98, 139), (86, 139)]),
        blob(.abs, [(86, 141), (98, 141), (98, 158), (86, 158)]),
        blob(.abs, [(86, 160), (98, 160), (98, 177), (86, 177)]),
        blob(.abs, [(86, 179), (98, 179), (98, 202), (89, 196)]),
        blob(.obliques, [(84, 124), (72, 118), (67, 140), (71, 168), (80, 188), (84, 160)]),
        blob(.quads, [(87, 198), (70, 190), (63, 224), (65, 262), (73, 290), (86, 292), (90, 262), (88, 226)]),
        blob(.adductors, [(99, 210), (93, 206), (90, 236), (94, 262), (99, 250)]),
        blob(.shins, [(70, 312), (65, 340), (69, 380), (78, 385), (84, 350), (85, 314)])
    ]

    private static let back: [Part] = bodyFrame + [
        blob(.traps, [(100, 56), (90, 62), (70, 76), (84, 84), (96, 104), (100, 114)]),
        blob(.rearDelts, [(68, 78), (56, 82), (49, 98), (53, 113), (64, 102), (72, 88)]),
        blob(.upperBack, [(84, 88), (72, 92), (69, 107), (82, 117), (94, 110)]),
        blob(.lats, [(70, 112), (64, 128), (70, 152), (84, 172), (90, 168), (90, 140), (82, 120)]),
        blob(.lowerBack, [(99, 124), (94, 128), (92, 168), (90, 194), (99, 198)]),
        blob(.triceps, [(52, 114), (46, 130), (45, 150), (52, 161), (62, 150), (62, 122)]),
        forearm,
        blob(.glutes, [(99, 200), (84, 196), (70, 204), (67, 226), (80, 241), (99, 237)]),
        blob(.hamstrings, [(96, 244), (80, 242), (68, 248), (65, 272), (72, 293), (86, 295), (94, 276)]),
        blob(.calves, [(70, 311), (63, 330), (67, 360), (76, 381), (84, 360), (86, 330), (84, 312)])
    ]
}
