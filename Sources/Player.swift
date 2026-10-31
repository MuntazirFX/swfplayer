import SwiftUI
import WebKit

// MARK: - JS -> Swift bridge
final class ScriptBridge: NSObject, WKScriptMessageHandler {
    var onMessage: ((String) -> Void)?
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if let s = message.body as? String { onMessage?(s) }
    }
}

// MARK: - Orientation helper (iOS 16+, iPhone only)
enum Orient {
    static func set(_ mask: UIInterfaceOrientationMask) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        if #available(iOS 16.0, *) {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}

// MARK: - Per-game save backup (Flash SharedObjects live in localStorage)
enum SaveStore {
    private static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Saves")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private static func path(_ key: String) -> URL {
        dir.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    static func read(_ key: String) -> String {
        guard let s = try? String(contentsOf: path(key), encoding: .utf8),
              let d = s.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: d)) is [String: Any] else { return "{}" }
        return s
    }

    static func write(_ json: String, for key: String) {
        guard json != "{}", !json.isEmpty else { return }
        try? json.write(to: path(key), atomically: true, encoding: .utf8)
    }
}

// MARK: - Game config passed to the web page
struct GameConfig {
    var gid: String
    var scale: String
    var quality: String
    var size: CGSize
    var engine: String
    var fps: Int
    var showFps: Bool
    var showCursor: Bool
    var trackpad: Bool
    var dpr: String
    var renderer: String
}

// MARK: - Web view holder + JS helpers
final class WebHolder {
    weak var web: WKWebView?
    var onReady: (() -> Void)?
    var onStuck: (() -> Void)?

    func js(_ code: String) { web?.evaluateJavaScript(code, completionHandler: nil) }

    func key(_ type: String, code: String, key: String) {
        let script = "(function(){var e=new KeyboardEvent('\(type)',{key:'\(key)',code:'\(code)',bubbles:true,cancelable:true});var t=document.querySelector('ruffle-player')||document;t.dispatchEvent(e);})();"
        js(script)
    }

    func tap(code: String, key: String) {
        self.key("keydown", code: code, key: key)
        self.key("keyup", code: code, key: key)
    }

    func load(_ c: GameConfig) {
        var comps = URLComponents()
        comps.scheme = "app"
        comps.host = "localhost"
        comps.path = "/index.html"
        comps.queryItems = [
            URLQueryItem(name: "game", value: c.gid),
            URLQueryItem(name: "scale", value: c.scale),
            URLQueryItem(name: "quality", value: c.quality),
            URLQueryItem(name: "w", value: String(Int(c.size.width))),
            URLQueryItem(name: "h", value: String(Int(c.size.height))),
            URLQueryItem(name: "engine", value: c.engine),
            URLQueryItem(name: "fps", value: String(c.fps)),
            URLQueryItem(name: "showfps", value: c.showFps ? "1" : "0"),
            URLQueryItem(name: "cursor", value: c.showCursor ? "1" : "0"),
            URLQueryItem(name: "trackpad", value: c.trackpad ? "1" : "0"),
            URLQueryItem(name: "dpr", value: c.dpr),
            URLQueryItem(name: "renderer", value: c.renderer)
        ]
        guard let u = comps.url else { return }
        web?.load(URLRequest(url: u))
    }

    func setPaused(_ paused: Bool) { js(paused ? "window.pf&&pf.pause()" : "window.pf&&pf.play()") }
    func setMuted(_ muted: Bool) { js("window.pf&&pf.mute(\(muted))") }
    func setMode(_ mode: String) { js("window.pf&&pf.setMode('\(mode)')") }
    func setCursor(show: Bool, trackpad: Bool) { js("window.pf&&pf.setCursor(\(show),\(trackpad))") }
    func setFps(_ n: Int) { js("window.pf&&pf.setFps(\(n))") }
    func setShowFps(_ b: Bool) { js("window.pf&&pf.showFps(\(b))") }
    func setGain(_ g: Double) { js("window.pf&&pf.setGain(\(g))") }
    func moveCursor(dx: Double, dy: Double) { js("window.pf&&pf.moveBy(\(dx),\(dy))") }
    func mouse(down: Bool, button: Int) { js("window.pf&&pf.mouse('\(down ? "down" : "up")',\(button))") }

