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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(url.host() ?? url.absoluteString).lineLimit(1)
                Spacer()
                Label(targetLanguage == "ja" ? "外部記事は日本語へ自動翻訳" : "External articles translate to English", systemImage: "character.book.closed")
                    .font(.caption).foregroundStyle(.secondary)
                Button(targetLanguage == "ja" ? "情報へ戻る" : "Back to Info", action: onClose)
            }.padding(10).background(.bar)
            WebContainer(url: url, targetLanguage: targetLanguage)
        }
    }
}

struct WebContainer: NSViewRepresentable {
    let url: URL
    let targetLanguage: String
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        view.load(localizedRequest(url))
        return view
    }
    func makeCoordinator() -> Coordinator { Coordinator(targetLanguage: targetLanguage) }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.targetLanguage = targetLanguage
        if view.url != url { view.load(localizedRequest(url)) }
    }

    private func localizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(targetLanguage == "ja" ? "ja-JP,ja;q=0.9" : "en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        return request
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var targetLanguage: String
        init(targetLanguage: String) { self.targetLanguage = targetLanguage }

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
            return !host.contains("wikipedia.org") && !host.contains("news.google.") && !host.contains("translate.google.")
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
