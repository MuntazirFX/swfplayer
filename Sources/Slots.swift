import SwiftUI

// MARK: - Assignable on-screen buttons (P1..P4 = big, S1..S8 = small)
struct SlotButtonModel: Codable, Identifiable, Equatable {
    var id: String        // "P1", "S3", ...
    var action: String    // KeyAction id
    var x: Double         // 0...1 of screen width (center)
    var y: Double         // 0...1 of screen height (center)
    var scale: Double     // 0.6...1.8
    var big: Bool { id.hasPrefix("P") }
}

enum SlotLayouts {
    static func slots(_ layout: String) -> [String] {
        switch layout {
        case "focus": return ["P1", "S1", "S2", "S3", "S4", "S5", "S6", "S7"]
        case "double": return ["P1", "P2", "S1", "S2", "S3", "S4", "S5", "S6"]
        case "quadra": return ["P1", "P2", "P3", "P4", "S1", "S2", "S3", "S4"]
        default: return ["S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8"]
        }
    }

    static func defaults(_ layout: String) -> [SlotButtonModel] {
        let ids = slots(layout)
        let acts = ["Space", "KeyZ", "KeyX", "KeyC", "KeyV", "Enter", "Shift", "KeyR"]
        let pPos: [(Double, Double)] = [(0.92, 0.82), (0.79, 0.86), (0.84, 0.66), (0.93, 0.62)]
        let hasP = ids.contains("P1")
        var out: [SlotButtonModel] = []
        var pi = 0
        var si = 0
        for (i, id) in ids.enumerated() {
            let act = acts[i % acts.count]
            if id.hasPrefix("P") {
                let p = pPos[min(pi, pPos.count - 1)]
                let sc: Double = layout == "focus" ? 1.55 : (layout == "double" ? 1.35 : 1.15)
                out.append(SlotButtonModel(id: id, action: act, x: p.0, y: p.1, scale: sc))
                pi += 1
            } else {
                let col = si % 2
                let row = si / 2
                let x = 0.93 - 0.09 * Double(col)
                let y = max(0.12, (hasP ? 0.52 : 0.88) - (hasP ? 0.13 : 0.15) * Double(row))
                out.append(SlotButtonModel(id: id, action: act, x: x, y: y, scale: 0.9))
                si += 1
            }
        }
        return out
    }
}

enum SlotStore {
    private static func key(_ game: String, _ layout: String) -> String { "slots.\(game).\(layout)" }

    static func load(_ game: String, _ layout: String) -> [SlotButtonModel] {
        if let d = UserDefaults.standard.data(forKey: key(game, layout)),
           let m = try? JSONDecoder().decode([SlotButtonModel].self, from: d), !m.isEmpty { return m }
        return SlotLayouts.defaults(layout)
    }

    static func save(_ slots: [SlotButtonModel], _ game: String, _ layout: String) {
        if let d = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(d, forKey: key(game, layout))
        }
    }
}

extension KeyAction {
    static func short(_ id: String) -> String {
        switch id {
        case "none": return "-"
        case "Space": return "SPC"
        case "Enter": return "ENT"
        case "Escape": return "ESC"
        case "Shift": return "SHF"
        case "Control": return "CTL"
        case "Tab": return "TAB"
        case "Backspace": return "BKS"
        case "ArrowUp": return "UP"
        case "ArrowDown": return "DN"
        case "ArrowLeft": return "LT"
        case "ArrowRight": return "RT"
        case "mouseL": return "M-L"
        case "mouseR": return "M-R"
        default: return find(id)?.label ?? id
        }
    }
}

// MARK: - Playing: one assignable button
struct SlotButton: View {
    let model: SlotButtonModel
    let size: CGFloat
    let holder: WebHolder
    @AppStorage("haptics") private var haptics = true
    @State private var down = false

    private func fire(_ isDown: Bool) {
        guard model.action != "none", let a = KeyAction.find(model.action) else { return }
        if model.action == "mouseL" { holder.mouse(down: isDown, button: 0) }
        else if model.action == "mouseR" { holder.mouse(down: isDown, button: 2) }
        else { holder.key(isDown ? "keydown" : "keyup", code: a.code, key: a.key) }
    }

