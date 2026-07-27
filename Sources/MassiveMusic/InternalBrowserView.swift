import SwiftUI
import WebKit

struct InternalBrowserView: View {
    let url: URL
    let targetLanguage: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        EmbeddedBrowserView(url: url, targetLanguage: targetLanguage) { dismiss() }
            .frame(minWidth: 780, minHeight: 620)
    }
}

struct EmbeddedBrowserView: View {
    let url: URL
    let targetLanguage: String
    let onClose: () -> Void
    @StateObject private var navigation = BrowserNavigationController()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: navigation.goBack) {
                    Image(systemName: "chevron.backward")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!navigation.canGoBack)
                .help(targetLanguage == "ja" ? "前のページへ戻る" : "Go Back")
                .accessibilityLabel(targetLanguage == "ja" ? "前のページへ戻る" : "Go Back")

                Button(action: navigation.goForward) {
                    Image(systemName: "chevron.forward")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!navigation.canGoForward)
                .help(targetLanguage == "ja" ? "次のページへ進む" : "Go Forward")
                .accessibilityLabel(targetLanguage == "ja" ? "次のページへ進む" : "Go Forward")

                Text(url.host() ?? url.absoluteString).lineLimit(1)
                Spacer()
                Label(targetLanguage == "ja" ? "外部記事は日本語へ自動翻訳" : "External articles translate to English", systemImage: "character.book.closed")
                    .font(.caption).foregroundStyle(.secondary)
                Button(targetLanguage == "ja" ? "情報へ戻る" : "Back to Info", action: onClose)
            }.padding(10).background(.bar)
            WebContainer(url: url, targetLanguage: targetLanguage, navigation: navigation)
        }
    }
}

@MainActor
final class BrowserNavigationController: ObservableObject {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    private weak var webView: WKWebView?

    func attach(to webView: WKWebView) {
        self.webView = webView
        update(from: webView)
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }

    func update(from webView: WKWebView) {
        if canGoBack != webView.canGoBack { canGoBack = webView.canGoBack }
        if canGoForward != webView.canGoForward { canGoForward = webView.canGoForward }
    }
}

struct WebContainer: NSViewRepresentable {
    let url: URL
    let targetLanguage: String
    let navigation: BrowserNavigationController
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        context.coordinator.navigation = navigation
        navigation.attach(to: view)
        view.load(localizedRequest(url))
        return view
    }
    func makeCoordinator() -> Coordinator {
        Coordinator(targetLanguage: targetLanguage, requestedURL: url, navigation: navigation)
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.targetLanguage = targetLanguage
        context.coordinator.navigation = navigation
        navigation.attach(to: view)
        if context.coordinator.requestedURL != url {
            context.coordinator.requestedURL = url
            view.load(localizedRequest(url))
        }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.evaluateJavaScript(
            "document.querySelectorAll('video, audio').forEach(media => { media.pause(); media.removeAttribute('src'); media.load(); });"
        )
        view.stopLoading()
        view.navigationDelegate = nil
        view.loadHTMLString("", baseURL: nil)
    }

    private func localizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(targetLanguage == "ja" ? "ja-JP,ja;q=0.9" : "en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        return request
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var targetLanguage: String
        var requestedURL: URL
        weak var navigation: BrowserNavigationController?

        init(targetLanguage: String, requestedURL: URL, navigation: BrowserNavigationController) {
            self.targetLanguage = targetLanguage
            self.requestedURL = requestedURL
            self.navigation = navigation
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            self.navigation?.update(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.navigation?.update(from: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            navigation?.update(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame == true,
                  navigationAction.navigationType == .linkActivated,
                  let destination = navigationAction.request.url,
                  shouldTranslate(destination),
                  let translated = translationURL(for: destination) else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            webView.load(URLRequest(url: translated))
        }

        private func shouldTranslate(_ url: URL) -> Bool {
            guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
            return !host.contains("wikipedia.org")
                && !host.contains("news.google.")
                && !host.contains("translate.google.")
                && !host.contains("chordify.net")
        }

        private func translationURL(for url: URL) -> URL? {
            var components = URLComponents(string: "https://translate.google.com/translate")
            components?.queryItems = [
                URLQueryItem(name: "sl", value: "auto"),
                URLQueryItem(name: "tl", value: targetLanguage == "ja" ? "ja" : "en"),
                URLQueryItem(name: "u", value: url.absoluteString)
            ]
            return components?.url
        }
    }
}
