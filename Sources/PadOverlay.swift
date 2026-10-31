import SwiftUI

// MARK: - Virtual direction keys for a stick (LSB_* / RSB_*), sent through the gamepad mapping
final class VDirs {
    var pressed: Set<String> = []

    func update(_ v: CGVector, prefix: String, dir8: Bool, pads: GamepadManager) {
        let t: CGFloat = 0.4
        var want: Set<String> = []
        if dir8 {
            if v.dy < -t { want.insert(prefix + "Up") }
            if v.dy > t { want.insert(prefix + "Down") }
            if v.dx < -t { want.insert(prefix + "Left") }
            if v.dx > t { want.insert(prefix + "Right") }
        } else if abs(v.dx) > abs(v.dy) {
            if v.dx < -t { want.insert(prefix + "Left") }
            if v.dx > t { want.insert(prefix + "Right") }
        } else {
            if v.dy < -t { want.insert(prefix + "Up") }
            if v.dy > t { want.insert(prefix + "Down") }
        }
        for n in want.subtracting(pressed) { pads.press(n, true) }
        for n in pressed.subtracting(want) { pads.press(n, false) }
        pressed = want
    }
}

// MARK: - One item of the on-screen controller
struct PadItem: Identifiable {
    enum Kind {
        case shoulder(String)              // L1 L2 R1 R2
        case click(String)                 // L3 R3 (mouse click pills)
        case dpad(String)                  // SF symbol of the arrow
        case face(String, Color)           // SF symbol, color
        case stick(Bool)                   // true = left
    }
    let id: String                         // gamepad input name (or LS / RS)
    let kind: Kind
    let fx: CGFloat                        // centre, fraction of width
    let fy: CGFloat                        // centre, fraction of height
}

enum PadLayout {
    static let green = Color(red: 0.16, green: 0.62, blue: 0.30)
    static let purple = Color(red: 0.55, green: 0.32, blue: 0.75)
    static let red = Color(red: 0.80, green: 0.22, blue: 0.22)
    static let blue = Color(red: 0.28, green: 0.55, blue: 0.80)

    static let items: [PadItem] = [
        PadItem(id: "LT", kind: .shoulder("L2"), fx: 0.199, fy: 0.084),
        PadItem(id: "LB", kind: .shoulder("L1"), fx: 0.313, fy: 0.084),
        PadItem(id: "RB", kind: .shoulder("R1"), fx: 0.719, fy: 0.084),
        PadItem(id: "RT", kind: .shoulder("R2"), fx: 0.833, fy: 0.084),
        PadItem(id: "DPadUp", kind: .dpad("arrow.up"), fx: 0.232, fy: 0.290),
        PadItem(id: "DPadLeft", kind: .dpad("arrow.left"), fx: 0.177, fy: 0.409),
        PadItem(id: "DPadRight", kind: .dpad("arrow.right"), fx: 0.286, fy: 0.409),
        PadItem(id: "DPadDown", kind: .dpad("arrow.down"), fx: 0.232, fy: 0.527),
        PadItem(id: "LS", kind: .stick(true), fx: 0.296, fy: 0.653),
        PadItem(id: "RS", kind: .stick(false), fx: 0.704, fy: 0.653),
        PadItem(id: "Y", kind: .face("triangle", PadLayout.green), fx: 0.792, fy: 0.322),
        PadItem(id: "X", kind: .face("square", PadLayout.purple), fx: 0.738, fy: 0.441),
        PadItem(id: "B", kind: .face("circle", PadLayout.red), fx: 0.847, fy: 0.441),
        PadItem(id: "A", kind: .face("xmark", PadLayout.blue), fx: 0.792, fy: 0.561),
        PadItem(id: "LSB", kind: .click("L3"), fx: 0.193, fy: 0.808),
        PadItem(id: "RSB", kind: .click("R3"), fx: 0.807, fy: 0.808)
    ]
}

// MARK: - A pressable pad button (pill / key / circle)
struct PadButtonView: View {
    let item: PadItem
    let k: CGFloat
    @ObservedObject private var pads = GamepadManager.shared
    @AppStorage("haptics") private var haptics = true
    @State private var down = false

    private func fireDown(_ d: Bool) { pads.press(item.id, d) }

    private var mapped: String { pads.label(item.id) }

    @ViewBuilder private var mouseIcon: some View {
        Image(systemName: "computermouse.fill").font(.system(size: 13 * k))
    }

