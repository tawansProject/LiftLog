import SwiftUI
import UIKit
import SwiftData

/// Dark blue theme used across the iPhone app.
enum Theme {
    static let background = Color(red: 0.039, green: 0.090, blue: 0.180)   // #0A1730 deep navy
    static let card = Color(red: 0.075, green: 0.157, blue: 0.290)         // #13284A
    static let cardRaised = Color(red: 0.110, green: 0.216, blue: 0.392)   // #1C3764
    static let accent = Color(red: 0.302, green: 0.553, blue: 1.0)         // #4D8DFF

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
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
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
            ExerciseGIFView(urlString: gifUrl)
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(gifUrl == nil)
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
                ExerciseGIFView(urlString: gifUrl)
                    .frame(height: 280)
                MuscleChips(target: targetMuscles, secondary: secondaryMuscles)
                let steps = instructions
                if !steps.isEmpty {
                    Text("How to do it").font(.headline)
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        Text(step).font(.subheadline).foregroundStyle(.secondary)
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
