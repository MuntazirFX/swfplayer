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

// MARK: - Web view + key injection
final class WebHolder {
    weak var web: WKWebView?
    func key(_ type: String, code: String, key: String) {
        let js = "(function(){var e=new KeyboardEvent('\(type)',{key:'\(key)',code:'\(code)',bubbles:true,cancelable:true});var t=document.querySelector('ruffle-player')||document;t.dispatchEvent(e);})();"
        web?.evaluateJavaScript(js)
    }
}

struct GameView: UIViewRepresentable {
    let holder: WebHolder
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(AppSchemeHandler(), forURLScheme: "app")
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        holder.web = wv
        wv.load(URLRequest(url: URL(string: "app://localhost/index.html")!))
        return wv
    }
    func updateUIView(_ wv: WKWebView, context: Context) {}
}

// MARK: - On-screen controls
struct KeyButton: View {
    var label: String = ""
    var icon: String? = nil
    let code: String
    let key: String
    var size: CGFloat = 58
    let holder: WebHolder
    @State private var down = false

    var body: some View {
        Group {
            if let icon = icon { Image(systemName: icon).font(.system(size: size * 0.38, weight: .bold)) }
            else { Text(label).font(.system(size: size * 0.30, weight: .bold)) }
        }
        .foregroundColor(.white)
        .frame(width: size, height: size)
        .background(Circle().fill(down ? Color.orange : Color.white.opacity(0.22)))
        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !down { down = true; holder.key("keydown", code: code, key: key) }
                }
                .onEnded { _ in
                    down = false; holder.key("keyup", code: code, key: key)
                }
        )
    }
}

struct DPad: View {
    let holder: WebHolder
    let wasd: Bool
    var body: some View {
        let s: CGFloat = 54
        VStack(spacing: 4) {
            KeyButton(icon: "arrowtriangle.up.fill", code: wasd ? "KeyW" : "ArrowUp",
                      key: wasd ? "w" : "ArrowUp", size: s, holder: holder)
            HStack(spacing: 4) {
                KeyButton(icon: "arrowtriangle.left.fill", code: wasd ? "KeyA" : "ArrowLeft",
                          key: wasd ? "a" : "ArrowLeft", size: s, holder: holder)
                Color.clear.frame(width: s, height: s)
                KeyButton(icon: "arrowtriangle.right.fill", code: wasd ? "KeyD" : "ArrowRight",
                          key: wasd ? "d" : "ArrowRight", size: s, holder: holder)
            }
            KeyButton(icon: "arrowtriangle.down.fill", code: wasd ? "KeyS" : "ArrowDown",
                      key: wasd ? "s" : "ArrowDown", size: s, holder: holder)
        }
    }
}

struct ActionPad: View {
    let holder: WebHolder
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                KeyButton(label: "Z", code: "KeyZ", key: "z", holder: holder)
                KeyButton(label: "X", code: "KeyX", key: "x", holder: holder)
            }
            HStack(spacing: 8) {
                KeyButton(label: "SPC", code: "Space", key: " ", holder: holder)
                KeyButton(label: "ENT", code: "Enter", key: "Enter", holder: holder)
            }
        }
    }
}

struct PlayerScreen: View {
    let name: String
    let onClose: () -> Void
    @AppStorage("controlsOn") private var controlsOn = true
    @AppStorage("wasd") private var wasd = false
    @State private var holder = WebHolder()

    private func roundIcon(_ system: String) -> some View {
        Image(systemName: system).foregroundColor(.white).padding(10)
            .background(Color.black.opacity(0.55)).clipShape(Circle())
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GameView(holder: holder).ignoresSafeArea()

            if controlsOn {
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        DPad(holder: holder, wasd: wasd)
                        Spacer()
                        ActionPad(holder: holder)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 24)
                }
            }

            VStack {
                HStack(spacing: 10) {
                    Button(action: onClose) { roundIcon("xmark") }
                    Spacer()
                    Button { wasd.toggle() } label: {
                        Text(wasd ? "WASD" : "ARROWS").font(.caption.bold()).foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Color.black.opacity(0.55)).clipShape(Capsule())
                    }
                    Button { controlsOn.toggle() } label: {
                        roundIcon(controlsOn ? "gamecontroller.fill" : "gamecontroller")
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8)
                Spacer()
            }
        }
        .statusBarHidden(true)
    }
}

// MARK: - Document picker
struct DocPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coord { Coord(onPick: onPick, onCancel: onCancel) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        p.allowsMultipleSelection = true
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    final class Coord: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: () -> Void
        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick; self.onCancel = onCancel
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
    }
}

extension URL: Identifiable { public var id: String { absoluteString } }
extension URL { var gameName: String { deletingPathExtension().lastPathComponent } }

// MARK: - Library
final class Library: ObservableObject {
    @Published var files: [URL] = []
    @Published var plays: [String: Int] = UserDefaults.standard.dictionary(forKey: "plays") as? [String: Int] ?? [:]
    @Published var last: [String: Double] = UserDefaults.standard.dictionary(forKey: "last") as? [String: Double] ?? [:]

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
    }
    func add(_ urls: [URL]) -> String {
        var msgs: [String] = []
        for u in urls {
            let ok = u.startAccessingSecurityScopedResource()
            defer { if ok { u.stopAccessingSecurityScopedResource() } }
            var name = u.lastPathComponent
            if !name.lowercased().hasSuffix(".swf") { name += ".swf" }
            let dest = dir.appendingPathComponent(name)
            do {
                let d = try Data(contentsOf: u)
                try d.write(to: dest, options: .atomic)
                msgs.append("OK: \(name)")
            } catch {
                msgs.append("Error: \(name): \(error.localizedDescription)")
            }
        }
        refresh()
        return msgs.joined(separator: "\n")
    }
    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refresh()
    }
    func recordPlay(_ url: URL) {
        let n = url.gameName
        plays[n, default: 0] += 1
        last[n] = Date().timeIntervalSince1970
        UserDefaults.standard.set(plays, forKey: "plays")
        UserDefaults.standard.set(last, forKey: "last")
    }
}