    func exportSaves(_ done: @escaping (String) -> Void) {
        guard let w = web else { done("{}"); return }
        w.evaluateJavaScript("window.pf?pf.exportSaves():'{}'") { res, _ in
            done((res as? String) ?? "{}")
        }
    }
}

struct GameView: UIViewRepresentable {
    let holder: WebHolder
    let config: GameConfig

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(AppSchemeHandler(), forURLScheme: "app")
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        let h = holder
        let bridge = ScriptBridge()
        bridge.onMessage = { [weak h] msg in
            if msg == "ready" { DispatchQueue.main.async { h?.onReady?() } }
            if msg == "stuck" { DispatchQueue.main.async { h?.onStuck?() } }
        }
        cfg.userContentController.add(bridge, name: "pf")

        let saves = SaveStore.read(config.gid)
        let script = WKUserScript(source: "window.__saves = \(saves);",
                                  injectionTime: .atDocumentStart, forMainFrameOnly: true)
        cfg.userContentController.addUserScript(script)

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        holder.web = wv
        holder.load(config)
        return wv
    }
    func updateUIView(_ wv: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeAllScriptMessageHandlers()
        uiView.configuration.userContentController.removeAllUserScripts()
        uiView.loadHTMLString("", baseURL: nil)
    }
}

// MARK: - Side bar item
struct SideItem: Identifiable {
    let id: String
    let icon: String
    let on: Bool
    let action: () -> Void
    var tint: String = "orange"
    var slashed: Bool = false
}

// MARK: - Player screen
struct PlayerScreen: View {
    let gameKey: String
    let name: String
    let gameSize: CGSize
    let needThumb: Bool
    let onThumb: (UIImage) -> Void
    let onClose: () -> Void

    @AppStorage("controlsOn") private var controlsOn = true
    @AppStorage("padOn") private var padOn = false
    @AppStorage("padLayout") private var padLayout = "simple"
    @AppStorage("mirror") private var mirror = false
    @AppStorage("dir8") private var dir8 = true
    @AppStorage("wasd") private var wasd = false
    @AppStorage("scaleMode") private var scaleMode = "auto"
    @AppStorage("quality") private var quality = "low"
    @AppStorage("resolution") private var resolution = "auto"
    @AppStorage("renderer") private var renderer = "auto"
    @AppStorage("engine") private var engine = "standard"
    @AppStorage("fpsCap") private var fpsCap = "0"
    @AppStorage("showFps") private var showFps = false
    @AppStorage("ctrlSize") private var ctrlSize = 58.0
    @AppStorage("ctrlOpacity") private var ctrlOpacity = 1.0
    @AppStorage("moveType") private var moveType = "dpad"
    @AppStorage("autoLandscape") private var autoLandscape = true
    @AppStorage("touchDirect") private var touchDirect = true
    @AppStorage("cursorSpeed") private var cursorSpeed = 9.0
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var pads = GamepadManager.shared

    @State private var holder = WebHolder()
    @State private var loading = true
    @State private var paused = false
    @State private var muted = false
    @State private var landscape = false
    @State private var showOptions = false
    @State private var showMapping = false
    @State private var pencil = false
    @State private var strokes: [Stroke] = []
    @State private var penIndex = 0
    @State private var stuckCount = 0
    @State private var stuckBanner = false
    @State private var confirmExit = false
    @State private var thumbDone = false
    @State private var slots: [SlotButtonModel] = []
    @State private var editing = false

    private let penColors: [Color] = [.red, .yellow, .green, .white, .cyan]
    private let autosave = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // MARK: helpers
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// Touch OFF = virtual mouse: direct taps on the game screen are blocked.
    private var cursorMode: Bool { !touchDirect }

    private var cursorVisible: Bool {
        if cursorMode { return true }
        if padOn && pads.config.rightStickMouse { return true }
        if !pads.names.isEmpty && (pads.config.leftStickMouse || pads.config.rightStickMouse) { return true }
        return false
    }

    private var syncKey: String {
        "\(fpsCap)|\(showFps)|\(cursorSpeed)|\(cursorMode)|\(cursorVisible)"
    }

    private func config() -> GameConfig {
        GameConfig(gid: gameKey, scale: scaleMode, quality: quality, size: gameSize,
                   engine: engine, fps: Int(fpsCap) ?? 0, showFps: showFps,
                   showCursor: cursorVisible, trackpad: cursorMode,
                   dpr: engine == "perf" ? "1" : resolution, renderer: renderer)
    }

