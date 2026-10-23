import Foundation

/// Dynamic matcher for ANY imported SWF game title. Searches Flashpoint's curated
/// Flash-game archive with several query strategies; no game title is hard-coded.
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

        // Search broadly in the archive using the filename/title and a smart search.
        // Results are merged and ranked, rather than accepting the first internet hit.
        var collected: [String: Entry] = [:]
        var lastError: Error?
        for mode in ["title", "smartSearch"] {
            do {
                for entry in try await search(name: name, mode: mode) {
                    let key = entry.id ?? normalized(entry.title ?? "")
                    if !key.isEmpty { collected[key] = entry }
                }
            } catch { lastError = error }
        }
        if collected.isEmpty, let lastError { throw lastError }

        let candidates = collected.values.filter {
            ($0.platform ?? "").localizedCaseInsensitiveContains("flash") &&
            ($0.library ?? "").localizedCaseInsensitiveContains("arcade")
        }
        let ranked = candidates.map { ($0, score(name, against: $0)) }.sorted { $0.1 > $1.1 }
        guard let (match, confidence) = ranked.first, confidence >= 0.72,
              let title = match.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            throw NSError(domain: "GameAI", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Is SWF game ka reliable match Flashpoint archive mein nahi mila. Koi galat details apply nahi ki gayin. Original game title se file rename karke dobara AI Match try karein."
            ])
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
        if !tags.isEmpty { details.append("Genre / tags: " + tags) }
        if !notes.isEmpty { details.append("Notes: " + notes) }
        details.append(String(format: "Match confidence: %.0f%%", confidence * 100))

        let logoURL: String? = {
            guard let id = match.id, id.count == 36 else { return nil }
            let a = String(id.prefix(2)), b = String(id.dropFirst(2).prefix(2))
            return "https://infinity.unstable.life/images/Logos/\(a)/\(b)/\(id).png?type=jpg"
        }()
        let source = (match.source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? match.source! : "https://flashpointarchive.org/datahub"
        return GameOnlineInfo(title: title, description: description, imageURL: logoURL,
                              sourceURL: source, pageTitle: title,
                              extract: details.joined(separator: "\n"))
    }

    private static func search(name: String, mode: String) async throws -> [Entry] {
        var components = URLComponents(url: api.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: mode, value: name),
            URLQueryItem(name: "platform", value: "Flash"),
            URLQueryItem(name: "fields", value: "id,title,alternateTitles,developer,publisher,platform,library,tags,originalDescription,source,releaseDate,notes"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "filter", value: "true")
        ]
        // A cleaned title can find entries whose filenames have punctuation or .swf suffixes.
        let cleaned = normalized(name)
        if mode == "smartSearch", !cleaned.isEmpty { items[0] = URLQueryItem(name: mode, value: cleaned) }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SWFPlayer/2.1 (multi-query Flash game metadata lookup)", forHTTPHeaderField: "User-Agent")
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
            .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
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
        if title == q + " game" || title == "the " + q { return 0.94 }
        if title.contains(q) || q.contains(title) || aliases.contains(where: { !$0.isEmpty && ($0.contains(q) || q.contains($0)) }) { return 0.84 }
        let qw = Set(q.split(separator: " ").map(String.init))
        let tw = Set(title.split(separator: " ").map(String.init))
        guard !qw.isEmpty, !tw.isEmpty else { return 0 }
        let overlap = Double(qw.intersection(tw).count) / Double(max(qw.count, tw.count))
        return overlap
    }
}
