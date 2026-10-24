import SwiftUI

// MARK: - Option lists
enum GameOptions {
    static let engines: [(String, String)] = [("standard", "Standard"), ("perf", "Performance"), ("cdn", "Original")]
    static let screenModes: [(String, String)] = [("auto", "Auto"), ("showAll", "Fit"), ("noBorder", "Fill"), ("exactFit", "Stretch")]
    static let qualities: [(String, String)] = [("low", "Low"), ("medium", "Medium"), ("high", "High"), ("best", "Best")]
    static let fpsCaps: [(String, String)] = [("0", "Default"), ("30", "30"), ("40", "40"), ("50", "50"), ("60", "60")]
    static let layouts: [(String, String)] = [("simple", "Simple"), ("focus", "Focus"), ("double", "Double"), ("quadra", "Quadra")]
    static let styles: [(String, String)] = [("buttons", "Buttons"), ("dual", "Dual sticks")]
    static let touchModes: [(String, String)] = [("direct", "Direct touch"), ("cursor", "Cursor")]
    static let dirs: [(String, String)] = [("8", "8-Directions"), ("4", "4-Directions")]

    static let resetKeys = ["scaleMode", "quality", "engine", "fpsCap", "showFps", "controlsOn", "controlStyle",
                            "padLayout", "mirror", "dir8", "wasd", "extraKeys", "haptics", "ctrlSize",
                            "ctrlOpacity", "autoLandscape", "cursorMode", "cursorSpeed"]
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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

// MARK: - In-game options panel (Game | Controls)
struct GameOptionsPanel: View {
    let onClose: () -> Void
    let onReload: () -> Void
    let onOrientation: (Bool) -> Void
    let onMapping: () -> Void

    @AppStorage("scaleMode") private var scaleMode = "auto"
    @AppStorage("quality") private var quality = "high"
    @AppStorage("engine") private var engine = "standard"
    @AppStorage("fpsCap") private var fpsCap = "0"
    @AppStorage("showFps") private var showFps = false
    @AppStorage("autoLandscape") private var autoLandscape = true
    @AppStorage("controlsOn") private var controlsOn = true
    @AppStorage("controlStyle") private var controlStyle = "buttons"
    @AppStorage("padLayout") private var padLayout = "simple"
    @AppStorage("mirror") private var mirror = false
    @AppStorage("dir8") private var dir8 = true
    @AppStorage("wasd") private var wasd = false
    @AppStorage("extraKeys") private var extraKeys = false
    @AppStorage("haptics") private var haptics = true
    @AppStorage("ctrlSize") private var ctrlSize = 58.0
    @AppStorage("ctrlOpacity") private var ctrlOpacity = 1.0
    @AppStorage("cursorMode") private var cursorMode = false
    @AppStorage("cursorSpeed") private var cursorSpeed = 9.0

    @State private var tab = 0
    @State private var pendEngine = "standard"
    @State private var pendQuality = "high"

    private var needsReload: Bool { pendEngine != engine || pendQuality != quality }

    private func heading(_ t: String) -> some View {
        Text(t).font(.caption.weight(.bold)).foregroundColor(.orange).padding(.top, 4)
    }
    private func note(_ t: String) -> some View {
        Text(t).font(.caption).foregroundColor(.white.opacity(0.55))
    }

    private var dirBinding: Binding<String> {
        Binding(get: { dir8 ? "8" : "4" }, set: { dir8 = ($0 == "8") })
    }
    private var touchBinding: Binding<String> {
        Binding(get: { cursorMode ? "cursor" : "direct" }, set: { cursorMode = ($0 == "cursor") })
    }

    private var engineNote: String {
        switch pendEngine {
        case "perf": return "Direct WebGL, low quality. Best speed on older devices."
        case "cdn": return "Latest official Ruffle, loaded from the internet."
        default: return "Ruffle bundled inside the app. Works offline."
        }
    }

