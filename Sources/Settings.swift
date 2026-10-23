import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var lib: Library
    @AppStorage("scaleMode") private var scaleMode = "showAll"
    @AppStorage("quality") private var quality = "high"
    @AppStorage("autoLandscape") private var autoLandscape = true
    @AppStorage("controlsOn") private var controlsOn = true
    @AppStorage("wasd") private var wasd = false
    @AppStorage("extraKeys") private var extraKeys = false
    @AppStorage("haptics") private var haptics = true
    @AppStorage("ctrlSize") private var ctrlSize = 58.0
    @AppStorage("ctrlOpacity") private var ctrlOpacity = 1.0

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Display")) {
                    Picker("Screen mode", selection: $scaleMode) {
                        Text("Fit (poora dikhao)").tag("showAll")
                        Text("Fill (crop)").tag("noBorder")
                        Text("Stretch").tag("exactFit")
                        Text("Original size").tag("noScale")
                    }
                    Picker("Quality", selection: $quality) {
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                        Text("Best").tag("best")
                    }
                    Toggle("Landscape games auto-rotate", isOn: $autoLandscape)
                }
                Section(header: Text("Controls")) {
                    Toggle("On-screen controls", isOn: $controlsOn)
                    Toggle("WASD (arrows ki jagah)", isOn: $wasd)
                    Toggle("Extra buttons (C, Shift, Esc, R)", isOn: $extraKeys)
                    Toggle("Haptic feedback", isOn: $haptics)
                    VStack(alignment: .leading) {
                        Text("Button size: \(Int(ctrlSize))")
                        Slider(value: $ctrlSize, in: 40...80, step: 2)
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
                    Button("Thumbnails saaf karo") { lib.clearThumbs() }
                }
                Section(header: Text("About"), footer: Text("Files app mein SWF Player > Games folder mein bhi SWF daal sakte ho.")) {
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
                Section(footer: Text("Khali chhodoge toh auto naam wapas aa jayega.")) {
                    TextField("Game ka naam", text: $text).disableAutocorrection(true)
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