    private func syncJS() {
        holder.setCursor(show: cursorVisible, trackpad: cursorMode)
        holder.setFps(Int(fpsCap) ?? 0)
        holder.setShowFps(showFps)
        holder.setGain(0.5 + cursorSpeed / 9.0)
        if muted { holder.setMuted(true) }
    }

    private func sideIcon(_ it: SideItem) -> some View {
        let fill: Color
        let fg: Color
        if it.on && it.tint == "green" {
            fill = Color(red: 0.05, green: 0.30, blue: 0.06)
            fg = Color(red: 0.55, green: 0.90, blue: 0.50)
        } else if it.on && it.tint == "yellow" {
            fill = Color(red: 0.36, green: 0.31, blue: 0.0)
            fg = Color(red: 0.95, green: 0.85, blue: 0.10)
        } else if it.on {
            fill = Color.orange
            fg = Color.black
        } else {
            fill = Color(white: 0.36, opacity: 0.88)
            fg = Color.black.opacity(0.85)
        }
        return ZStack {
            RoundedRectangle(cornerRadius: 8).fill(fill)
            Image(systemName: it.icon).font(.system(size: 15, weight: .semibold)).foregroundColor(fg)
            if it.slashed {
                Rectangle().fill(fg).frame(width: 2, height: 24).rotationEffect(.degrees(45))
            }
        }
        .frame(width: 32, height: 32)
    }

    private func snapshot() {
        guard let wv = holder.web else { return }
        wv.takeSnapshot(with: nil) { image, _ in
            if let image = image { onThumb(image) }
        }
    }

    private func saveNow() {
        holder.exportSaves { json in SaveStore.write(json, for: gameKey) }
    }

    private func reload() {
        loading = true
        paused = false
        holder.load(config())
    }

    private func setOrientation(_ land: Bool) {
        landscape = land
        Orient.set(land ? .landscape : .portrait)
    }

    private func requestExit() {
        holder.setPaused(true)
        confirmExit = true
    }

    private func leave() {
        holder.exportSaves { json in
            SaveStore.write(json, for: gameKey)
            finish()
        }
    }

    private func finish() {
        holder.onReady = nil
        holder.onStuck = nil
        GamepadManager.shared.detach()
        if landscape { Orient.set(.portrait) }
        onClose()
    }

    private func togglePencil() {
        pencil.toggle()
        if !pencil { strokes.removeAll() }
    }

    private var sideItems: [SideItem] {
        var a: [SideItem] = []
        a.append(SideItem(id: "exit", icon: "arrow.left", on: false, action: { requestExit() }))
        a.append(SideItem(id: "reload", icon: "arrow.clockwise", on: false, action: { reload() }))
        a.append(SideItem(id: "pause", icon: paused ? "play.fill" : "pause.fill", on: false,
                          action: { paused.toggle(); holder.setPaused(paused) }))
        a.append(SideItem(id: "options", icon: "gearshape.fill", on: false,
                          action: { showOptions.toggle() }))
        a.append(SideItem(id: "touch", icon: "hand.tap.fill", on: touchDirect,
                          action: { touchDirect.toggle() }, tint: "green"))
        a.append(SideItem(id: "mapping", icon: "gamecontroller.fill", on: false,
                          action: { showMapping = true }))
        a.append(SideItem(id: "pencil", icon: "pencil", on: pencil, action: { togglePencil() }))
        a.append(SideItem(id: "keyboard", icon: "keyboard", on: false,
                          action: { controlsOn.toggle() }, slashed: !controlsOn))
        a.append(SideItem(id: "pad", icon: "circle.grid.cross.fill", on: padOn,
                          action: { padOn.toggle() }, tint: "yellow"))
        return a
    }

    // MARK: overlays
    @ViewBuilder private var controlsOverlay: some View {
        ZStack {
            MovePad(holder: holder, moveType: moveType, wasd: wasd, dir8: dir8,
                    size: ctrlSize, mirror: mirror)
            SlotPads(slots: slots, size: ctrlSize, mirror: mirror, holder: holder)
        }
        .opacity(ctrlOpacity)
    }

    /// On-screen gamepad (same mapping as a real controller) and the virtual mouse.
    @ViewBuilder private var padLayers: some View {
        if padOn && !editing {
            PadOverlay(holder: holder, scale: ctrlSize / 58.0).opacity(ctrlOpacity)
        }
        if cursorMode && !padOn && !editing {
            CursorOverlay(holder: holder)
        }
    }

