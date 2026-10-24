import SwiftUI
import WebKit

// MARK: - Browser state + helpers
struct BrowserState {
    var canBack = false
    var canForward = false
    var loading = false
    var url = ""
    var title = ""
}

final class BrowserHolder {
    weak var web: WKWebView?

    func load(_ text: String) {
        guard let u = BrowserHolder.normalize(text) else { return }
        web?.load(URLRequest(url: u))
    }

    static func normalize(_ raw: String) -> URL? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        let low = t.lowercased()
        if low.hasPrefix("http://") || low.hasPrefix("https://") { return URL(string: t) }
        if t.contains(" ") || !t.contains(".") {
            let q = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t
            return URL(string: "https://duckduckgo.com/?q=" + q)
        }
        return URL(string: "https://" + t)
    }
}

// MARK: - WKWebView wrapper (plain website, no Ruffle involved)
struct BrowserView: UIViewRepresentable {
    let holder: BrowserHolder
    let startURL: String
    let desktop: Bool
    let onState: (BrowserState) -> Void

    func makeCoordinator() -> Coord { Coord(onState: onState, desktop: desktop) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.isOpaque = false
        wv.backgroundColor = .black
        holder.web = wv
        holder.load(startURL)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        context.coordinator.onState = onState
        if context.coordinator.desktop != desktop {
            context.coordinator.desktop = desktop
            wv.reload()
        }
    }

    final class Coord: NSObject, WKNavigationDelegate, WKUIDelegate {
        var onState: (BrowserState) -> Void
        var desktop: Bool

        init(onState: @escaping (BrowserState) -> Void, desktop: Bool) {
            self.onState = onState
            self.desktop = desktop
        }

        private func push(_ w: WKWebView, loading: Bool) {
            onState(BrowserState(canBack: w.canGoBack, canForward: w.canGoForward, loading: loading,
                                 url: w.url?.absoluteString ?? "", title: w.title ?? ""))
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            push(webView, loading: true)
        }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            push(webView, loading: true)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            push(webView, loading: false)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            push(webView, loading: false)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            push(webView, loading: false)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     preferences: WKWebpagePreferences,
                     decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            preferences.preferredContentMode = desktop ? .desktop : .mobile
            decisionHandler(.allow, preferences)
        }

        // target="_blank" / window.open -> open in the same view
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }
}

// MARK: - Web Games screen
struct WebGamesView: View {
    let onClose: () -> Void

    @AppStorage("webHome") private var home = "https://www.friv.com"
    @AppStorage("webDesktop") private var desktop = false
    @State private var holder = BrowserHolder()
    @State private var st = BrowserState()
    @State private var field = ""
    @State private var barOpen = true
    @State private var landscape = false
    @FocusState private var fieldFocused: Bool

    private let sites: [(String, String)] = [
        ("Friv", "https://www.friv.com"),
        ("Friv Max", "https://www.frivmax.com"),
        ("Poki", "https://poki.com"),
        ("CrazyGames", "https://www.crazygames.com")
    ]

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private func iconBtn(_ name: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .foregroundColor(enabled ? .white : .gray)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
        }
        .disabled(!enabled)
    }

    private func close() {
        if landscape { Orient.set(.portrait) }
        onClose()
    }

    private var sitesMenu: some View {
        Menu {
            ForEach(sites, id: \.0) { s in
                Button(s.0) { holder.load(s.1) }
            }
            Divider()
            Button { home = st.url.isEmpty ? home : st.url } label: {
                Label("Set this page as home", systemImage: "house")
            }
            Button { desktop.toggle() } label: {
                Label("Request desktop site", systemImage: desktop ? "checkmark" : "desktopcomputer")
            }
        } label: {
            Image(systemName: "star.fill").foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.12)).clipShape(Circle())
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            iconBtn("xmark") { close() }
            iconBtn("chevron.left", enabled: st.canBack) { holder.web?.goBack() }
            iconBtn("chevron.right", enabled: st.canForward) { holder.web?.goForward() }
            iconBtn(st.loading ? "xmark.circle" : "arrow.clockwise") {
                if st.loading { holder.web?.stopLoading() } else { holder.web?.reload() }
            }
            TextField("Search or enter site", text: $field)
                .focused($fieldFocused)
                .keyboardType(.webSearch)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .submitLabel(.go)
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
                .onSubmit {
                    holder.load(field)
                    fieldFocused = false
                }
            sitesMenu
            if isPhone {
                iconBtn("rotate.right") {
                    landscape.toggle()
                    Orient.set(landscape ? .landscape : .portrait)
                }
            }
            iconBtn("chevron.up") { barOpen = false }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(red: 0.08, green: 0.07, blue: 0.14))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                if barOpen { toolbar }
                BrowserView(holder: holder, startURL: home, desktop: desktop, onState: { s in
                    st = s
                    if !fieldFocused { field = s.url }
                })
                .ignoresSafeArea(edges: .bottom)
            }
            if !barOpen {
                Button { barOpen = true } label: {
                    Image(systemName: "chevron.down").foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.6)).clipShape(Circle())
                }
                .padding(10)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { field = home }
    }
}
