import SwiftUI
import GameController

// MARK: - Key / mouse actions a gamepad input can trigger
struct KeyAction: Identifiable {
    let id: String
    let label: String
    let code: String
    let key: String

    static let all: [KeyAction] = {
        var a: [KeyAction] = [
            KeyAction(id: "none", label: "None", code: "", key: ""),
            KeyAction(id: "ArrowUp", label: "Arrow Up", code: "ArrowUp", key: "ArrowUp"),
            KeyAction(id: "ArrowDown", label: "Arrow Down", code: "ArrowDown", key: "ArrowDown"),
            KeyAction(id: "ArrowLeft", label: "Arrow Left", code: "ArrowLeft", key: "ArrowLeft"),
            KeyAction(id: "ArrowRight", label: "Arrow Right", code: "ArrowRight", key: "ArrowRight"),
            KeyAction(id: "Space", label: "Space", code: "Space", key: " "),
            KeyAction(id: "Enter", label: "Enter", code: "Enter", key: "Enter"),
            KeyAction(id: "Escape", label: "Escape", code: "Escape", key: "Escape"),
            KeyAction(id: "Shift", label: "Shift", code: "ShiftLeft", key: "Shift"),
            KeyAction(id: "Control", label: "Ctrl", code: "ControlLeft", key: "Control"),
            KeyAction(id: "Tab", label: "Tab", code: "Tab", key: "Tab"),
            KeyAction(id: "Backspace", label: "Backspace", code: "Backspace", key: "Backspace"),
            KeyAction(id: "mouseL", label: "Mouse Left Click", code: "", key: ""),
            KeyAction(id: "mouseR", label: "Mouse Right Click", code: "", key: "")
        ]
        for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            a.append(KeyAction(id: "Key\(c)", label: String(c), code: "Key\(c)", key: String(c).lowercased()))
        }
        for d in "0123456789" {
            a.append(KeyAction(id: "Digit\(d)", label: String(d), code: "Digit\(d)", key: String(d)))
        }
        return a
    }()

    static func find(_ id: String) -> KeyAction? { all.first { $0.id == id } }
}

// MARK: - Config
enum PadInputs {
    static let groups: [(String, [String])] = [
        ("Face Buttons", ["A", "B", "X", "Y"]),
        ("D-Pad", ["DPadUp", "DPadDown", "DPadLeft", "DPadRight"]),
        ("Shoulder Buttons", ["LB", "RB", "LT", "RT"]),
        ("System Buttons", ["Start", "Back", "Guide"]),
        ("Stick Buttons", ["LSB", "RSB"]),
        ("Left Stick", ["LSB_Up", "LSB_Down", "LSB_Left", "LSB_Right"]),
        ("Right Stick", ["RSB_Up", "RSB_Down", "RSB_Left", "RSB_Right"])
    ]
    static var all: [String] { groups.flatMap { $0.1 } }
}

struct PadConfig: Codable, Equatable {
    var map: [String: String]
    var leftStickMouse: Bool
    var rightStickMouse: Bool
    var clickLeft: String     // "LT" (L2) or "LSB" (L3)
    var clickRight: String    // "RT" (R2) or "RSB" (R3)

    static let defaults = PadConfig(
        map: [
            "DPadUp": "ArrowUp", "DPadDown": "ArrowDown", "DPadLeft": "ArrowLeft", "DPadRight": "ArrowRight",
            "LSB_Up": "ArrowUp", "LSB_Down": "ArrowDown", "LSB_Left": "ArrowLeft", "LSB_Right": "ArrowRight",
            "A": "Space", "B": "KeyX", "X": "KeyZ", "Y": "KeyC", "Start": "Enter", "Back": "Escape"
        ],
        leftStickMouse: false, rightStickMouse: true, clickLeft: "LT", clickRight: "RT")
}

// MARK: - Manager (physical controllers via GameController framework)
final class GamepadManager: ObservableObject {
    static let shared = GamepadManager()

    @Published var names: [String] = []
    @Published var config: PadConfig = PadConfig.defaults
    @Published var lastPressed: String?
    var detecting = false

