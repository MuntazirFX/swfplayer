import SwiftUI
import UniformTypeIdentifiers

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
    @Published var info: [String: SWFInfo] = {
        if let d = UserDefaults.standard.data(forKey: "swfinfo"),
           let m = try? JSONDecoder().decode([String: SWFInfo].self, from: d) { return m }
        return [:]
    }()
    @Published var plays: [String: Int] = UserDefaults.standard.dictionary(forKey: "plays") as? [String: Int] ?? [:]
    @Published var last: [String: Double] = UserDefaults.standard.dictionary(forKey: "last") as? [String: Double] ?? [:]
    @Published var favs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "favs") ?? [])
    @Published var custom: [String: String] = UserDefaults.standard.dictionary(forKey: "customTitles") as? [String: String] ?? [:]
    @Published var thumbRev = 0

    let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Games")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    let thumbDir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Thumbs")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private let cache = NSCache<NSString, UIImage>()

    init() { refresh() }

    func refresh() {
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        files = all.filter { $0.pathExtension.lowercased() == "swf" }
        loadMissingInfo()
    }

    private func loadMissingInfo() {
        let missing = files.filter { info[$0.lastPathComponent] == nil }
        if missing.isEmpty { return }
        DispatchQueue.global(qos: .utility).async {
            var found: [String: SWFInfo] = [:]
            for u in missing { found[u.lastPathComponent] = SWFMeta.readInfo(u) }
            DispatchQueue.main.async {
                for (k, v) in found { self.info[k] = v }
                if let data = try? JSONEncoder().encode(self.info) {
                    UserDefaults.standard.set(data, forKey: "swfinfo")
                }
            }
        }
    }

    // MARK: titles / info
    func title(_ url: URL) -> String {
        if let c = custom[url.gameName], !c.isEmpty { return c }
        return info[url.lastPathComponent]?.title ?? SWFMeta.cleanName(url.gameName)
    }

    func subtitle(_ url: URL) -> String {
        var parts: [String] = []
        if let i = info[url.lastPathComponent], i.width > 0 { parts.append("\(i.width)×\(i.height)") }
        let sz = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if sz > 0 { parts.append(ByteCountFormatter.string(fromByteCount: Int64(sz), countStyle: .file)) }
        return parts.joined(separator: " · ")
    }

    func isLandscape(_ url: URL) -> Bool {
        if let i = info[url.lastPathComponent], i.width > 0 { return i.width > i.height }
        return false
    }

    func rename(_ url: URL, to name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        custom[url.gameName] = t.isEmpty ? nil : t
        UserDefaults.standard.set(custom, forKey: "customTitles")
    }

    // MARK: favorites
    func isFav(_ url: URL) -> Bool { favs.contains(url.gameName) }
    func toggleFav(_ url: URL) {
        let n = url.gameName
        if favs.contains(n) { favs.remove(n) } else { favs.insert(n) }
        UserDefaults.standard.set(Array(favs), forKey: "favs")
    }

    // MARK: thumbnails
    private func thumbPath(_ url: URL) -> URL { thumbDir.appendingPathComponent(url.gameName + ".jpg") }

    func hasThumb(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: thumbPath(url).path) }

    func thumb(_ url: URL) -> UIImage? {
        let key = url.gameName as NSString
        if let c = cache.object(forKey: key) { return c }
        guard let img = UIImage(contentsOfFile: thumbPath(url).path) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    func saveThumb(_ image: UIImage, for url: URL) {
        let maxSide: CGFloat = 480
        let longest = max(image.size.width, image.size.height, 1)
        let k = min(1, maxSide / longest)
        let size = CGSize(width: image.size.width * k, height: image.size.height * k)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = small.jpegData(compressionQuality: 0.75) else { return }
        try? data.write(to: thumbPath(url), options: .atomic)
        cache.removeObject(forKey: url.gameName as NSString)
        DispatchQueue.main.async { self.thumbRev += 1 }
    }

    func clearThumbs() {
        let all = (try? FileManager.default.contentsOfDirectory(at: thumbDir, includingPropertiesForKeys: nil)) ?? []
        for f in all { try? FileManager.default.removeItem(at: f) }
        cache.removeAllObjects()
        thumbRev += 1
    }

    var storageText: String {
        var total: Int64 = 0
        for u in files {
            total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    // MARK: add / remove / stats
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
                info[name] = nil
                msgs.append("OK: \(SWFMeta.cleanName((name as NSString).deletingPathExtension))")
            } catch {
                msgs.append("Error: \(name): \(error.localizedDescription)")
            }
        }
        refresh()
        return msgs.joined(separator: "\n")
    }

    func remove(_ url: URL) {
        let n = url.gameName
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: thumbPath(url))
        cache.removeObject(forKey: n as NSString)
        info[url.lastPathComponent] = nil
        if favs.contains(n) {
            favs.remove(n)
            UserDefaults.standard.set(Array(favs), forKey: "favs")
        }
        if custom[n] != nil {
            custom[n] = nil
            UserDefaults.standard.set(custom, forKey: "customTitles")
        }
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
