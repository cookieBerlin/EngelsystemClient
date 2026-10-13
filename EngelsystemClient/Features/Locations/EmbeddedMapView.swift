import SwiftUI
import WebKit

/// The map page rendered inside `LocationDetailView` (`MapLinkMode.embedded`). A thin
/// `WKWebView` adapter: a non-persistent data store (no cookies or cache survive; the
/// page is fetched anew every time the screen appears) and navigation decided by
/// `MapLinkMode.navigationDecision` (web addresses only; they never open other apps). See ADR 0014.
struct EmbeddedMapView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        /// WebKit's "allow, but do not try to open a matching app" policy. It has no public
        /// name: `WKNavigationActionPolicy.allow` + 2 (the value Firefox, Brave and others
        /// use). Without it iOS hands links, form submissions and redirects to addresses
        /// such as Google Maps to the installed app (universal links), which leaves the
        /// app in the middle of the map's consent dialog. Falls back to a plain `.allow`
        /// if a future iOS stops recognising the raw value. See ADR 0014.
        static let allowWithoutOpeningApps = WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            switch MapLinkMode.navigationDecision(to: navigationAction.request.url) {
            case .allow: decisionHandler(Self.allowWithoutOpeningApps)
            case .cancel: decisionHandler(.cancel)
            }
        }

        /// Links that want a new window (`target="_blank"`) load in this view instead.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if MapLinkMode.allowsNavigation(to: navigationAction.request.url) {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
