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

// MARK: - Virtual joystick
struct VirtualStick: View {
    let size: CGFloat
    let onChange: (CGVector) -> Void
    var onTap: (() -> Void)? = nil
    var ringFill: Color = Color.white.opacity(0.12)
    var ringStroke: Color = Color.white.opacity(0.4)
    var knobFill: Color = Color.white.opacity(0.38)
    var knobIcon: String? = nil
    var bottomIcon: String? = nil
    @State private var knob: CGSize = .zero
    @State private var start: Date?
    @State private var moved = false

    var body: some View {
        let r = size / 2
        ZStack {
            Circle().fill(ringFill)
            Circle().stroke(ringStroke, lineWidth: 2)
            if let b = bottomIcon {
                Image(systemName: b).font(.system(size: size * 0.13))
                    .foregroundColor(ringStroke).offset(y: size * 0.33)
            }
            Circle().fill(knobFill)
                .frame(width: size * 0.42, height: size * 0.42)
                .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 2))
                .overlay(Group {
                    if let k = knobIcon {
                        Image(systemName: k).font(.system(size: size * 0.2)).foregroundColor(.white.opacity(0.85))
                    }
                })
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
