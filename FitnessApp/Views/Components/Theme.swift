import SwiftUI
import UIKit
import SwiftData

/// Dark blue theme used across the iPhone app. Tuned for contrast: a deeper
/// background, brighter cards and accent, and secondary text that stays readable.
enum Theme {
    static let background = Color(red: 0.024, green: 0.063, blue: 0.141)   // #061024 deep navy
    static let card = Color(red: 0.082, green: 0.176, blue: 0.333)         // #152D55
    static let cardRaised = Color(red: 0.125, green: 0.251, blue: 0.459)   // #204075
    static let accent = Color(red: 0.373, green: 0.627, blue: 1.0)         // #5FA0FF
    /// Tinted fill for selected / current rows.
    static let accentSoft = accent.opacity(0.24)
    /// White highlight surfaces and buttons, with navy text on them.
    static let highlight = Color.white
    static let onHighlight = Color(red: 0.024, green: 0.063, blue: 0.141)  // navy text on white
    /// Secondary and tertiary text on navy (system grey is too faint here).
    static let subtext = Color(red: 0.776, green: 0.835, blue: 0.929)      // #C6D5ED
    static let faint = Color(red: 0.576, green: 0.651, blue: 0.776)        // #93A6C6
    /// Outline that lifts cards off the navy background.
    static let outline = Color.white.opacity(0.20)
    /// Muscle map: worked muscles in a warm colour that stands out against blue.
    static let muscleHot = Color(red: 1.0, green: 0.333, blue: 0.247)      // #FF553F primary
    static let muscleWarm = Color(red: 1.0, green: 0.659, blue: 0.290)     // #FFA84A secondary
    static let muscleIdle = Color(red: 0.180, green: 0.310, blue: 0.525)   // #2E4F86 not worked

    /// Navigation and tab bars in the same navy.
    static func applyAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(background)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(card)
        tab.shadowColor = UIColor(outline)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(faint)
            item.normal.titleTextAttributes = [.foregroundColor: UIColor(faint)]
            item.selected.iconColor = UIColor(accent)
            item.selected.titleTextAttributes = [.foregroundColor: UIColor(accent)]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

/// Primary action button: solid white with navy text.
struct WhiteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WhiteButton(configuration: configuration)
    }

    private struct WhiteButton: View {
        var configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(Theme.onHighlight)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Theme.highlight.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35),
                            in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

extension ButtonStyle where Self == WhiteButtonStyle {
    static var white: WhiteButtonStyle { WhiteButtonStyle() }
}

extension View {
    /// Navy background behind a List or Form (rows use `Theme.card`).
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}

/// Small exercise GIF; tap to open a larger preview.
struct ExerciseThumbnail: View {
    var name: String
    var gifUrl: String?
    var targetMuscles: [String] = []
    var secondaryMuscles: [String] = []
    var exerciseId: String? = nil
    var size: CGFloat = 56
    @State private var showPreview = false

    var body: some View {
        Button { showPreview = true } label: {
            ExerciseGIFView(urlString: gifUrl, exerciseId: exerciseId)
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(!ExerciseMedia.hasAnimation(gifUrl: gifUrl, exerciseId: exerciseId))
        .sheet(isPresented: $showPreview) {
            ExercisePreviewSheet(name: name, gifUrl: gifUrl, targetMuscles: targetMuscles,
                                 secondaryMuscles: secondaryMuscles, exerciseId: exerciseId)
                .presentationDetents([.medium, .large])
        }
    }
}

/// Large animated preview with muscles and, when cached, the instructions.
struct ExercisePreviewSheet: View {
    var name: String
    var gifUrl: String?
    var targetMuscles: [String]
    var secondaryMuscles: [String]
    var exerciseId: String?
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(name).font(.title3.bold())
                ExerciseGIFView(urlString: gifUrl, exerciseId: exerciseId)
                    .frame(height: 280)
                MuscleChips(target: targetMuscles, secondary: secondaryMuscles)
                let steps = instructions
                if !steps.isEmpty {
                    Text("How to do it").font(.headline)
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        Text(step).font(.subheadline).foregroundStyle(Theme.subtext)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var instructions: [String] {
        guard let exerciseId else { return [] }
        let descriptor = FetchDescriptor<CachedExercise>(predicate: #Predicate { $0.exerciseId == exerciseId })
        return (try? context.fetch(descriptor).first?.instructions) ?? []
    }
}
