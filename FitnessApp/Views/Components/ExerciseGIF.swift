import SwiftUI
import UIKit
import ImageIO
import CryptoKit

enum ExerciseMedia {
    /// Custom exercises have no animation; library exercises can always look one up by id.
    static func hasAnimation(gifUrl: String?, exerciseId: String?) -> Bool {
        if gifUrl != nil { return true }
        guard let exerciseId else { return false }
        return !exerciseId.hasPrefix("custom-")
    }
}

/// Animated GIF from ExerciseDB. Falls back to looking the exercise up by id
/// when the saved link is missing or broken, and offers a retry on failure.
struct ExerciseGIFView: View {
    var urlString: String?
    var exerciseId: String? = nil
    @State private var image: UIImage?
    @State private var phase = Phase.loading
    @State private var attempt = 0

    private enum Phase { case loading, loaded, failed }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Theme.cardRaised)
            if let image {
                AnimatedImageView(image: image)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if phase == .loading && ExerciseMedia.hasAnimation(gifUrl: urlString, exerciseId: exerciseId) {
                ProgressView().tint(Theme.subtext)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2)
                    if phase == .failed {
                        Image(systemName: "arrow.clockwise").font(.caption2)
                    }
                }
                .foregroundStyle(Theme.subtext)
            }
        }
        // Simultaneous so a surrounding button still gets the tap.
        .simultaneousGesture(TapGesture().onEnded {
            if phase == .failed { attempt += 1 }
        })
        .task(id: "\(urlString ?? "")|\(exerciseId ?? "")|\(attempt)") {
            if image == nil { phase = .loading }
            let loaded = await GIFLoader.shared.image(for: urlString, exerciseId: exerciseId)
            if Task.isCancelled { return }
            image = loaded ?? image
            phase = image == nil ? .failed : .loaded
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

/// Downloads and decodes exercise GIFs.
/// - At most a few downloads run at once (lists of thumbnails used to trip the
///   free API's rate limit, which left blank tiles), with retries and backoff.
/// - Files are kept on disk so they show offline and load instantly next time.
/// - A broken or missing link is replaced by the exercise's current one from ExerciseDB.
actor GIFLoader {
    static let shared = GIFLoader()

    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var lookups: [String: Task<String?, Never>] = [:]
    private var failedLookups: [String: Date] = [:]
    private var resolved: [String: String]
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let maxConcurrent = 4
    private let directory: URL
    private static let resolvedKey = "gif.resolvedURLs"

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("ExerciseGIFs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        resolved = UserDefaults.standard.dictionary(forKey: Self.resolvedKey) as? [String: String] ?? [:]
    }

    func image(for urlString: String?, exerciseId: String? = nil) async -> UIImage? {
        let saved = Self.normalized(urlString)
        if let exerciseId, let fresh = resolved[exerciseId], fresh != saved, let image = await load(fresh) {
            return image
        }
        if let saved, let image = await load(saved) { return image }
        guard let exerciseId, !exerciseId.hasPrefix("custom-"),
              let fresh = await lookUp(exerciseId: exerciseId), fresh != saved else { return nil }
        return await load(fresh)
    }

    // MARK: Loading

    private func load(_ urlString: String) async -> UIImage? {
        if let cached = memory.object(forKey: urlString as NSString) { return cached }
        if let running = inFlight[urlString] { return await running.value }
        // Unstructured so a row scrolling away doesn't cancel a download others can reuse.
        let task = Task { await self.fetch(urlString) }
        inFlight[urlString] = task
        let image = await task.value
        inFlight[urlString] = nil
        if let image { memory.setObject(image, forKey: urlString as NSString, cost: Self.cost(of: image)) }
        return image
    }

    private func fetch(_ urlString: String) async -> UIImage? {
        let file = fileURL(for: urlString)
        if let data = try? Data(contentsOf: file), let image = await Self.decodeDetached(data) {
            return image
        }
        guard let url = URL(string: urlString) else { return nil }
        await acquire()
        defer { release() }
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000) }
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.setValue("image/gif,image/*", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request) else { continue }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 404 || status == 403 || status == 410 { return nil } // gone: let the id lookup try
            guard (200..<300).contains(status), let image = await Self.decodeDetached(data) else { continue }
            try? data.write(to: file, options: .atomic)
            return image
        }
        return nil
    }

    private func lookUp(exerciseId: String) async -> String? {
        if let fresh = resolved[exerciseId] { return fresh }
        if let failed = failedLookups[exerciseId], Date().timeIntervalSince(failed) < 120 { return nil }
        if let running = lookups[exerciseId] { return await running.value }
        let task = Task<String?, Never> {
            Self.normalized(try? await ExerciseDBClient.shared.exercise(id: exerciseId).gifUrl)
        }
        lookups[exerciseId] = task
        let fresh = await task.value
        lookups[exerciseId] = nil
        if let fresh {
            resolved[exerciseId] = fresh
            UserDefaults.standard.set(resolved, forKey: Self.resolvedKey)
        } else {
            failedLookups[exerciseId] = Date()
        }
        return fresh
    }

    // MARK: Concurrency limit

    private func acquire() async {
        if active < maxConcurrent {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            active -= 1
        } else {
            waiters.removeFirst().resume() // hand the slot straight over
        }
    }

    // MARK: Helpers

    private func fileURL(for urlString: String) -> URL {
        let digest = SHA256.hash(data: Data(urlString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".gif")
    }

    static func normalized(_ urlString: String?) -> String? {
        guard var value = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasPrefix("//") { value = "https:" + value }
        // iOS blocks plain http by default.
        if value.hasPrefix("http://") { value = "https://" + value.dropFirst("http://".count) }
        guard let url = URL(string: value), url.scheme == "https" else { return nil }
        return value
    }

    private static func cost(of image: UIImage) -> Int {
        let frames = max(image.images?.count ?? 1, 1)
        return Int(image.size.width * image.size.height * image.scale * image.scale) * 4 * frames
    }

    private static func decodeDetached(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { decode(data) }.value
    }

    /// Decodes every frame, downsampled so long lists of GIFs stay light on memory.
    private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 480
        ]
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
        if frames.count == 1 { return frames[0] }
        return frames.isEmpty ? nil : UIImage.animatedImage(with: frames, duration: duration)
    }
}
