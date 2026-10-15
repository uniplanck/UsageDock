import AppKit
import WebKit

/// Loads grok.com inside an isolated `WKWebsiteDataStore` and asks that page
/// for the Settings → Usage credits config. Session cookies stay in the data
/// store; this type never reads them out or writes them to preferences.
@MainActor
enum GrokWebSession {
    struct Payload {
        var interpretation: GrokWebCredits.Interpretation
        var diagnostic: String
    }

    static func fetchCredits(sessionID: UUID) async -> Payload {
        let fetcher = GrokWebPageFetcher(sessionID: sessionID)
        return await fetcher.fetch()
    }
}

@MainActor
final class GrokWebLoginPresenter: NSObject, WKNavigationDelegate, NSWindowDelegate {
    static let shared = GrokWebLoginPresenter()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var statusField: NSTextField?
    private var onFinish: (() -> Void)?
    private var finished = false

    func present(sessionID: UUID, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        finished = false

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: sessionID)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 720), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        let status = NSTextField(labelWithString: "Sign in, then return to grok.com.")
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        statusField = status

        let done = NSButton(title: "Done — read usage", target: self, action: #selector(finishLogin))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelLogin))
        cancel.bezelStyle = .rounded

        let buttons = NSStackView(views: [status, NSView(), done, cancel])
        buttons.orientation = .horizontal
        buttons.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        buttons.spacing = 8

        let column = NSStackView(views: [webView, buttons])
        column.orientation = .vertical
        column.spacing = 0
        webView.setContentHuggingPriority(.defaultLow, for: .vertical)
        buttons.setContentHuggingPriority(.required, for: .vertical)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to Grok"
        window.minSize = NSSize(width: 720, height: 520)
        window.contentView = column
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        webView.load(URLRequest(url: GrokWebCredits.usagePage))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let host = webView.url?.host ?? ""
        if host == "grok.com" || host.hasSuffix(".grok.com") {
            statusField?.stringValue = "grok.com is open. Choose Done to read Settings → Usage."
        } else {
            statusField?.stringValue = "Finish signing in. This window comes back to grok.com when the session is ready."
        }
    }

    func windowWillClose(_ notification: Notification) {
        webView?.navigationDelegate = nil
        webView = nil
        window = nil
        if !finished {
            onFinish = nil
        }
    }

    @objc private func finishLogin() {
        finished = true
        let callback = onFinish
        onFinish = nil
        window?.close()
        callback?()
    }

    @objc private func cancelLogin() {
        finished = false
        onFinish = nil
        window?.close()
    }
}

@MainActor
private final class GrokWebPageFetcher: NSObject, WKNavigationDelegate {
    private let sessionID: UUID
    private var webView: WKWebView?
    private var window: NSWindow?
    private var loadContinuation: CheckedContinuation<URL, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    func fetch() async -> GrokWebSession.Payload {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: sessionID)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 800), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        self.window = window
        defer {
            self.webView?.navigationDelegate = nil
            self.webView = nil
            self.window?.close()
            self.window = nil
        }

        do {
            let pageURL = try await load(webView)
            let host = pageURL.host ?? ""
            guard host == "grok.com" || host.hasSuffix(".grok.com") else {
                return signedOut("Grok web login is not active. Sign in again on grok.com.")
            }
            let raw = try await webView.callAsyncJavaScript(
                Self.fetchScript,
                arguments: ["endpoint": GrokWebCredits.endpoint.absoluteString],
                in: nil,
                contentWorld: .page
            )
            guard let object = raw as? [String: Any] else {
                return unavailable("Grok web usage request returned no response. UsageDock will not invent 0%.")
            }
            let status = (object["status"] as? NSNumber)?.intValue
                ?? (object["status"] as? Int)
                ?? 0
            let contentType = object["contentType"] as? String ?? ""
            let grpcHeader = (object["grpcStatus"] as? String).flatMap(Int.init)
            let body: Data
            if let encoded = object["bodyBase64"] as? String, let decoded = Data(base64Encoded: encoded) {
                body = decoded
            } else {
                body = Data()
            }
            let finalURL = object["url"] as? String ?? ""
            if let host = URL(string: finalURL)?.host, host != "grok.com", !host.hasSuffix(".grok.com") {
                return signedOut("Grok web login is not active. Sign in again on grok.com.")
            }
            let verdict = GrokWebCredits.interpret(
                body: body,
                httpStatus: status,
                contentType: contentType,
                headerGrpcStatus: grpcHeader
            )
            return GrokWebSession.Payload(interpretation: verdict.interpretation, diagnostic: verdict.diagnostic)
        } catch {
            let host = webView.url?.host ?? ""
            if host != "grok.com", !host.hasSuffix(".grok.com") {
                return signedOut("Grok web login is not active. Sign in again on grok.com.")
            }
            return unavailable("Grok web usage could not be loaded. UsageDock will not invent 0%.")
        }
    }

    private func signedOut(_ message: String) -> GrokWebSession.Payload {
        let verdict = GrokWebCredits.interpret(body: Data("<html>".utf8), httpStatus: 401, contentType: "text/html")
        return GrokWebSession.Payload(interpretation: .needsReLogin(message), diagnostic: verdict.diagnostic)
    }

    private func unavailable(_ message: String) -> GrokWebSession.Payload {
        GrokWebDiagnostics.store("result: unavailable\n\(message)")
        return GrokWebSession.Payload(interpretation: .unavailable(message), diagnostic: message)
    }

    private func load(_ webView: WKWebView) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                self?.resume(throwing: URLError(.timedOut))
            }
            webView.load(URLRequest(url: GrokWebCredits.usagePage))
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        settleTask?.cancel()
        settleTask = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        let host = url.host ?? ""
        if host == "grok.com" || host.hasSuffix(".grok.com") {
            resume(returning: url)
            return
        }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self, let current = webView.url else { return }
            self.resume(returning: current)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resume(throwing: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resume(throwing: error)
    }

    private func resume(returning url: URL) {
        timeoutTask?.cancel()
        timeoutTask = nil
        settleTask?.cancel()
        settleTask = nil
        loadContinuation?.resume(returning: url)
        loadContinuation = nil
    }

    private func resume(throwing error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        settleTask?.cancel()
        settleTask = nil
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    private static let fetchScript = """
    const response = await fetch(endpoint, {
      method: "POST",
      credentials: "include",
      cache: "no-store",
      headers: {
        "content-type": "application/grpc-web+proto",
        "x-grpc-web": "1",
        "x-user-agent": "connect-es/2.1.1",
        "accept": "application/grpc-web+proto"
      },
      body: new Uint8Array([0, 0, 0, 0, 0])
    });
    const bytes = new Uint8Array(await response.arrayBuffer());
    let binary = "";
    for (let index = 0; index < bytes.length; index += 0x8000) {
      binary += String.fromCharCode.apply(null, bytes.subarray(index, index + 0x8000));
    }
    return {
      status: response.status,
      url: String(response.url || ""),
      contentType: response.headers.get("content-type") || "",
      grpcStatus: response.headers.get("grpc-status"),
      bodyBase64: btoa(binary)
    };
    """
}
