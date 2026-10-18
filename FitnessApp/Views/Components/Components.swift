import SwiftUI
import UIKit
import ImageIO

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
            .background(filled ? color : color.opacity(0.25), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(filled ? 0 : 0.6), lineWidth: 1))
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

/// Animated exercise GIF, decoded with ImageIO and cached in memory and on disk.
/// Pass `exerciseId` so a missing or broken link can be looked up again.
struct ExerciseGIFView: View {
    var urlString: String?
    var exerciseId: String? = nil
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.white)
            if let image {
                AnimatedImageView(image: image)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if failed || (urlString == nil && !GIFLoader.canLookUp(exerciseId)) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.onHighlight.opacity(0.45))
            } else {
                ProgressView().tint(Theme.onHighlight)
            }
        }
        .task(id: "\(urlString ?? "")|\(exerciseId ?? "")") {
            failed = false
            image = await GIFLoader.shared.image(for: urlString, exerciseId: exerciseId)
            failed = image == nil
        }
    }
}

private struct AnimatedImageView: UIViewRepresentable {
    var image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .white
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if view.image !== image { view.image = image }
        view.startAnimating()
    }
}

/// Loads exercise GIFs. Fixes the usual reasons a GIF did not show:
/// http links (blocked by iOS), links with spaces, a dead link stored with an
/// old session (looked up again by exercise id), large GIFs decoded at full
/// size, and the same GIF downloaded many times at once.
actor GIFLoader {
    static let shared = GIFLoader()
    private static let mediaBase = "https://static.exercisedb.dev/media/"

    private var cache: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 20_000_000, diskCapacity: 300_000_000)
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    /// Library exercises can be looked up by id; custom ones have no GIF.
    nonisolated static func canLookUp(_ exerciseId: String?) -> Bool {
        guard let exerciseId, !exerciseId.isEmpty else { return false }
        return !exerciseId.hasPrefix("custom-")
    }

    func image(for urlString: String?, exerciseId: String? = nil) async -> UIImage? {
        let key = urlString ?? exerciseId ?? ""
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        if let running = inFlight[key] { return await running.value }
        let task = Task { await self.load(urlString: urlString, exerciseId: exerciseId) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { cache[key] = image }
        return image
    }

    private func load(urlString: String?, exerciseId: String?) async -> UIImage? {
        var candidates: [URL] = []
        if let url = Self.normalized(urlString) { candidates.append(url) }
        if Self.canLookUp(exerciseId), let exerciseId,
           let url = URL(string: Self.mediaBase + exerciseId + ".gif"), !candidates.contains(url) {
            candidates.append(url)
        }
        for url in candidates {
            if let image = await fetch(url) { return image }
        }
        // Last try: ask the library for the exercise's current link.
        if Self.canLookUp(exerciseId), let exerciseId,
           let fresh = try? await ExerciseDBClient.shared.exercise(id: exerciseId),
           let url = Self.normalized(fresh.gifUrl), !candidates.contains(url) {
            return await fetch(url)
        }
        return nil
    }

    private func fetch(_ url: URL) async -> UIImage? {
        for attempt in 0..<2 {
            if let result = try? await session.data(from: url) {
                let (data, response) = result
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                if (200..<300).contains(status), let image = Self.decode(data) { return image }
                if status == 404 { return nil }
            }
            if attempt == 0 { try? await Task.sleep(nanoseconds: 800_000_000) }
        }
        return nil
    }

    static func normalized(_ raw: String?) -> URL? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("//") { text = "https:" + text }
        if text.hasPrefix("http://") { text = "https://" + text.dropFirst("http://".count) }
        if let url = URL(string: text) { return url }
        return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:))
    }

    /// Decodes every frame, scaled down to at most 400 px, so long lists of
    /// GIFs don't run out of memory.
    private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let count = CGImageSourceGetCount(source)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard count > 1 else {
            if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) { return UIImage(cgImage: cg) }
            return UIImage(data: data)
        }
        var frames: [UIImage] = []
        var duration: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, i, options as CFDictionary)
                    ?? CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            duration += delay < 0.02 ? 0.1 : delay
        }
        guard !frames.isEmpty else { return UIImage(data: data) }
        return UIImage.animatedImage(with: frames, duration: duration)
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
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack(alignment: .top) {
                Image(systemName: suggestion.action.symbol)
                    .foregroundStyle(color)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.headline).font(.subheadline.bold())
                    Text(suggestion.reason).font(.caption).foregroundStyle(Theme.secondaryText)
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
        .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.5), lineWidth: 1))
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
                Text("No muscles yet. Add an exercise.").foregroundStyle(Theme.secondaryText)
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
                            .foregroundStyle(Theme.secondaryText)
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
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            if !groups.isEmpty {
                Text("Counts working sets: target muscles count 1, secondary muscles count ½.")
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
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
                Text(detail).font(.caption2).foregroundStyle(Theme.secondaryText)
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
