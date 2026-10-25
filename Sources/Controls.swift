import SwiftUI

// MARK: - Single on-screen key
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

// MARK: - Button layouts: Simple / Focus / Double / Quadra
struct KeyPads: View {
    let holder: WebHolder
    let layout: String
    let wasd: Bool
    let size: CGFloat
    let extra: Bool
    let mirror: Bool

    @ViewBuilder private var leftCluster: some View {
        DPad(holder: holder, wasd: layout == "double" ? false : wasd, size: size * 0.93)
    }

    @ViewBuilder private var rightCluster: some View {
        switch layout {
        case "focus":
            HStack(alignment: .bottom, spacing: 12) {
                KeyButton(label: "Z", code: "KeyZ", key: "z", size: size * 1.15, holder: holder)
                KeyButton(label: "SPC", code: "Space", key: " ", size: size * 1.5, holder: holder)
            }
        case "double":
            VStack(spacing: 8) {
                DPad(holder: holder, wasd: true, size: size * 0.93)
                KeyButton(label: "SPC", code: "Space", key: " ", size: size, holder: holder)
            }
        case "quadra":
            VStack(spacing: 4) {
                KeyButton(label: "C", code: "KeyC", key: "c", size: size, holder: holder)
                HStack(spacing: 4) {
                    KeyButton(label: "Z", code: "KeyZ", key: "z", size: size, holder: holder)
                    Color.clear.frame(width: size, height: size)
                    KeyButton(label: "X", code: "KeyX", key: "x", size: size, holder: holder)
                }
                KeyButton(label: "V", code: "KeyV", key: "v", size: size, holder: holder)
            }
        default:
            ActionPad(holder: holder, size: size, extra: extra)
        }
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if mirror {
                rightCluster
                Spacer()
                leftCluster
            } else {
                leftCluster
                Spacer()
                rightCluster
            }
        }
    }
}

// MARK: - Virtual joystick
struct VirtualStick: View {
    let size: CGFloat
    let onChange: (CGVector) -> Void
    var onTap: (() -> Void)? = nil
    @State private var knob: CGSize = .zero
    @State private var start: Date?
    @State private var moved = false

    var body: some View {
        let r = size / 2
        ZStack {
            Circle().fill(Color.white.opacity(0.12))
            Circle().stroke(Color.white.opacity(0.4), lineWidth: 1.5)
            Circle().fill(Color.white.opacity(0.38))
                .frame(width: size * 0.42, height: size * 0.42)
                .offset(knob)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if start == nil { start = Date(); moved = false }
                    let dx = g.location.x - r
                    let dy = g.location.y - r
                    let lim = r * 0.8
                    let dist = sqrt(dx * dx + dy * dy)
                    let k: CGFloat = dist > lim ? lim / dist : 1
                    let nx = dx * k / lim
                    let ny = dy * k / lim
                    if sqrt(nx * nx + ny * ny) > 0.3 { moved = true }
                    knob = CGSize(width: dx * k * 0.72, height: dy * k * 0.72)
                    onChange(CGVector(dx: nx, dy: ny))
                }
                .onEnded { _ in
                    var quick = false
                    if let s = start { quick = Date().timeIntervalSince(s) < 0.25 }
                    if quick && !moved { onTap?() }
                    start = nil
                    moved = false
                    knob = .zero
                    onChange(CGVector(dx: 0, dy: 0))
                }
        )
    }
}

/// Turns an analog stick vector into held arrow / WASD keys (4 or 8 directions).
final class DirKeys {
    var pressed: Set<String> = []

    private func keyFor(_ d: String, wasd: Bool) -> (String, String)? {
        if wasd {
            switch d {
            case "L": return ("KeyA", "a")
            case "R": return ("KeyD", "d")
            case "U": return ("KeyW", "w")
            default: return ("KeyS", "s")
            }
        }
        switch d {
        case "L": return ("ArrowLeft", "ArrowLeft")
        case "R": return ("ArrowRight", "ArrowRight")
        case "U": return ("ArrowUp", "ArrowUp")
        default: return ("ArrowDown", "ArrowDown")
        }
    }

    func update(_ v: CGVector, holder: WebHolder, wasd: Bool, dir8: Bool) {
        let t: CGFloat = 0.4
        var want: Set<String> = []
        if dir8 {
            if v.dx < -t { want.insert("L") }
            if v.dx > t { want.insert("R") }
            if v.dy < -t { want.insert("U") }
            if v.dy > t { want.insert("D") }
        } else if abs(v.dx) > abs(v.dy) {
            if v.dx < -t { want.insert("L") }
            if v.dx > t { want.insert("R") }
        } else {
            if v.dy < -t { want.insert("U") }
            if v.dy > t { want.insert("D") }
        }
        for d in want.subtracting(pressed) {
            if let k = keyFor(d, wasd: wasd) { holder.key("keydown", code: k.0, key: k.1) }
        }
        for d in pressed.subtracting(want) {
            if let k = keyFor(d, wasd: wasd) { holder.key("keyup", code: k.0, key: k.1) }
        }
        pressed = want
    }
}

final class StickBox { var v = CGVector(dx: 0, dy: 0) }

struct MouseBtn: View {
    let label: String
    let button: Int
    let holder: WebHolder
    @State private var down = false
    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Capsule().fill(down ? Color.orange : Color.blue.opacity(0.45)))
            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !down { down = true; holder.mouse(down: true, button: button) }
                    }
                    .onEnded { _ in
                        down = false
                        holder.mouse(down: false, button: button)
                    }
            )
    }
}

// MARK: - PS4-style dual stick overlay: left = move keys, right = cursor
struct DualSticks: View {
    let holder: WebHolder
    let size: CGFloat
    let mirror: Bool
    let wasd: Bool
    let dir8: Bool
    @AppStorage("cursorSpeed") private var speed = 9.0
    @State private var keys = DirKeys()
    @State private var box = StickBox()
    private let tick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    @ViewBuilder private var moveCluster: some View {
        VirtualStick(size: size, onChange: { v in
            keys.update(v, holder: holder, wasd: wasd, dir8: dir8)
        })
    }

    @ViewBuilder private var cursorCluster: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MouseBtn(label: "L-Click", button: 0, holder: holder)
                MouseBtn(label: "R-Click", button: 2, holder: holder)
            }
            VirtualStick(size: size, onChange: { v in box.v = v })
        }
    }

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                if mirror {
                    cursorCluster
                    Spacer()
                    moveCluster
                } else {
                    moveCluster
                    Spacer()
                    cursorCluster
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .onReceive(tick) { _ in
            let v = box.v
            if abs(v.dx) > 0.12 || abs(v.dy) > 0.12 {
                let px = speed * 55.0 / 60.0
                holder.moveCursor(dx: Double(v.dx) * px, dy: Double(v.dy) * px)
            }
        }
    }
}
