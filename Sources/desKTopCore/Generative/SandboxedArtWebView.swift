import AppKit
import WebKit
import Foundation

public enum SandboxedWebError: Error {
    case invalidURL
    case pathTraversalDetected
    case snapshotTimeout
    case renderFailed
}

/// Custom scheme handler for isolated local token files preventing path traversal
public final class IsolatedArtSchemeHandler: NSObject, WKURLSchemeHandler {
    private let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        super.init()
    }

    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(SandboxedWebError.invalidURL)
            return
        }

        // Relative path validation - reject path traversal
        let path = url.path
        if path.contains("..") {
            urlSchemeTask.didFailWithError(SandboxedWebError.pathTraversalDetected)
            return
        }

        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let targetFile = rootDirectory.appendingPathComponent(cleanPath)

        guard targetFile.path.hasPrefix(rootDirectory.path),
              let data = try? Data(contentsOf: targetFile) else {
            let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            urlSchemeTask.didReceive(notFound)
            urlSchemeTask.didFinish()
            return
        }

        // Determine MIME type
        let ext = targetFile.pathExtension.lowercased()
        let mime: String = {
            switch ext {
            case "html", "htm": return "text/html"
            case "js": return "application/javascript"
            case "css": return "text/css"
            case "svg": return "image/svg+xml"
            case "png": return "image/png"
            case "jpg", "jpeg": return "image/jpeg"
            case "gif": return "image/gif"
            case "webp": return "image/webp"
            default: return "application/octet-stream"
            }
        }()

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Content-Security-Policy": "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob:; connect-src 'none'; frame-src 'none'; object-src 'none';"
            ]
        )!

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

/// Sandboxed ephemeral WebKit view for executing untrusted generative art
public final class SandboxedArtWebView: NSView {
    public let webView: WKWebView

    @MainActor
    public init(tokenDirectory: URL? = nil, frame: NSRect = .zero) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        // Content Security Policy
        let userScript = WKUserScript(
            source: """
            const meta = document.createElement('meta');
            meta.httpEquiv = 'Content-Security-Policy';
            meta.content = "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob:; connect-src 'none'; frame-src 'none'; object-src 'none';";
            document.head ? document.head.appendChild(meta) : document.addEventListener('DOMContentLoaded', () => document.head.appendChild(meta));
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(userScript)

        if let dir = tokenDirectory {
            let handler = IsolatedArtSchemeHandler(rootDirectory: dir)
            config.setURLSchemeHandler(handler, forURLScheme: "desktop-art")
        }

        self.webView = WKWebView(frame: frame, configuration: config)
        super.init(frame: frame)

        wantsLayer = true
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Loads raw HTML string with base URL
    @MainActor
    public func loadHTML(_ html: String, baseURL: URL? = nil) {
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// Headless snapshot capturing a high-resolution Retina image of current frame
    @MainActor
    public func captureSnapshot() async throws -> NSImage {
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        return try await webView.takeSnapshot(configuration: config)
    }
}
