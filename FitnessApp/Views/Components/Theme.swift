import SwiftUI
import UIKit
import SwiftData

/// Dark blue theme used across the iPhone app.
enum Theme {
    // Higher-contrast dark blue: a deeper base, lighter cards, a brighter accent
    // and brighter secondary text, so cards and labels stand out clearly.
    static let background = Color(red: 0.020, green: 0.051, blue: 0.118)   // #050D1E deepest navy
    static let card = Color(red: 0.090, green: 0.188, blue: 0.353)         // #17305A
    static let cardRaised = Color(red: 0.141, green: 0.271, blue: 0.494)   // #24457E
    static let accent = Color(red: 0.400, green: 0.640, blue: 1.0)         // #66A3FF
    /// White highlight surfaces and buttons, with navy text on them.
    static let highlight = Color.white
    static let onHighlight = Color(red: 0.020, green: 0.051, blue: 0.118)  // navy text on white
    /// Outline that lifts cards off the navy background.
    static let outline = Color.white.opacity(0.22)
    /// Secondary and tertiary text, brighter than the system grays on navy.
    static let secondaryText = Color.white.opacity(0.78)
    static let tertiaryText = Color.white.opacity(0.6)

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
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor.white.withAlphaComponent(0.6)
            item.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.6)]
            item.selected.iconColor = .white
            item.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
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
            .listRowSeparatorTint(Theme.outline)
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
        .disabled(gifUrl == nil && !GIFLoader.canLookUp(exerciseId))
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
                        Text(step).font(.subheadline).foregroundStyle(Theme.secondaryText)
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
