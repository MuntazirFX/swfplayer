import Foundation

/// Matches imported SWF files against Flashpoint's curated game database.
/// A general encyclopedia result is never accepted as a game match.
struct GameOnlineInfo: Codable {
    var title: String
    var description: String
    var imageURL: String?
    var sourceURL: String
    var pageTitle: String
    var extract: String
}

enum GameAIService {
    private static let api = URL(string: "https://db-api.unstable.life")!

    private struct Entry: Decodable {
        let id: String?
        let title: String?
        let alternateTitles: String?
        let developer: String?
        let publisher: String?
        let platform: String?
        let library: String?
        let tags: [String]?
        let originalDescription: String?
        let source: String?
        let releaseDate: String?
        let notes: String?
    }

    static func findGame(named rawName: String) async throws -> GameOnlineInfo {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw URLError(.badURL) }

        // Search curated Flashpoint metadata, constrained to Flash and game entries.
        let candidates = try await search(name: name)
        let games = candidates.filter {
            ($0.platform ?? "").localizedCaseInsensitiveContains("flash") &&
            ($0.library ?? "").localizedCaseInsensitiveContains("arcade")
        }
        let ranked = games.map { ($0, score(name, against: $0)) }.sorted { $0.1 > $1.1 }

        guard let (match, confidence) = ranked.first, confidence >= 0.78 else {
            throw NSError(domain: "GameAI", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Flashpoint mein is SWF ke liye reliable Flash-game match nahi mila. Galat game ki details apply nahi ki gayin. SWF ko original game title se rename karke dobara AI Match chalayein."
            ])
        }
        guard let title = match.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            throw URLError(.cannotParseResponse)
        }

        let developer = clean(match.developer)
        let publisher = clean(match.publisher)
        let tags = (match.tags ?? []).joined(separator: ", ")
        let originalDescription = clean(match.originalDescription)
        let notes = clean(match.notes)
        let description = originalDescription.isEmpty
            ? "Flashpoint archived Flash game.\n\(tags.isEmpty ? "Genre/tags not listed." : "Tags: " + tags)"
            : originalDescription
        var details: [String] = []
        if !developer.isEmpty { details.append("Developer: " + developer) }
        if !publisher.isEmpty { details.append("Publisher: " + publisher) }
        if let date = match.releaseDate, !date.isEmpty { details.append("Release date: " + date) }
        if !tags.isEmpty { details.append("Tags: " + tags) }
        if !notes.isEmpty { details.append("Notes: " + notes) }
        let extract = details.isEmpty ? "Matched in Flashpoint's curated Flash archive." : details.joined(separator: "\n")

        let logoURL: String? = {
            guard let id = match.id, id.count == 36 else { return nil }
            let a = String(id.prefix(2)), b = String(id.dropFirst(2).prefix(2))
            return "https://infinity.unstable.life/images/Logos/\(a)/\(b)/\(id).png?type=jpg"
        }()
        let source = (match.source?.isEmpty == false) ? match.source! : "https://flashpointarchive.org/datahub"
        return GameOnlineInfo(title: title, description: description, imageURL: logoURL,
                              sourceURL: source, pageTitle: title, extract: extract)
    }

    private static func search(name: String) async throws -> [Entry] {
        var components = URLComponents(url: api.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "title", value: name),
            URLQueryItem(name: "platform", value: "Flash"),
            URLQueryItem(name: "fields", value: "id,title,alternateTitles,developer,publisher,platform,library,tags,originalDescription,source,releaseDate,notes"),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "filter", value: "true")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SWFPlayer/2.0 (Flashpoint curated metadata lookup)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([Entry].self, from: data)
    }

    private static func clean(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: #"\.(swf|flash)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func score(_ query: String, against entry: Entry) -> Double {
        let q = normalized(query)
        let title = normalized(entry.title ?? "")
        let aliases = (entry.alternateTitles ?? "").components(separatedBy: ";").map { normalized($0) }
        guard !q.isEmpty, !title.isEmpty else { return 0 }
        if q == title || aliases.contains(q) { return 1.0 }
        if title == q + " game" || title == "the " + q { return 0.92 }

        // Avoid accepting a vague one-word filename just because it occurs in a longer title.
        let qWords = Set(q.split(separator: " ").map(String.init))
        let titleWords = Set(title.split(separator: " ").map(String.init))
        if qWords.count >= 2 && (title.contains(q) || q.contains(title) || aliases.contains(where: { !$0.isEmpty && $0 == q })) {
            return 0.82
        }
        guard qWords.count >= 2, !titleWords.isEmpty else { return 0 }
        return Double(qWords.intersection(titleWords).count) / Double(max(qWords.count, titleWords.count))
    }
}