    private var sideBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 5) {
                    ForEach(sideItems) { it in
                        Button(action: it.action) { sideIcon(it) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 12).padding(.top, 10)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var optionsOverlay: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let al: Alignment = wide ? .trailing : .bottom
            ZStack(alignment: al) {
                Color.black.opacity(0.25).ignoresSafeArea()
                    .onTapGesture { showOptions = false }
                GameOptionsPanel(onClose: { showOptions = false },
                                 onReload: { reload() },
                                 onOrientation: { setOrientation($0) },
                                 onMapping: { showOptions = false; showMapping = true },
                                 onEditLayout: {
                                     showOptions = false
                                     controlsOn = true
                                     editing = true
                                 })
                    .frame(width: wide ? min(400, geo.size.width * 0.55) : nil)
                    .frame(maxHeight: wide ? geo.size.height - 16 : geo.size.height * 0.7)
                    .padding(8)
            }
        }
    }

    private var content: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GameView(holder: holder, config: config()).ignoresSafeArea()

            if loading {
                VStack(spacing: 12) {
                    ProgressView().progressViewStyle(.circular).tint(.orange)
                    Text(name).font(.caption).foregroundColor(.white.opacity(0.7))
                }
                .allowsHitTesting(false)
            }

            if controlsOn {
                if editing {
                    SlotEditor(slots: $slots, size: ctrlSize, mirror: mirror,
                               onReset: { slots = SlotLayouts.defaults(padLayout) },
                               onDone: {
                                   SlotStore.save(slots, gameKey, padLayout)
                                   editing = false
                               })
                } else {
                    controlsOverlay
                }
            }

            if pencil {
                AnnotationLayer(strokes: $strokes, color: penColors[min(penIndex, penColors.count - 1)])
                VStack {
                    Spacer()
                    AnnotationBar(strokes: $strokes, colorIndex: $penIndex, colors: penColors,
                                  onDone: { togglePencil() })
                        .padding(.bottom, 16)
                }
            }

            padLayers

            if stuckBanner {
                VStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("The game isn't responding. Try a lower render resolution, or switch the engine to Performance in Options.")
                            .font(.footnote).foregroundColor(.white).multilineTextAlignment(.center)
                        HStack(spacing: 16) {
                            Button("Reload") { stuckBanner = false; reload() }
                                .font(.subheadline.weight(.bold)).foregroundColor(.orange)
                            Button("Dismiss") { stuckBanner = false }
                                .font(.subheadline).foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(14)
                    .background(Color.black.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24).padding(.bottom, 24)
                }
            }

            if !editing { sideBar }

            if showOptions { optionsOverlay }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    var body: some View {
        content
            .statusBarHidden(true)
            .alert("Exit game?", isPresented: $confirmExit) {
                Button("Cancel", role: .cancel) { if !paused { holder.setPaused(false) } }
                Button("Leave game", role: .destructive) { leave() }
            } message: {
                Text("Your game is paused. Are you sure you want to leave?\nSave data will sync before exit.")
            }
            .sheet(isPresented: $showMapping) { GamepadMappingView(gameName: name) }
            .onAppear {
                GamepadManager.shared.attach(holder: holder, gameKey: gameKey)
                slots = SlotStore.load(gameKey, padLayout)
                holder.onStuck = {
                    if stuckCount == 0 {
                        stuckCount = 1
                        reload()
                    } else {
                        stuckBanner = true
                    }
                }
                holder.onReady = {
                    loading = false
                    syncJS()
                    if needThumb && !thumbDone {
                        thumbDone = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { snapshot() }
                    }
                }
                if autoLandscape {
                    if gameSize.width > gameSize.height * 1.05 {
                        landscape = true
                        Orient.set(.landscape)
                    } else if gameSize.height > gameSize.width * 1.05 {
                        Orient.set(.portrait)
                    }
                }
            }
            .onChange(of: scaleMode) { m in holder.setMode(m) }
            .onChange(of: padLayout) { l in slots = SlotStore.load(gameKey, l) }
            .onChange(of: syncKey) { _ in syncJS() }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    holder.setPaused(paused)
                } else {
                    holder.setPaused(true)
                    saveNow()
                }
            }
            .onReceive(autosave) { _ in saveNow() }
    }
}
