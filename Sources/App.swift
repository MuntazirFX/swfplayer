import SwiftUI

enum ActiveSheet: Identifiable {
    case picker, settings, rename(URL)
    var id: String {
        switch self {
        case .picker: return "picker"
        case .settings: return "settings"
        case .rename(let u): return "rename-" + u.absoluteString
        }
    }
}

// MARK: - Menu
struct ContentView: View {
    @StateObject private var lib = Library()
    @AppStorage("sortMode") private var sortMode = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: ActiveSheet?
    @State private var query = ""
    @State private var favOnly = false
    @State private var playing: URL?
    @State private var info: String?
    @State private var deleteTarget: URL?
    @State private var showWeb = false

    private var sorted: [URL] {
        var list = lib.files
        if favOnly { list = list.filter { lib.isFav($0) } }
        if !query.isEmpty { list = list.filter { lib.title($0).localizedCaseInsensitiveContains(query) } }
        switch sortMode {
        case 1: return list.sorted { lib.title($0).lowercased() < lib.title($1).lowercased() }
        case 2: return list.sorted { (lib.plays[$0.gameName] ?? 0) > (lib.plays[$1.gameName] ?? 0) }
        default: return list.sorted { (lib.last[$0.gameName] ?? 0) > (lib.last[$1.gameName] ?? 0) }
        }
    }
    private var countText: String {
        let n = sorted.count
        let base = n == 1 ? "1 game" : "\(n) games"
        return favOnly ? base + " · favorites" : base
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

    @ViewBuilder
    private func card(_ url: URL) -> some View {
        let t = lib.title(url)
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if let img = lib.thumb(url) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [color(t), color(t).opacity(0.45)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        Text(String(t.prefix(1)).uppercased())
                            .font(.system(size: 44, weight: .heavy)).foregroundColor(.white.opacity(0.9))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 90)
                .clipped()
                .cornerRadius(12)

                if lib.isFav(url) {
                    Image(systemName: "heart.fill").font(.caption).foregroundColor(.red).padding(6)
                }
            }
            Text(t)
                .font(.subheadline.bold()).foregroundColor(.white).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(lib.subtitle(url))
                .font(.caption).foregroundColor(.gray).lineLimit(1)
        }
        .padding(10).background(Color.white.opacity(0.08)).cornerRadius(16)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [Color(red: 0.08, green: 0.06, blue: 0.16), .black],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        (Text("SWF ").foregroundColor(.white) + Text("Player").foregroundColor(.orange))
                            .font(.system(size: 36, weight: .heavy))
                        Spacer()
                        HStack(spacing: 10) {
                            Button { showWeb = true } label: {
                                Image(systemName: "globe").foregroundColor(.orange)
                                    .padding(10).background(Color.white.opacity(0.08)).clipShape(Circle())
                            }
                            Button { sheet = .settings } label: {
                                Image(systemName: "gearshape.fill").foregroundColor(.gray)
                                    .padding(10).background(Color.white.opacity(0.08)).clipShape(Circle())
                            }
                        }
                    }
                    .padding(.top, 12)
                    .fullScreenCover(isPresented: $showWeb) {
                        WebGamesView(onClose: { showWeb = false })
                    }

                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("Search games", text: $query)
                            .foregroundColor(.white).disableAutocorrection(true)
                    }
                    .padding(12).background(Color.white.opacity(0.08)).cornerRadius(14)

                    HStack {
                        Text(countText).font(.subheadline).foregroundColor(.gray)
                        Spacer()
                        Menu {
                            Button("Recently Played") { sortMode = 0 }
                            Button("Name") { sortMode = 1 }
                            Button("Most Played") { sortMode = 2 }
                            Button { favOnly.toggle() } label: {
                                Label("Favorites only", systemImage: favOnly ? "checkmark" : "heart")
                            }
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
                            Text("No games yet").foregroundColor(.white).font(.headline)
                            Text("Tap + to add SWF files").foregroundColor(.gray).font(.subheadline)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 80)
                    } else if sorted.isEmpty {
                        Text("No results")
                            .foregroundColor(.gray).font(.subheadline)
                            .frame(maxWidth: .infinity).padding(.top, 60)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(sorted) { url in
                                Button { play(url) } label: { card(url) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button { play(url) } label: { Label("Play", systemImage: "play.fill") }
                                        Button { lib.toggleFav(url) } label: {
                                            Label(lib.isFav(url) ? "Remove from Favorites" : "Add to Favorites",
                                                  systemImage: lib.isFav(url) ? "heart.slash" : "heart")
                                        }
                                        Button { sheet = .rename(url) } label: { Label("Rename", systemImage: "pencil") }
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

            Button { sheet = .picker } label: {
                Image(systemName: "plus").font(.title.bold()).foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Circle()).shadow(color: .orange.opacity(0.5), radius: 10)
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $sheet) { s in
            switch s {
            case .picker:
                DocPicker(onPick: { urls in
                    sheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { info = lib.add(urls) }
                }, onCancel: { sheet = nil })
            case .settings:
                SettingsView(lib: lib)
            case .rename(let url):
                RenameSheet(initial: lib.title(url)) { new in lib.rename(url, to: new) }
            }
        }
        .alert("Import", isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
            Button("OK") {}
        } message: { Text(info ?? "") }
        .confirmationDialog("Delete this game?",
                            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let t = deleteTarget { lib.remove(t) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        }
        .fullScreenCover(item: $playing) { url in
            PlayerScreen(gameKey: url.gameName,
                         name: lib.title(url),
                         gameSize: lib.gameSize(url),
                         needThumb: !lib.hasThumb(url),
                         onThumb: { img in lib.saveThumb(img, for: url) },
                         onClose: { playing = nil })
        }
        .onOpenURL { url in info = lib.add([url]) }
        .onChange(of: scenePhase) { phase in
            if phase == .active { lib.refresh() }
        }
    }
}

@main struct SWFPlayerApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