    private var gameTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                heading("FLASH ENGINE")
                ChipPicker(options: GameOptions.engines, selection: $pendEngine)
                note(engineNote)
                heading("SCREEN")
                ChipPicker(options: GameOptions.screenModes, selection: $scaleMode)
                HStack(spacing: 8) {
                    Button { onOrientation(true) } label: { orientChip("rectangle", "Landscape") }
                    Button { onOrientation(false) } label: { orientChip("rectangle.portrait", "Portrait") }
                }
            }
            Group {
                Toggle("Auto-rotate to match game", isOn: $autoLandscape).tint(.orange)
                heading("FRAME RATE")
                ChipPicker(options: GameOptions.fpsCaps, selection: $fpsCap)
                note("Limits how often the screen is redrawn. Lower it to save battery and heat.")
                Toggle("Show FPS counter", isOn: $showFps).tint(.orange)
                heading("QUALITY")
                ChipPicker(options: GameOptions.qualities, selection: $pendQuality)
                note("Engine and quality changes need Save and Reload.")
            }
        }
    }

    private func orientChip(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title).font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.12))
        .foregroundColor(.white)
        .clipShape(Capsule())
    }

    private var controlsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                heading("ON-SCREEN CONTROLS")
                Toggle("Show controls", isOn: $controlsOn).tint(.orange)
                ChipPicker(options: GameOptions.styles, selection: $controlStyle)
                if controlStyle == "buttons" {
                    note("Keyboard layout")
                    ChipPicker(options: GameOptions.layouts, selection: $padLayout)
                }
                Toggle("Left to right (swap sides)", isOn: $mirror).tint(.orange)
                note("Direction control")
                ChipPicker(options: GameOptions.dirs, selection: dirBinding)
            }
            Group {
                heading("TOUCH MODE")
                ChipPicker(options: GameOptions.touchModes, selection: touchBinding)
                note("Cursor mode: drag to move the pointer, tap to click, two-finger tap to right-click, hold to drag.")
                Text("Cursor speed: \(Int(cursorSpeed))").font(.subheadline)
                Slider(value: $cursorSpeed, in: 1...18, step: 1).tint(.orange)
            }
            Group {
                heading("BUTTONS")
                Toggle("WASD instead of arrows", isOn: $wasd).tint(.orange)
                Toggle("Extra buttons (C, Shift, Esc, R)", isOn: $extraKeys).tint(.orange)
                Toggle("Haptic feedback", isOn: $haptics).tint(.orange)
                Text("Button size: \(Int(ctrlSize))").font(.subheadline)
                Slider(value: $ctrlSize, in: 40...80, step: 2).tint(.orange)
                Text("Opacity: \(Int(ctrlOpacity * 100))%").font(.subheadline)
                Slider(value: $ctrlOpacity, in: 0.2...1.0).tint(.orange)
                Button(action: onMapping) {
                    Label("Edit gamepad mapping", systemImage: "gamecontroller.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.9))
                        .foregroundColor(.black)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func resetAll() {
        let engineChanged = engine != "standard" || quality != "high"
        for k in GameOptions.resetKeys { UserDefaults.standard.removeObject(forKey: k) }
        pendEngine = "standard"
        pendQuality = "high"
        if engineChanged { onReload() }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Game Options").font(.headline)
                Spacer()
                Button("Done", action: onClose).font(.body.weight(.semibold)).foregroundColor(.orange)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

            Picker("", selection: $tab) {
                Text("Game").tag(0)
                Text("Controls").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.bottom, 8)

            Divider().background(Color.white.opacity(0.15))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if tab == 0 { gameTab } else { controlsTab }
                }
                .padding(16)
            }

            Divider().background(Color.white.opacity(0.15))
            HStack {
                Button("Reset to default", action: resetAll).foregroundColor(.orange)
                Spacer()
                if needsReload {
                    Button {
                        engine = pendEngine
                        quality = pendQuality
                        onReload()
                        onClose()
                    } label: {
                        Text("Save and Reload").font(.subheadline.weight(.bold))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(Color.orange).foregroundColor(.black).clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .foregroundColor(.white)
        .background(Color(red: 0.08, green: 0.07, blue: 0.14).opacity(0.97))
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .onAppear {
            pendEngine = engine
            pendQuality = quality
        }
    }
}

// MARK: - Screen annotation (pencil)
struct Stroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var color: Color
}

struct AnnotationLayer: View {
    @Binding var strokes: [Stroke]
    let color: Color
    @State private var current: Stroke?

    private func path(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let f = pts.first else { return p }
        p.move(to: f)
        for q in pts.dropFirst() { p.addLine(to: q) }
        if pts.count == 1 { p.addLine(to: CGPoint(x: f.x + 0.1, y: f.y)) }
        return p
    }

    var body: some View {
        ZStack {
            ForEach(strokes) { s in
                path(s.points).stroke(s.color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let c = current {
                path(c.points).stroke(c.color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            Color.white.opacity(0.001)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            if current == nil { current = Stroke(points: [g.location], color: color) }
                            else { current?.points.append(g.location) }
                        }
                        .onEnded { _ in
                            if let c = current { strokes.append(c) }
                            current = nil
                        }
                )
        }
    }
}

struct AnnotationBar: View {
    @Binding var strokes: [Stroke]
    @Binding var colorIndex: Int
    let colors: [Color]
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(colors.indices, id: \.self) { i in
                Circle().fill(colors[i]).frame(width: 26, height: 26)
                    .overlay(Circle().stroke(Color.white, lineWidth: i == colorIndex ? 3 : 0))
                    .onTapGesture { colorIndex = i }
            }
            Button { if !strokes.isEmpty { strokes.removeLast() } } label: {
                Image(systemName: "arrow.uturn.backward").foregroundColor(.white)
            }
            Button { strokes.removeAll() } label: {
                Image(systemName: "trash").foregroundColor(.white)
            }
            Button("Done", action: onDone).foregroundColor(.orange).font(.body.weight(.semibold))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.black.opacity(0.7))
        .clipShape(Capsule())
    }
}

// MARK: - Virtual keyboard (forwards typing to the game)
struct KeyboardCapture: View {
    let holder: WebHolder
    let onClose: () -> Void
    private let sentinel = " "
    @State private var text = " "
    @FocusState private var focused: Bool

    private func send(_ ch: Character) {
        let s = String(ch)
        var code = ""
        if let u = s.unicodeScalars.first {
            if (65...90).contains(Int(u.value)) || (97...122).contains(Int(u.value)) { code = "Key" + s.uppercased() }
            else if (48...57).contains(Int(u.value)) { code = "Digit" + s }
            else if s == " " { code = "Space" }
        }
        holder.tap(code: code, key: s)
    }

    var body: some View {
        TextField("", text: $text)
            .focused($focused)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .submitLabel(.return)
            .frame(width: 1, height: 1)
            .opacity(0.02)
            .onAppear { focused = true }
            .onChange(of: text) { new in
                if new == sentinel { return }
                if new.count < sentinel.count {
                    holder.tap(code: "Backspace", key: "Backspace")
                } else {
                    for ch in String(new.dropFirst(sentinel.count)) { send(ch) }
                }
                text = sentinel
            }
            .onSubmit {
                holder.tap(code: "Enter", key: "Enter")
                focused = true
            }
    }
}
