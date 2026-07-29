import AppKit
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
                Button {
                    navigation.openInDefaultBrowser(fallback: url)
                } label: {
                    Label(
                        targetLanguage == "ja" ? "ブラウザで開く" : "Open in Browser",
                        systemImage: "safari"
                    )
                }
                .help(targetLanguage == "ja" ? "ログインが必要なページを既定ブラウザで開く" : "Open pages that require sign-in in your default browser")
                Button(targetLanguage == "ja" ? "情報へ戻る" : "Back to Info", action: onClose)
            }.padding(10).background(.bar)
            GeometryReader { proxy in
                WebContainer(
                    url: url,
                    targetLanguage: targetLanguage,
                    navigation: navigation,
                    availableWidth: proxy.size.width
                )
            }
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

    func openInDefaultBrowser(fallback: URL) {
        NSWorkspace.shared.open(webView?.url ?? fallback)
    }

    func update(from webView: WKWebView) {
        if canGoBack != webView.canGoBack { canGoBack = webView.canGoBack }
        if canGoForward != webView.canGoForward { canGoForward = webView.canGoForward }
    }
}

struct WebContainer: NSViewRepresentable {
    let url: URL
    let targetLanguage: String
    let navigation: BrowserNavigationController
    let availableWidth: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        context.coordinator.navigation = navigation
        navigation.attach(to: view)
        view.load(localizedRequest(url))
        return view
    }
    func makeCoordinator() -> Coordinator {
        Coordinator(
            targetLanguage: targetLanguage,
            requestedURL: url,
            navigation: navigation,
            availableWidth: availableWidth
        )
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.targetLanguage = targetLanguage
        context.coordinator.navigation = navigation
        context.coordinator.availableWidth = availableWidth
        navigation.attach(to: view)
        if context.coordinator.requestedURL != url {
            context.coordinator.requestedURL = url
            view.load(localizedRequest(url))
        } else {
            context.coordinator.fitPage(in: view, availableWidth: availableWidth)
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
        var availableWidth: CGFloat
        weak var navigation: BrowserNavigationController?
        private var fitTask: Task<Void, Never>?
        private var lastFitRequestWidth: CGFloat?

        init(
            targetLanguage: String,
            requestedURL: URL,
            navigation: BrowserNavigationController,
            availableWidth: CGFloat
        ) {
            self.targetLanguage = targetLanguage
            self.requestedURL = requestedURL
            self.navigation = navigation
            self.availableWidth = availableWidth
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            self.navigation?.update(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.navigation?.update(from: webView)
            fitPage(in: webView, availableWidth: availableWidth, force: true)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            navigation?.update(from: webView)
        }

        func fitPage(in webView: WKWebView, availableWidth: CGFloat, force: Bool = false) {
            guard availableWidth > 0 else { return }
            if !force,
               let lastFitRequestWidth,
               abs(lastFitRequestWidth - availableWidth) < 1 {
                return
            }
            lastFitRequestWidth = availableWidth
            fitTask?.cancel()
            fitTask = Task { @MainActor [weak webView] in
                guard let webView else { return }
                webView.pageZoom = 1
                await Task.yield()
                let script = """
                    Math.max(
                        document.documentElement?.scrollWidth ?? 0,
                        document.body?.scrollWidth ?? 0,
                        document.documentElement?.clientWidth ?? 0
                    )
                    """
                guard !Task.isCancelled,
                      let value = try? await webView.evaluateJavaScript(script),
                      let contentWidth = value as? Double,
                      contentWidth > 0 else { return }
                guard !Task.isCancelled else { return }
                let fittedZoom = Double(max(0, availableWidth - 8)) / contentWidth
                webView.pageZoom = max(0.6, min(1, fittedZoom))
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame == true,
                  let destination = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if shouldOpenGoogleAuthenticationExternally(destination) {
                decisionHandler(.cancel)
                NSWorkspace.shared.open(destination)
                return
            }
            guard navigationAction.navigationType == .linkActivated,
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
            return !shouldOpenGoogleAuthenticationExternally(url)
                && !host.contains("wikipedia.org")
                && !host.contains("news.google.")
                && !host.contains("translate.google.")
                && !host.contains("chordify.net")
                && !host.contains("youtube.com")
                && !host.contains("youtu.be")
        }

        private func shouldOpenGoogleAuthenticationExternally(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            return host == "accounts.google.com"
                || host.hasSuffix(".accounts.google.com")
                || host == "accounts.youtube.com"
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
