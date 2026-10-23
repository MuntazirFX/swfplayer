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

// MARK: - Web view + key injection
final class WebHolder {
    weak var web: WKWebView?
    var onReady: (() -> Void)?

    func js(_ code: String) { web?.evaluateJavaScript(code, completionHandler: nil) }

    func key(_ type: String, code: String, key: String) {
        let script = "(function(){var e=new KeyboardEvent('\(type)',{key:'\(key)',code:'\(code)',bubbles:true,cancelable:true});var t=document.querySelector('ruffle-player')||document;t.dispatchEvent(e);})();"
        js(script)
    }

    func load(scale: String, quality: String, size: CGSize) {
        let w = Int(size.width), h = Int(size.height)
        guard let u = URL(string: "app://localhost/index.html?scale=\(scale)&quality=\(quality)&w=\(w)&h=\(h)") else { return }
        web?.load(URLRequest(url: u))
    }

    func setMode(_ mode: String) { js("window.pf&&pf.setMode('\(mode)')") }

    func setPaused(_ paused: Bool) { js(paused ? "window.pf&&pf.pause()" : "window.pf&&pf.play()") }
    func setMuted(_ muted: Bool) { js("window.pf&&pf.mute(\(muted))") }
}

struct GameView: UIViewRepresentable {
    let holder: WebHolder
    let scale: String
    let quality: String
    let size: CGSize

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(AppSchemeHandler(), forURLScheme: "app")
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        let h = holder
        let bridge = ScriptBridge()
        bridge.onMessage = { [weak h] msg in
            if msg == "ready" { DispatchQueue.main.async { h?.onReady?() } }
        }
        cfg.userContentController.add(bridge, name: "pf")

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        holder.web = wv
        holder.load(scale: scale, quality: quality, size: size)
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
    @AppStorage("haptics") private var haptics = true
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
                    if !down {
                        down = true
                        if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                        holder.key("keydown", code: code, key: key)
                    }
                }
                .onEnded { _ in
                    down = false
                    holder.key("keyup", code: code, key: key)
                }
        )
    }
}

struct DPad: View {
    let holder: WebHolder
    let wasd: Bool
    let size: CGFloat
    var body: some View {
        let s = size
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
    let size: CGFloat
    let extra: Bool
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                KeyButton(label: "Z", code: "KeyZ", key: "z", size: size, holder: holder)
                KeyButton(label: "X", code: "KeyX", key: "x", size: size, holder: holder)
            }
            HStack(spacing: 8) {
                KeyButton(label: "SPC", code: "Space", key: " ", size: size, holder: holder)
                KeyButton(label: "ENT", code: "Enter", key: "Enter", size: size, holder: holder)
            }
            if extra {
                HStack(spacing: 8) {
                    KeyButton(label: "C", code: "KeyC", key: "c", size: size, holder: holder)
                    KeyButton(label: "SHF", code: "ShiftLeft", key: "Shift", size: size, holder: holder)
                }
                HStack(spacing: 8) {
                    KeyButton(label: "ESC", code: "Escape", key: "Escape", size: size, holder: holder)
                    KeyButton(label: "R", code: "KeyR", key: "r", size: size, holder: holder)
                }
            }
        }
    }
}

// MARK: - Option lists
enum GameOptions {
    static let screenModes: [(String, String)] = [("auto", "Auto"), ("showAll", "Fit"), ("noBorder", "Fill"), ("exactFit", "Stretch")]
    static let qualities: [(String, String)] = [("low", "Low"), ("medium", "Medium"), ("high", "High"), ("best", "Best")]
}

