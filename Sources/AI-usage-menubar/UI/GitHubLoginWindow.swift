import AppKit
import WebKit
import Foundation

final class GitHubLoginWindow: NSWindowController, WKNavigationDelegate {
    private var webView: WKWebView!
    private let onComplete: (String) -> Void

    init(onComplete: @escaping (String) -> Void) {
        self.onComplete = onComplete

        let wc = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        wc.title = "Connect GitHub"
        super.init(window: wc)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: wc.contentView!.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        wc.contentView?.addSubview(webView)

        let req = URLRequest(url: URL(string: "https://github.com/login")!)
        webView.load(req)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Check current URL and cookie store for session cookies
        if let url = webView.url {
            if url.host == "github.com" {
                checkForSessionCookies()
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // allow navigation and inspect
        decisionHandler(.allow)
    }

    private func checkForSessionCookies() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let names = Set(cookies.map { $0.name })
            if names.contains("_gh_sess") && names.contains("user_session") {
                // build header
                let header = CookieStorage.header(from: cookies.filter { names.contains($0.name) })
                DispatchQueue.main.async {
                    self.onComplete(header)
                    self.closeWindow()
                }
            }
        }
    }

    func closeWindow() {
        self.window?.close()
    }
}