// MARK: - Menu
struct ContentView: View {
    @StateObject private var lib = Library()
    @AppStorage("sortMode") private var sortMode = 0
    @State private var picking = false
    @State private var query = ""
    @State private var playing: URL?
    @State private var info: String?
    @State private var deleteTarget: URL?

    private var sorted: [URL] {
        var list = lib.files
        if !query.isEmpty { list = list.filter { $0.gameName.localizedCaseInsensitiveContains(query) } }
        switch sortMode {
        case 1: return list.sorted { $0.gameName.lowercased() < $1.gameName.lowercased() }
        case 2: return list.sorted { (lib.plays[$0.gameName] ?? 0) > (lib.plays[$1.gameName] ?? 0) }
        default: return list.sorted { (lib.last[$0.gameName] ?? 0) > (lib.last[$1.gameName] ?? 0) }
        }
    }
    private var lastPlayed: URL? {
        lib.files.filter { lib.last[$0.gameName] != nil }
            .max { (lib.last[$0.gameName] ?? 0) < (lib.last[$1.gameName] ?? 0) }
    }
    private func play(_ url: URL) {
        GameStore.data = try? Data(contentsOf: url)
        lib.recordPlay(url)
        playing = url
    }
    private func color(_ name: String) -> Color {
        let h = name.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }
        return Color(hue: Double(h) / 360, saturation: 0.6, brightness: 0.8)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [Color(red: 0.08, green: 0.06, blue: 0.16), .black],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    (Text("SWF ").foregroundColor(.white) + Text("Player").foregroundColor(.orange))
                        .font(.system(size: 36, weight: .heavy))
                        .padding(.top, 12)

                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("Game search karo", text: $query)
                            .foregroundColor(.white).disableAutocorrection(true)
                    }
                    .padding(12).background(Color.white.opacity(0.08)).cornerRadius(14)

                    if let lp = lastPlayed, query.isEmpty {
                        Button { play(lp) } label: {
                            HStack {
                                Image(systemName: "play.circle.fill").font(.title)
                                VStack(alignment: .leading) {
                                    Text("Continue").font(.caption).opacity(0.8)
                                    Text(lp.gameName).font(.headline).lineLimit(1)
                                }
                                Spacer()
                            }
                            .foregroundColor(.white).padding(14)
                            .background(LinearGradient(colors: [.orange, Color(red: 0.9, green: 0.3, blue: 0.2)],
                                                       startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(16)
                        }
                    }

                    HStack {
                        Text("\(lib.files.count) games").font(.subheadline).foregroundColor(.gray)
                        Spacer()
                        Menu {
                            Button("Recently Played") { sortMode = 0 }
                            Button("Name") { sortMode = 1 }
                            Button("Most Played") { sortMode = 2 }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text(["Recent", "Name", "Most Played"][min(sortMode, 2)])
                            }
                            .font(.subheadline).foregroundColor(.orange)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.orange.opacity(0.15)).clipShape(Capsule())
                        }
                    }

                    if lib.files.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "gamecontroller").font(.system(size: 54)).foregroundColor(.gray)
                            Text("Koi game nahi hai").foregroundColor(.white).font(.headline)
                            Text("Neeche + dabake SWF files add karo").foregroundColor(.gray).font(.subheadline)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 80)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(sorted) { url in
                                let n = url.gameName
                                Button { play(url) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(LinearGradient(colors: [color(n), color(n).opacity(0.45)],
                                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                            Text(String(n.prefix(1)).uppercased())
                                                .font(.system(size: 44, weight: .heavy)).foregroundColor(.white.opacity(0.9))
                                        }
                                        .frame(height: 90)
                                        Text(n.replacingOccurrences(of: "_", with: " "))
                                            .font(.subheadline.bold()).foregroundColor(.white).lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Label("\(lib.plays[n] ?? 0) plays", systemImage: "play.fill")
                                            .font(.caption).foregroundColor(.orange)
                                    }
                                    .padding(10).background(Color.white.opacity(0.08)).cornerRadius(16)
                                }
                                .contextMenu {
                                    Button(role: .destructive) { deleteTarget = url } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 16)
            }

            Button { picking = true } label: {
                Image(systemName: "plus").font(.title.bold()).foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Circle()).shadow(color: .orange.opacity(0.5), radius: 10)
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $picking) {
            DocPicker(onPick: { urls in
                picking = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { info = lib.add(urls) }
            }, onCancel: { picking = false })
        }
        .alert("Import", isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
            Button("OK") {}
        } message: { Text(info ?? "") }
        .confirmationDialog("Ye game delete karna hai?",
                            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let t = deleteTarget { lib.remove(t) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        }
        .fullScreenCover(item: $playing) { url in
            PlayerScreen(name: url.gameName) { playing = nil }
        }
    }
}

@main struct SWFPlayerApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