    private weak var holder: WebHolder?
    private var gameKey = "default"
    private var pressed: Set<String> = []
    private var timer: Timer?
    private let dead: Float = 0.2

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(controllersChanged),
                                               name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllersChanged),
                                               name: .GCControllerDidDisconnect, object: nil)
        controllersChanged()
    }

    @objc private func controllersChanged() {
        DispatchQueue.main.async {
            let list = GCController.controllers()
            self.names = list.map { $0.vendorName ?? "Controller" }
            for c in list { self.bind(c) }
        }
    }

    private func bind(_ c: GCController) {
        guard let gp = c.extendedGamepad else { return }
        gp.valueChangedHandler = { [weak self] pad, _ in self?.handle(pad) }
    }

    // MARK: attach / persistence
    func attach(holder: WebHolder, gameKey: String) {
        self.holder = holder
        self.gameKey = gameKey
        config = GamepadManager.load(gameKey)
        pressed = []
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    func detach() {
        for n in pressed { fire(n, false) }
        pressed = []
        holder = nil
        timer?.invalidate()
        timer = nil
        detecting = false
    }

    func save() {
        if let d = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(d, forKey: "padcfg." + gameKey)
        }
    }

    private static func load(_ key: String) -> PadConfig {
        if let d = UserDefaults.standard.data(forKey: "padcfg." + key),
           let c = try? JSONDecoder().decode(PadConfig.self, from: d) { return c }
        return PadConfig.defaults
    }

    // MARK: input handling
    private func dirs(_ s: GCControllerDirectionPad, _ prefix: String) -> Set<String> {
        let x = s.xAxis.value, y = s.yAxis.value
        let t: Float = 0.5
        let eight = UserDefaults.standard.object(forKey: "dir8") as? Bool ?? true
        var out: Set<String> = []
        if eight {
            if y > t { out.insert(prefix + "Up") }
            if y < -t { out.insert(prefix + "Down") }
            if x < -t { out.insert(prefix + "Left") }
            if x > t { out.insert(prefix + "Right") }
        } else if abs(x) > abs(y) {
            if x > t { out.insert(prefix + "Right") }
            if x < -t { out.insert(prefix + "Left") }
        } else {
            if y > t { out.insert(prefix + "Up") }
            if y < -t { out.insert(prefix + "Down") }
        }
        return out
    }

    private func handle(_ pad: GCExtendedGamepad) {
        var now: Set<String> = []
        if pad.buttonA.isPressed { now.insert("A") }
        if pad.buttonB.isPressed { now.insert("B") }
        if pad.buttonX.isPressed { now.insert("X") }
        if pad.buttonY.isPressed { now.insert("Y") }
        if pad.dpad.up.isPressed { now.insert("DPadUp") }
        if pad.dpad.down.isPressed { now.insert("DPadDown") }
        if pad.dpad.left.isPressed { now.insert("DPadLeft") }
        if pad.dpad.right.isPressed { now.insert("DPadRight") }
        if pad.leftShoulder.isPressed { now.insert("LB") }
        if pad.rightShoulder.isPressed { now.insert("RB") }
        if pad.leftTrigger.isPressed { now.insert("LT") }
        if pad.rightTrigger.isPressed { now.insert("RT") }
        if pad.buttonMenu.isPressed { now.insert("Start") }
        if pad.buttonOptions?.isPressed == true { now.insert("Back") }
        if pad.buttonHome?.isPressed == true { now.insert("Guide") }
        if pad.leftThumbstickButton?.isPressed == true { now.insert("LSB") }
        if pad.rightThumbstickButton?.isPressed == true { now.insert("RSB") }
        if !config.leftStickMouse { now.formUnion(dirs(pad.leftThumbstick, "LSB_")) }
        if !config.rightStickMouse { now.formUnion(dirs(pad.rightThumbstick, "RSB_")) }

        let down = now.subtracting(pressed)
        let up = pressed.subtracting(now)
        pressed = now
        for n in down {
            if detecting { lastPressed = n } else { fire(n, true) }
        }
        for n in up where !detecting { fire(n, false) }
    }

    private func fire(_ name: String, _ isDown: Bool) {
        guard let h = holder else { return }
        if config.leftStickMouse || config.rightStickMouse {
            if name == config.clickLeft { h.mouse(down: isDown, button: 0); return }
            if name == config.clickRight { h.mouse(down: isDown, button: 2); return }
        }
        guard let id = config.map[name], id != "none", let a = KeyAction.find(id) else { return }
        if id == "mouseL" { h.mouse(down: isDown, button: 0) }
        else if id == "mouseR" { h.mouse(down: isDown, button: 2) }
        else { h.key(isDown ? "keydown" : "keyup", code: a.code, key: a.key) }
    }

    // stick-as-mouse
    private func tick() {
        guard let h = holder, !detecting else { return }
        guard config.leftStickMouse || config.rightStickMouse else { return }
        guard let pad = GCController.controllers().first?.extendedGamepad else { return }
        var dx: Float = 0, dy: Float = 0
        func add(_ s: GCControllerDirectionPad) {
            var x = s.xAxis.value, y = s.yAxis.value
            if abs(x) < dead { x = 0 }
            if abs(y) < dead { y = 0 }
            dx += x
            dy -= y
        }
        if config.leftStickMouse { add(pad.leftThumbstick) }
        if config.rightStickMouse { add(pad.rightThumbstick) }
        if dx != 0 || dy != 0 {
            let speed = UserDefaults.standard.object(forKey: "cursorSpeed") as? Double ?? 9.0
            let px = speed * 55.0 / 60.0
            h.moveCursor(dx: Double(dx) * px, dy: Double(dy) * px)
        }
    }
}