    var body: some View {
        let s = size * CGFloat(model.scale)
        Text(KeyAction.short(model.action))
            .font(.system(size: s * 0.28, weight: .bold))
            .foregroundColor(.white)
            .frame(width: s, height: s)
            .background(Circle().fill(down ? Color.orange : Color.white.opacity(model.big ? 0.28 : 0.2)))
            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !down {
                            down = true
                            if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            fire(true)
                        }
                    }
                    .onEnded { _ in
                        down = false
                        fire(false)
                    }
            )
    }
}

struct SlotPads: View {
    let slots: [SlotButtonModel]
    let size: CGFloat
    let mirror: Bool
    let holder: WebHolder

    var body: some View {
        GeometryReader { geo in
            ForEach(slots) { m in
                SlotButton(model: m, size: size, holder: holder)
                    .position(x: CGFloat(mirror ? 1 - m.x : m.x) * geo.size.width,
                              y: CGFloat(m.y) * geo.size.height)
            }
        }
    }
}

// MARK: - Left movement control: D-Pad or Joystick
struct MovePad: View {
    let holder: WebHolder
    let moveType: String
    let wasd: Bool
    let dir8: Bool
    let size: CGFloat
    let mirror: Bool
    @State private var keys = DirKeys()

    @ViewBuilder private var pad: some View {
        if moveType == "joystick" {
            VirtualStick(size: size * 2.2, onChange: { v in
                keys.update(v, holder: holder, wasd: wasd, dir8: dir8)
            })
        } else {
            DPad(holder: holder, wasd: wasd, size: size * 0.93)
        }
    }

    var body: some View {
        VStack {
            Spacer()
            HStack {
                if mirror {
                    Spacer()
                    pad
                } else {
                    pad
                    Spacer()
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
    }
}

// MARK: - Editing: drag buttons, pick key, resize
struct SlotEditor: View {
    @Binding var slots: [SlotButtonModel]
    let size: CGFloat
    let mirror: Bool
    let onReset: () -> Void
    let onDone: () -> Void
    @State private var selected: String?

    private var selIndex: Int? { slots.firstIndex { $0.id == selected } }

    private func chip(_ m: SlotButtonModel, isSel: Bool) -> some View {
        let s = size * CGFloat(m.scale)
        return Text(m.id + "\n" + KeyAction.short(m.action))
            .font(.system(size: max(9, s * 0.2), weight: .bold))
            .multilineTextAlignment(.center)
            .foregroundColor(.white)
            .frame(width: s, height: s)
            .background(Circle().fill(Color.white.opacity(isSel ? 0.45 : 0.25)))
            .overlay(Circle().stroke(isSel ? Color.orange : Color.white.opacity(0.7),
                                     style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Text("Drag to move, tap to edit").font(.footnote).foregroundColor(.white.opacity(0.8))
                Button("Reset", action: onReset).foregroundColor(.orange)
                Button("Done", action: onDone).font(.body.weight(.bold)).foregroundColor(.orange)
            }
            if let i = selIndex {
                HStack(spacing: 10) {
                    Text(slots[i].id).font(.footnote.weight(.bold)).foregroundColor(.white)
                    Menu {
                        Picker("Key", selection: Binding(get: { slots[i].action },
                                                          set: { slots[i].action = $0 })) {
                            ForEach(KeyAction.all) { a in Text(a.label).tag(a.id) }
                        }
                    } label: {
                        Text(KeyAction.find(slots[i].action)?.label ?? "None").foregroundColor(.orange)
                    }
                    Slider(value: Binding(get: { slots[i].scale }, set: { slots[i].scale = $0 }),
                           in: 0.6...1.8)
                        .frame(width: 140).tint(.orange)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.black.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.top, 8)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            GeometryReader { geo in
                ZStack {
                    ForEach(slots.indices, id: \.self) { i in
                        chip(slots[i], isSel: selected == slots[i].id)
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .named("edit"))
                                    .onChanged { g in
                                        selected = slots[i].id
                                        var nx = Double(g.location.x / geo.size.width)
                                        if mirror { nx = 1 - nx }
                                        slots[i].x = min(max(nx, 0.03), 0.97)
                                        slots[i].y = min(max(Double(g.location.y / geo.size.height), 0.1), 0.96)
                                    }
                            )
                            .position(x: CGFloat(mirror ? 1 - slots[i].x : slots[i].x) * geo.size.width,
                                      y: CGFloat(slots[i].y) * geo.size.height)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .coordinateSpace(name: "edit")
            }
            VStack {
                toolbar
                Spacer()
            }
        }
    }
}