struct ChipPicker: View {
    let options: [(String, String)]
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.0) { opt in
                Button { selection = opt.0 } label: {
                    Text(opt.1)
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selection == opt.0 ? Color.orange : Color.white.opacity(0.12))
                        .foregroundColor(selection == opt.0 ? .black : .white)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - In-game options panel (display + controls, live)
struct GameOptionsPanel: View {
    let onClose: () -> Void
    @AppStorage("scaleMode") private var scaleMode = "auto"
    @AppStorage("quality") private var quality = "high"
    @AppStorage("autoLandscape") private var autoLandscape = true
    @AppStorage("controlsOn") private var controlsOn = true
    @AppStorage("wasd") private var wasd = false
    @AppStorage("extraKeys") private var extraKeys = false
    @AppStorage("haptics") private var haptics = true
    @AppStorage("ctrlSize") private var ctrlSize = 58.0
    @AppStorage("ctrlOpacity") private var ctrlOpacity = 1.0

    private func heading(_ t: String) -> some View {
        Text(t).font(.caption.weight(.bold)).foregroundColor(.orange).padding(.top, 4)
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("DISPLAY")
            Text("Screen mode").font(.subheadline)
            ChipPicker(options: GameOptions.screenModes, selection: $scaleMode)
            Text("Quality (game restarts)").font(.subheadline)
            ChipPicker(options: GameOptions.qualities, selection: $quality)
            Toggle("Auto-rotate to match game", isOn: $autoLandscape).tint(.orange)
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("CONTROLS")
            Toggle("On-screen controls", isOn: $controlsOn).tint(.orange)
            Toggle("WASD instead of arrows", isOn: $wasd).tint(.orange)
            Toggle("Extra buttons (C, Shift, Esc, R)", isOn: $extraKeys).tint(.orange)
            Toggle("Haptic feedback", isOn: $haptics).tint(.orange)
            Text("Button size: \(Int(ctrlSize))").font(.subheadline)
            Slider(value: $ctrlSize, in: 40...80, step: 2).tint(.orange)
            Text("Opacity: \(Int(ctrlOpacity * 100))%").font(.subheadline)
            Slider(value: $ctrlOpacity, in: 0.2...1.0).tint(.orange)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Game Options").font(.headline)
                Spacer()
                Button("Done", action: onClose).font(.body.weight(.semibold)).foregroundColor(.orange)
            }
            .padding(16)
            Divider().background(Color.white.opacity(0.15))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    displaySection
                    controlsSection
                }
                .padding(16)
            }
        }
        .foregroundColor(.white)
        .background(Color(red: 0.08, green: 0.07, blue: 0.14).opacity(0.97))
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Player screen
struct PlayerScreen: View {
    let name: String
    let gameSize: CGSize
    let needThumb: Bool
    let onThumb: (UIImage) -> Void
    let onClose: () -> Void

    @AppStorage("controlsOn") private var controlsOn = true
    @AppStorage("wasd") private var wasd = false
    @AppStorage("scaleMode") private var scaleMode = "auto"
    @AppStorage("quality") private var quality = "high"
    @AppStorage("ctrlSize") private var ctrlSize = 58.0
    @AppStorage("ctrlOpacity") private var ctrlOpacity = 1.0
    @AppStorage("extraKeys") private var extraKeys = false
    @AppStorage("autoLandscape") private var autoLandscape = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var holder = WebHolder()
    @State private var loading = true
    @State private var paused = false
    @State private var muted = false
    @State private var landscape = false
    @State private var showOptions = false

    private func roundIcon(_ system: String) -> some View {
        Image(systemName: system).foregroundColor(.white).padding(10)
            .background(Color.black.opacity(0.55)).clipShape(Circle())
    }

    private func snapshot() {
        guard let wv = holder.web else { return }
        wv.takeSnapshot(with: nil) { image, _ in
            if let image = image { onThumb(image) }
        }
    }

    private func close() {
        holder.setPaused(true)
        if landscape { Orient.set(.portrait) }
        onClose()
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GameView(holder: holder, scale: scaleMode, quality: quality, size: gameSize).ignoresSafeArea()

            if loading {
                VStack(spacing: 12) {
                    ProgressView().progressViewStyle(.circular).tint(.orange)
                    Text(name).font(.caption).foregroundColor(.white.opacity(0.7))
                }
                .allowsHitTesting(false)
            }

            if controlsOn {
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        DPad(holder: holder, wasd: wasd, size: ctrlSize * 0.93)
                        Spacer()
                        ActionPad(holder: holder, size: ctrlSize, extra: extraKeys)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 24)
                }
                .opacity(ctrlOpacity)
            }

            VStack {
                HStack(spacing: 10) {
                    Button(action: close) { roundIcon("xmark") }
                    Spacer()
                    Button {
                        paused.toggle()
                        holder.setPaused(paused)
                    } label: { roundIcon(paused ? "play.fill" : "pause.fill") }
                    Button {
                        muted.toggle()
                        holder.setMuted(muted)
                    } label: { roundIcon(muted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        Button {
                            landscape.toggle()
                            Orient.set(landscape ? .landscape : .portrait)
                        } label: { roundIcon("rotate.right") }
                    }
                    Button { showOptions.toggle() } label: { roundIcon("slider.horizontal.3") }
                    Button { controlsOn.toggle() } label: {
                        roundIcon(controlsOn ? "gamecontroller.fill" : "gamecontroller")
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8)
                Spacer()
            }

            if showOptions {
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        Color.black.opacity(0.25).ignoresSafeArea()
                            .onTapGesture { showOptions = false }
                        GameOptionsPanel(onClose: { showOptions = false })
                            .frame(maxWidth: 440)
                            .frame(maxHeight: max(220, geo.size.height * 0.65))
                            .padding(10)
                    }
                }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            holder.onReady = {
                loading = false
                if needThumb {
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
        .onChange(of: quality) { _ in
            loading = true
            holder.load(scale: scaleMode, quality: quality, size: gameSize)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { holder.setPaused(paused) } else { holder.setPaused(true) }
        }
    }
}
