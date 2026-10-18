import Foundation

/// Exercise as returned by the free ExerciseDB v1 API
/// (https://github.com/ExerciseDB/exercisedb-api, hosted at oss.exercisedb.dev).
/// Missing arrays decode as empty so partial responses still work.
struct ExerciseDTO: Codable, Hashable, Identifiable {
    var exerciseId: String
    var name: String
    var gifUrl: String?
    var bodyParts: [String]
    var equipments: [String]
    var targetMuscles: [String]
    var secondaryMuscles: [String]
    var instructions: [String]

    var id: String { exerciseId }

    init(exerciseId: String, name: String, gifUrl: String?, bodyParts: [String], equipments: [String],
         targetMuscles: [String], secondaryMuscles: [String], instructions: [String]) {
        self.exerciseId = exerciseId
        self.name = name
        self.gifUrl = gifUrl
        self.bodyParts = bodyParts
        self.equipments = equipments
        self.targetMuscles = targetMuscles
        self.secondaryMuscles = secondaryMuscles
        self.instructions = instructions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exerciseId = try c.decode(String.self, forKey: .exerciseId)
        name = try c.decode(String.self, forKey: .name)
        gifUrl = try c.decodeIfPresent(String.self, forKey: .gifUrl)
        bodyParts = try c.decodeIfPresent([String].self, forKey: .bodyParts) ?? []
        equipments = try c.decodeIfPresent([String].self, forKey: .equipments) ?? []
        targetMuscles = try c.decodeIfPresent([String].self, forKey: .targetMuscles) ?? []
        secondaryMuscles = try c.decodeIfPresent([String].self, forKey: .secondaryMuscles) ?? []
        instructions = try c.decodeIfPresent([String].self, forKey: .instructions) ?? []
    }

    /// Display name with a capital first letter ("dumbbell bench press" -> "Dumbbell bench press").
    var displayName: String { name.prefix(1).uppercased() + name.dropFirst() }

    func planned(defaultRestBetweenSets: Int, defaultRestAfterExercise: Int) -> PlannedExercise {
        var plan = PlannedExercise(exerciseId: exerciseId, name: displayName)
        plan.gifUrl = gifUrl
        plan.bodyParts = bodyParts
        plan.targetMuscles = targetMuscles
        plan.secondaryMuscles = secondaryMuscles
        plan.equipments = equipments
        plan.restBetweenSets = defaultRestBetweenSets
        plan.restAfterExercise = defaultRestAfterExercise
        return plan
    }
}

struct ExercisePage: Decodable {
    struct Meta: Decodable {
        var total: Int?
        var hasNextPage: Bool?
        var nextCursor: String?
    }

    var success: Bool?
    var meta: Meta?
    var data: [ExerciseDTO]
}

private struct ExerciseDetailResponse: Decodable {
    var data: ExerciseDTO
}

enum ExerciseDBError: LocalizedError {
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return code == 429 ? "The exercise library is busy. Try again in a minute."
                               : "The exercise library returned an error (\(code))."
        }
    }
}

/// Thin client for the free ExerciseDB v1 API. No API key is needed.
/// The API returns at most 25 items per page and pages with a cursor.
struct ExerciseDBClient {
    static let shared = ExerciseDBClient()
    static let baseURL = URL(string: "https://oss.exercisedb.dev/api/v1")!

    /// Body parts the API filters by.
    static let bodyParts = ["chest", "back", "shoulders", "upper arms", "lower arms",
                            "upper legs", "lower legs", "waist", "neck", "cardio"]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    /// Searches by name (and optionally body part). Returns full exercise
    /// records including target muscles.
    func search(name: String, bodyPart: String? = nil, cursor: String? = nil) async throws -> ExercisePage {
        var items = [URLQueryItem(name: "limit", value: "25")]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "name", value: trimmed)) }
        if let bodyPart { items.append(URLQueryItem(name: "bodyParts", value: bodyPart)) }
        if let cursor { items.append(URLQueryItem(name: "after", value: cursor)) }
        return try await get("exercises", query: items)
    }

    func exercise(id: String) async throws -> ExerciseDTO {
        let response: ExerciseDetailResponse = try await get("exercises/\(id)", query: [])
        return response.data
    }

    /// Downloads the whole free catalogue (about 1,500 exercises), page by page.
    func fetchAll(progress: @escaping (Int, Int) -> Void) async throws -> [ExerciseDTO] {
        var all: [ExerciseDTO] = []
        var cursor: String?
        repeat {
            let page = try await search(name: "", cursor: cursor)
            all.append(contentsOf: page.data)
            progress(all.count, page.meta?.total ?? all.count)
            cursor = (page.meta?.hasNextPage ?? false) ? page.meta?.nextCursor : nil
            try await Task.sleep(nanoseconds: 250_000_000) // be gentle with the free API
        } while cursor != nil && !Task.isCancelled
        return all
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ExerciseDBError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
