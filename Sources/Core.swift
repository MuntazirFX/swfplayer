import SwiftUI
import WebKit
import UniformTypeIdentifiers

enum GameStore { static var data: Data? }

// MARK: - Local server for Ruffle + game
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var path = url.path
        if path == "/" || path.isEmpty { path = "/index.html" }
        var data: Data?
        if path == "/game.swf" || (path.hasPrefix("/g/") && path.lowercased().hasSuffix(".swf")) {
            data = GameStore.data
        } else if let base = Bundle.main.resourceURL?.appendingPathComponent("www") {
            data = try? Data(contentsOf: base.appendingPathComponent(path))
        }
        guard let body = data else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let ext = (path as NSString).pathExtension.lowercased()
        let mime = ["html": "text/html", "js": "text/javascript", "wasm": "application/wasm",
                    "json": "application/json", "swf": "application/x-shockwave-flash"][ext] ?? "application/octet-stream"
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mime, "Content-Length": "\(body.count)",
                           "Access-Control-Allow-Origin": "*"])!
        task.didReceive(resp); task.didReceive(body); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// MARK: - SWF metadata (auto title, size, version)
struct SWFInfo: Codable {
    var title: String
    var width: Int
    var height: Int
    var version: Int
}

enum SWFMeta {
    private static let small: Set<String> = ["of", "the", "and", "a", "an", "in", "on", "vs", "to", "for"]

    static func cleanName(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(of: "\\(\\d+\\)", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[_\\-+]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        var words: [String] = []
        for (i, w) in s.split(separator: " ").enumerated() {
            let word = String(w)
            if word != word.lowercased() { words.append(word); continue }
            if i > 0 && small.contains(word) { words.append(word); continue }
            words.append(word.prefix(1).uppercased() + word.dropFirst())
        }
        let out = words.joined(separator: " ")
        return out.isEmpty ? raw : out
    }

    static func readInfo(_ url: URL) -> SWFInfo {
        let fallback = cleanName(url.deletingPathExtension().lastPathComponent)
        guard let data = try? Data(contentsOf: url), data.count > 16 else {
            return SWFInfo(title: fallback, width: 0, height: 0, version: 0)
        }
        let version = Int(data[3])
        var bodyData = Data()
        if data[0] == 0x46 {
            bodyData = data.subdata(in: 8..<data.count)
        } else if data[0] == 0x43 {
            let comp = data.subdata(in: 10..<(data.count - 4))
            if let d = try? (comp as NSData).decompressed(using: .zlib) { bodyData = d as Data }
        }
        let body = bodyData

        var w = 0, h = 0
        if body.count > 20 {
            let n = Int(body[0] >> 3)
            if n > 0 && n < 31 && 5 + n * 4 <= body.count * 8 {
                func bitsAt(_ pos: Int, _ cnt: Int) -> Int {
                    var v = 0
                    for i in 0..<cnt {
                        let p = pos + i
                        let byte = Int(body[p / 8])
                        v = (v << 1) | ((byte >> (7 - p % 8)) & 1)
                    }
                    return v
                }
                let xmin = bitsAt(5, n), xmax = bitsAt(5 + n, n)
                let ymin = bitsAt(5 + 2 * n, n), ymax = bitsAt(5 + 3 * n, n)
                w = (xmax - xmin) / 20
                h = (ymax - ymin) / 20
            }
        }

        var title = fallback
        if let t = xmpTitle(in: body) { title = t }
        return SWFInfo(title: title, width: w, height: h, version: version)
    }

    private static func xmpTitle(in body: Data) -> String? {
        guard let r = body.range(of: Data("<dc:title>".utf8)) else { return nil }
        let end = min(body.count, r.upperBound + 800)
        let chunk = String(decoding: body.subdata(in: r.lowerBound..<end), as: UTF8.self)
        let patterns = ["<dc:title>.*?<rdf:li[^>]*>(.*?)</rdf:li>", "<dc:title>(.*?)</dc:title>"]
        let bad: Set<String> = ["", "untitled", "untitled-1", "untitled document", "unknown", "adobe flash", "flash"]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators]),
                  let m = re.firstMatch(in: chunk, range: NSRange(chunk.startIndex..., in: chunk)),
                  m.numberOfRanges > 1,
                  let rr = Range(m.range(at: 1), in: chunk) else { continue }
            var t = String(chunk[rr]).trimmingCharacters(in: .whitespacesAndNewlines)
            t = t.replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&quot;", with: "\"")
            if !t.contains("<") && !bad.contains(t.lowercased()) && t.count < 80 { return t }
        }
        return nil
    }
}
