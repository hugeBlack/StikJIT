import Foundation
import SwiftUI
import WebKit
import JavaScriptCore

final class MiniToolRuntime: NSObject, ObservableObject {
    let tool: MiniToolBundle
    @Published var logs: [String] = []
    @Published var isReady: Bool = false

    let webView: WKWebView
    private var context: JSContext?

    private let messageHandlerName = "miniToolBridge"

    init(tool: MiniToolBundle) {
        self.tool = tool
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: MiniToolRuntime.frontendBridgeScript,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        controller.add(self, name: messageHandlerName)
        webView.navigationDelegate = self
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: messageHandlerName)
    }

    func start() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
        loadBackground()
        loadFrontend()
    }

    func reload() {
        start()
    }

    // MARK: - Loading

    private func loadFrontend() {
        guard FileManager.default.fileExists(atPath: tool.indexURL.path) else {
            appendLog("index.html missing for \(tool.name)")
            return
        }
        isReady = false
        let url = tool.indexURL
        webView.loadFileURL(url, allowingReadAccessTo: tool.url)
    }

    private func loadBackground() {
        context = JSContext()
        context?.exceptionHandler = { [weak self] _, exception in
            if let message = exception?.toString() {
                self?.appendLog("Background exception: \(message)")
            }
        }

        let sendToFrontend: @convention(block) (Any?) -> Void = { [weak self] payload in
            self?.deliverToFrontend(payload ?? NSNull())
        }
        
        let logFunction: @convention(block) (Any?) -> Void = { [weak self] msg in
            self?.appendLog(msg as? String ?? "Unable to decode log message.")
            
        }
        
        context?.setObject(sendToFrontend, forKeyedSubscript: "__miniToolPostMessage" as NSString)
        context?.setObject(logFunction, forKeyedSubscript: "__miniToolLog" as NSString)

        context?.evaluateScript(MiniToolRuntime.backgroundBridgeScript)

        do {
            let script = try String(contentsOf: tool.backgroundURL)
            context?.evaluateScript(script)
        } catch {
            appendLog("Failed to load background.js: \(error.localizedDescription)")
        }
    }

    private func deliverToBackground(_ payload: Any) {
        guard let receiver = context?.objectForKeyedSubscript("__miniToolReceive"),
              !receiver.isUndefined else {
            appendLog("Background handler is not ready")
            return
        }
        _ = receiver.call(withArguments: [payload])
    }

    private func deliverToFrontend(_ payload: Any) {
        guard let json = MiniToolRuntime.encodePayload(payload) else {
            appendLog("Unable to encode payload for frontend")
            return
        }
        DispatchQueue.main.async {
            let script = "window.miniTool && window.miniTool.__receive(\(json))"
            self.webView.evaluateJavaScript(script) { _, error in
                if let error {
                    self.appendLog("Frontend dispatch error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func appendLog(_ text: String) {
        DispatchQueue.main.async {
            self.logs.append(text)
        }
    }
}

// MARK: - WKScriptMessageHandler

extension MiniToolRuntime: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == messageHandlerName else { return }
        if let dict = message.body as? [String: Any], let payload = dict["payload"] {
            deliverToBackground(payload)
        } else {
            deliverToBackground(message.body)
        }
    }
}

// MARK: - WKNavigationDelegate

extension MiniToolRuntime: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        deliverToBackground(["type": "ui-ready", "tool": tool.name])
        deliverToFrontend(["type": "ready", "tool": tool.name])
    }
}

// MARK: - Scripts & Encoding

extension MiniToolRuntime {
    static let frontendBridgeScript = """
        window.miniTool = window.miniTool || {};
        window.miniTool.__handler = null;
        window.miniTool.onMessage = function(handler) { window.miniTool.__handler = handler; };
        window.miniTool.postMessage = function(payload) {
            window.webkit.messageHandlers.miniToolBridge.postMessage({ payload: payload });
        };
        window.miniTool.__receive = function(payload) {
            try {
                if (typeof window.miniTool.__handler === 'function') {
                    window.miniTool.__handler(payload);
                }
            } catch (err) {
                console.error(err);
            }
        };
    """

    static let backgroundBridgeScript = """
        var miniTool = this.miniTool || {};
        miniTool.__handler = null;
        miniTool.onMessage = function(handler) { miniTool.__handler = handler; };
        miniTool.postMessage = function(payload) { __miniToolPostMessage(payload); };
        miniTool.log = function(log) { __miniToolLog(log); }
        function __miniToolReceive(payload) {
            try {
                if (typeof miniTool.__handler === 'function') {
                    miniTool.__handler(payload);
                }
            } catch (err) {
                console.log(err);
            }
        }
        this.miniTool = miniTool;
    """

    static func encodePayload(_ payload: Any) -> String? {
        if JSONSerialization.isValidJSONObject(payload) {
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        if let string = payload as? String {
            let escaped = string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        if let number = payload as? NSNumber {
            return number.stringValue
        }
        return nil
    }
}