    @ViewBuilder private var face: some View {
        switch item.kind {
        case .shoulder(let t):
            VStack(spacing: 2) {
                Text(t).font(.system(size: 15 * k, weight: .bold))
                if pads.isClick(item.id) { mouseIcon } else { Text(mapped).font(.system(size: 13 * k)) }
            }
            .foregroundColor(.white)
            .frame(width: 92 * k, height: 47 * k)
            .background(Capsule().fill(down ? Color.orange : Color(white: 0.45, opacity: 0.75)))
            .overlay(Capsule().stroke(Color.white.opacity(0.55), lineWidth: 1.5))
        case .click(let t):
            VStack(spacing: 2) {
                Text(t).font(.system(size: 15 * k, weight: .bold))
                if pads.isClick(item.id) { mouseIcon } else { Text(mapped).font(.system(size: 13 * k)) }
            }
            .foregroundColor(.white)
            .frame(width: 92 * k, height: 47 * k)
            .background(Capsule().fill(down ? Color.orange : Color(red: 0.05, green: 0.13, blue: 0.30, opacity: 0.92)))
            .overlay(Capsule().stroke(Color(red: 0.22, green: 0.52, blue: 0.85), lineWidth: 2))
        case .dpad(let sym):
            VStack(spacing: 1) {
                Image(systemName: sym).font(.system(size: 14 * k, weight: .bold))
                Text(mapped).font(.system(size: 12 * k, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(width: 44 * k, height: 44 * k)
            .background(RoundedRectangle(cornerRadius: 6 * k).fill(down ? Color.orange : Color(white: 0.30, opacity: 0.88)))
            .overlay(RoundedRectangle(cornerRadius: 6 * k).stroke(Color(white: 0.65), lineWidth: 1.5))
        case .face(let sym, let col):
            VStack(spacing: 1) {
                Image(systemName: sym).font(.system(size: 14 * k, weight: .bold))
                Text(mapped).font(.system(size: 12 * k, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(width: 44 * k, height: 44 * k)
            .background(Circle().fill(down ? Color.orange : col.opacity(0.85)))
            .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1.5))
        case .stick:
            EmptyView()
        }
    }

    var body: some View {
        face
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !down {
                            down = true
                            if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            fireDown(true)
                        }
                    }
                    .onEnded { _ in
                        down = false
                        fireDown(false)
                    }
            )
    }
}

// MARK: - On-screen controller (PS4 style). Same mapping as a physical gamepad.
struct PadOverlay: View {
    let holder: WebHolder
    let scale: CGFloat
    @ObservedObject private var pads = GamepadManager.shared
    @AppStorage("cursorSpeed") private var speed = 9.0
    @State private var leftBox = StickBox()
    @State private var rightBox = StickBox()
    @State private var leftDirs = VDirs()
    @State private var rightDirs = VDirs()
    private let tick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var dir8: Bool { UserDefaults.standard.object(forKey: "dir8") as? Bool ?? true }

    @ViewBuilder private func stick(_ left: Bool, _ k: CGFloat) -> some View {
        if left {
            VirtualStick(size: 92 * k,
                         onChange: { v in
                             if pads.config.leftStickMouse { leftBox.v = v }
                             else { leftDirs.update(v, prefix: "LSB_", dir8: dir8, pads: pads) }
                         },
                         ringFill: Color(white: 0.38, opacity: 0.7),
                         ringStroke: Color(white: 0.7, opacity: 0.8),
                         knobFill: Color(white: 0.85, opacity: 0.75))
        } else {
            VirtualStick(size: 92 * k,
                         onChange: { v in
                             if pads.config.rightStickMouse { rightBox.v = v }
                             else { rightDirs.update(v, prefix: "RSB_", dir8: dir8, pads: pads) }
                         },
                         ringFill: Color(red: 0.06, green: 0.16, blue: 0.32, opacity: 0.85),
                         ringStroke: Color(red: 0.25, green: 0.58, blue: 0.92),
                         knobFill: Color(red: 0.28, green: 0.58, blue: 0.85, opacity: 0.9),
                         bottomIcon: pads.config.rightStickMouse ? "computermouse.fill" : nil)
        }
    }

    @ViewBuilder private func piece(_ item: PadItem, _ k: CGFloat) -> some View {
        switch item.kind {
        case .stick(let left): stick(left, k)
        default: PadButtonView(item: item, k: k)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let k = max(0.7, min(1.4, scale))
            ForEach(PadLayout.items) { item in
                piece(item, k)
                    .position(x: item.fx * geo.size.width, y: item.fy * geo.size.height)
            }
        }
        .onReceive(tick) { _ in
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            if pads.config.leftStickMouse { dx += leftBox.v.dx; dy += leftBox.v.dy }
            if pads.config.rightStickMouse { dx += rightBox.v.dx; dy += rightBox.v.dy }
            if abs(dx) > 0.12 || abs(dy) > 0.12 {
                let px = speed * 55.0 / 60.0
                holder.moveCursor(dx: Double(dx) * px, dy: Double(dy) * px)
            }
        }
    }
}

// MARK: - Virtual mouse (shown when "touch" is OFF): cursor stick + mouse button
struct CursorOverlay: View {
    let holder: WebHolder
    @AppStorage("cursorSpeed") private var speed = 9.0
    @AppStorage("haptics") private var haptics = true
    @State private var box = StickBox()
    @State private var down = false
    private let tick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                VirtualStick(size: 66, onChange: { v in box.v = v },
                             ringFill: Color.white.opacity(0.06),
                             ringStroke: Color.white.opacity(0.55),
                             knobFill: Color.white.opacity(0.22),
                             knobIcon: "scope")
                    .position(x: 0.14 * geo.size.width, y: 0.563 * geo.size.height)
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(down ? Color.orange : Color(red: 0.2, green: 0.55, blue: 0.4, opacity: 0.45)))
                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
                    .contentShape(Circle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !down {
                                    down = true
                                    if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                                    holder.mouse(down: true, button: 0)
                                }
                            }
                            .onEnded { _ in
                                down = false
                                holder.mouse(down: false, button: 0)
                            }
                    )
                    .position(x: 0.80 * geo.size.width, y: 0.693 * geo.size.height)
            }
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
