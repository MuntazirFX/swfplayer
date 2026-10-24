import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var lib: Library
    @AppStorage("scaleMode") private var scaleMode = "auto"
    @AppStorage("quality") private var quality = "high"
    @AppStorage("autoLandscape") private var autoLandscape = true
    @AppStorage("controlsOn") private var controlsOn = true
    @AppStorage("wasd") private var wasd = false
    @AppStorage("extraKeys") private var extraKeys = false
    @AppStorage("haptics") private var haptics = true
    @AppStorage("ctrlSize") private var ctrlSize = 58.0
    @AppStorage("ctrlOpacity") private var ctrlOpacity = 1.0
    @AppStorage("engine") private var engine = "standard"
    @AppStorage("fpsCap") private var fpsCap = "0"
    @AppStorage("showFps") private var showFps = false
    @AppStorage("cursorSpeed") private var cursorSpeed = 9.0

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Display")) {
                    Picker("Screen mode", selection: $scaleMode) {
                        Text("Auto (recommended)").tag("auto")
                        Text("Fit").tag("showAll")
                        Text("Fill (crop edges)").tag("noBorder")
                        Text("Stretch").tag("exactFit")
                    }
                    Picker("Quality", selection: $quality) {
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                        Text("Best").tag("best")
                    }
                    Toggle("Auto-rotate to match game", isOn: $autoLandscape)
                }
                Section(header: Text("Performance"),
                        footer: Text("Performance uses direct WebGL and low quality. Original loads the latest Ruffle from the internet.")) {
                    Picker("Flash engine", selection: $engine) {
                        Text("Standard").tag("standard")
                        Text("Performance").tag("perf")
                        Text("Original (online)").tag("cdn")
                    }
                    Picker("Frame rate", selection: $fpsCap) {
                        Text("Default").tag("0")
                        Text("30 FPS").tag("30")
                        Text("40 FPS").tag("40")
                        Text("50 FPS").tag("50")
                        Text("60 FPS").tag("60")
                    }
                    Toggle("Show FPS counter", isOn: $showFps)
                }
                Section(header: Text("Controls")) {
                    Toggle("On-screen controls", isOn: $controlsOn)
                    Toggle("WASD instead of arrows", isOn: $wasd)
                    Toggle("Extra buttons (C, Shift, Esc, R)", isOn: $extraKeys)
                    Toggle("Haptic feedback", isOn: $haptics)
                    VStack(alignment: .leading) {
                        Text("Button size: \(Int(ctrlSize))")
                        Slider(value: $ctrlSize, in: 40...80, step: 2)
                    }
                    VStack(alignment: .leading) {
                        Text("Cursor speed: \(Int(cursorSpeed))")
                        Slider(value: $cursorSpeed, in: 1...18, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text("Opacity: \(Int(ctrlOpacity * 100))%")
                        Slider(value: $ctrlOpacity, in: 0.2...1.0)
                    }
                }
                Section(header: Text("Storage")) {
                    HStack {
                        Text("Games")
                        Spacer()
                        Text("\(lib.files.count) · \(lib.storageText)").foregroundColor(.gray)
                    }
                    Button("Clear thumbnails") { lib.clearThumbs() }
                }
                Section(header: Text("About"), footer: Text("You can also drop SWF files into SWF Player › Games in the Files app.")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(version).foregroundColor(.gray)
                    }
                    Text("Powered by Ruffle")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    let onSave: (String) -> Void

    init(initial: String, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section(footer: Text("Leave empty to restore the automatic name.")) {
                    TextField("Game name", text: $text).disableAutocorrection(true)
                }
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(text); dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
