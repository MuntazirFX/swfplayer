import Foundation

/// Public-web metadata lookup for imported SWF games.
/// Uses Wikipedia's public search and summary endpoints; no API key is required.
struct GameOnlineInfo: Codable {
    var title: String
    var description: String
    var imageURL: String?
    var sourceURL: String
    var pageTitle: String
    var extract: String
}

enum GameAIService {
    private struct SearchResponse: Decodable {
        struct Query: Decodable {
            struct SearchItem: Decodable { let title: String }
            let search: [SearchItem]
        }
        let query: Query?
    }

    private struct Summary: Decodable {
        let title: String?
        let extract: String?
        let description: String?
        let thumbnail: ImageLink?
        let originalimage: ImageLink?
        let content_urls: ContentURLs?

        struct ImageLink: Decodable { let source: String? }
        struct ContentURLs: Decodable {
            let desktop: Link?
            struct Link: Decodable { let page: String? }
        }
    }

    static func findGame(named rawName: String) async throws -> GameOnlineInfo {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              var components = URLComponents(string: "https://en.wikipedia.org/w/api.php") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: name + " video game"),
            URLQueryItem(name: "srlimit", value: "5"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "origin", value: "*")
        ]
        guard let searchURL = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: searchURL)
        request.setValue("SWFPlayer/1.3 (online game metadata lookup)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let search = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard let result = search.query?.search.first else {
            throw NSError(domain: "GameAI", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "No online match was found. Try renaming the game to its original title and run AI Match again."])
        }

        let encodedTitle = result.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? result.title
        guard let summaryURL = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/" + encodedTitle) else {
            throw URLError(.badURL)
        }
        var summaryRequest = URLRequest(url: summaryURL)
        summaryRequest.setValue("SWFPlayer/1.3 (online game metadata lookup)", forHTTPHeaderField: "User-Agent")
        let (summaryData, summaryResponse) = try await URLSession.shared.data(for: summaryRequest)
        guard (summaryResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let summary = try JSONDecoder().decode(Summary.self, from: summaryData)
        let finalTitle = summary.title ?? result.title
        let extract = summary.extract ?? "No description was available from this source."
        let source = summary.content_urls?.desktop?.page ?? "https://en.wikipedia.org/wiki/" + encodedTitle
        return GameOnlineInfo(
            title: finalTitle,
            description: summary.description ?? "Game information",
            imageURL: summary.originalimage?.source ?? summary.thumbnail?.source,
            sourceURL: source,
            pageTitle: result.title,
            extract: extract
        )
    }
}