// MARK: - Mapping editor
struct GamepadMappingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pads = GamepadManager.shared
    @AppStorage("cursorSpeed") private var cursorSpeed = 9.0
    let gameName: String
    @State private var detect = false
    @State private var flash: String?

    private func bind<T>(_ kp: WritableKeyPath<PadConfig, T>) -> Binding<T> {
        Binding(get: { pads.config[keyPath: kp] },
                set: { pads.config[keyPath: kp] = $0; pads.save() })
    }

    private var mappedCount: Int {
        PadInputs.all.filter { (pads.config.map[$0] ?? "none") != "none" }.count
    }

    private func row(_ input: String) -> some View {
        let current = pads.config.map[input] ?? "none"
        return HStack {
            Text(input).foregroundColor(flash == input ? .orange : .primary)
            Spacer()
            Menu {
                Picker("Action", selection: Binding(
                    get: { pads.config.map[input] ?? "none" },
                    set: { v in
                        pads.config.map[input] = (v == "none") ? nil : v
                        pads.save()
                    })) {
                    ForEach(KeyAction.all) { a in Text(a.label).tag(a.id) }
                }
            } label: {
                Text(KeyAction.find(current)?.label ?? "None").foregroundColor(.orange)
            }
        }
    }

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                Form {
                    Section(header: Text("Connected Controllers (\(pads.names.count))")) {
                        if pads.names.isEmpty {
                            Text("No controller found. Connect an Xbox, PlayStation or MFi gamepad over Bluetooth.")
                                .foregroundColor(.gray)
                        } else {
                            ForEach(pads.names, id: \.self) { n in
                                Label(n, systemImage: "gamecontroller.fill")
                            }
                        }
                        Toggle("Detect: press a button on your gamepad", isOn: $detect)
                    }
                    Section(header: Text("Stick as Mouse"),
                            footer: Text("The stick moves the in-game cursor. Triggers or stick buttons act as mouse clicks.")) {
                        Toggle("Left stick moves cursor", isOn: bind(\.leftStickMouse))
                        Toggle("Right stick moves cursor", isOn: bind(\.rightStickMouse))
                        Picker("Left click", selection: bind(\.clickLeft)) {
                            Text("L2").tag("LT")
                            Text("L3").tag("LSB")
                        }.pickerStyle(.segmented)
                        Picker("Right click", selection: bind(\.clickRight)) {
                            Text("R2").tag("RT")
                            Text("R3").tag("RSB")
                        }.pickerStyle(.segmented)
                        VStack(alignment: .leading) {
                            Text("Cursor speed: \(Int(cursorSpeed))")
                            Slider(value: $cursorSpeed, in: 1...18, step: 1)
                        }
                    }
                    ForEach(PadInputs.groups, id: \.0) { group in
                        Section(header: Text(group.0)) {
                            ForEach(group.1, id: \.self) { input in
                                row(input).id(input)
                            }
                        }
                    }
                    Section(footer: Text("\(mappedCount)/\(PadInputs.all.count) buttons mapped")) {
                        Button("Reset to default", role: .destructive) {
                            pads.config = PadConfig.defaults
                            pads.save()
                        }
                    }
                }
                .onChange(of: pads.lastPressed) { v in
                    if detect, let v = v {
                        flash = v
                        withAnimation { proxy.scrollTo(v, anchor: .center) }
                    }
                }
            }
            .navigationTitle(gameName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: detect) { pads.detecting = $0 }
            .onDisappear { pads.detecting = false; pads.save() }
        }
        .preferredColorScheme(.dark)
    }
}
