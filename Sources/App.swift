import SwiftUI
import WebKit
import UniformTypeIdentifiers

enum GameStore { static var data: Data? }

final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var path = url.path
        if path == "/" || path.isEmpty { path = "/index.html" }
        var data: Data?
        if path == "/game.swf" {
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

struct GameView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(AppSchemeHandler(), forURLScheme: "app")
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.isScrollEnabled = false
        wv.load(URLRequest(url: URL(string: "app://localhost/index.html")!))
        return wv
    }
    func updateUIView(_ wv: WKWebView, context: Context) {}
}

extension URL: Identifiable { public var id: String { absoluteString } }

final class Library: ObservableObject {
    @Published var files: [URL] = []
    let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Games")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    init() { refresh() }
    func refresh() {
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        files = all.filter { $0.pathExtension.lowercased() == "swf" }
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
    }
    func add(_ urls: [URL]) {
        for u in urls {
            let ok = u.startAccessingSecurityScopedResource()
            defer { if ok { u.stopAccessingSecurityScopedResource() } }
            let dest = dir.appendingPathComponent(u.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: u, to: dest)
        }
        refresh()
    }
    func remove(_ offsets: IndexSet, from list: [URL]) {
        for i in offsets { try? FileManager.default.removeItem(at: list[i]) }
        refresh()
    }
}

struct ContentView: View {
    @StateObject private var lib = Library()
    @State private var picking = false
    @State private var query = ""
    @State private var playing: URL?

    var filtered: [URL] {
        query.isEmpty ? lib.files : lib.files.filter {
            $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(filtered) { url in
                    Button {
                        GameStore.data = try? Data(contentsOf: url)
                        playing = url
                    } label: {
                        HStack {
                            Image(systemName: "gamecontroller.fill")
                            Text(url.deletingPathExtension().lastPathComponent)
                        }
                    }
                }
                .onDelete { lib.remove($0, from: filtered) }
            }
            .overlay {
                if lib.files.isEmpty {
                    Text("Koi game nahi hai.\nUpar + dabake SWF files add karo.")
                        .multilineTextAlignment(.center).foregroundColor(.secondary)
                }
            }
            .searchable(text: $query)
            .navigationTitle("Games")
            .toolbar {
                Button { picking = true } label: { Image(systemName: "plus") }
            }
        }
        .navigationViewStyle(.stack)
        .fileImporter(isPresented: $picking,
                      allowedContentTypes: [UTType(filenameExtension: "swf") ?? .data, .data],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { lib.add(urls) }
        }
        .fullScreenCover(item: $playing) { _ in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                GameView().ignoresSafeArea()
                Button { playing = nil } label: {
                    Image(systemName: "xmark").padding(10)
                        .background(.black.opacity(0.5)).clipShape(Circle())
                }.padding(8).foregroundColor(.white)
            }
        }
    }
}

@main struct SWFPlayerApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
