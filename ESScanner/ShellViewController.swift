//  ShellViewController.swift
//  ESScanner — Exit Strategies Field Estimator (native shell)
//
//  The shell's only screen: a full-screen WKWebView hosting the web
//  estimator, plus the JavaScript bridge that gives the page its one
//  native capability — RoomPlan scanning.
//
//  Bridge contract (must stay in sync with js/app.js and with
//  web-bridge/scan-bridge.js):
//
//    web -> native : webkit.messageHandlers.scanRoom.postMessage({ roomId })
//    native -> web : window.handleScanResult(<ScanPayload JSON>)
//                    window.handleScanError(<{ code, message } JSON>)
//
//  The roomId in the request is informational on this side: the web
//  page itself tracks which room is waiting (pendingScanRoomId) and
//  merges the returned payload into that room. The native side only
//  supplies measurements; every number remains editable in the page.

import UIKit
import WebKit
import RoomPlan
import AVFoundation

final class ShellViewController: UIViewController {

    private var webView: WKWebView!
    private var isScanning = false

    // Shown only if the estimator itself cannot be loaded.
    private var loadErrorView: UIView?
    private var loadErrorLabel: UILabel?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let userContentController = WKUserContentController()
        // WKUserContentController retains its handlers strongly, so the
        // handler registered here is a weak proxy — registering self
        // directly would create a retain cycle and leak the shell.
        userContentController.add(WeakScriptMessageHandler(delegate: self),
                                  name: AppConfig.scanHandlerName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        // Default (persistent) store: estimator drafts and any sign-in
        // survive app restarts, exactly as they do in the browser PWA.
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        view.addSubview(webView)
        self.webView = webView

        webView.load(URLRequest(url: AppConfig.estimatorURL))
    }

    // MARK: - Scan flow

    private func beginScan() {
        guard !isScanning else { return }   // one capture at a time

        guard RoomCaptureSession.isSupported else {
            deliverError(code: "lidar-unsupported",
                         message: "This device does not have a LiDAR scanner.")
            showAlert(title: "Scanner unavailable",
                      message: "Room scanning needs a LiDAR-equipped iPhone or iPad Pro. Manual measurements in the estimator work as always.")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentScanner()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.presentScanner()
                    } else {
                        self?.cameraDenied()
                    }
                }
            }
        default:    // .denied or .restricted
            cameraDenied()
        }
    }

    private func cameraDenied() {
        deliverError(code: "camera-denied",
                     message: "Camera access is off for this app.")
        showAlert(title: "Camera access is off",
                  message: "The room scanner needs the camera. You can turn it on in Settings, or keep typing measurements in by hand.",
                  offerSettings: true)
    }

    private func presentScanner() {
        isScanning = true
        let scanner = RoomScanViewController { [weak self] outcome in
            guard let self else { return }
            self.isScanning = false
            switch outcome {
            case .completed(let payload):
                self.deliver(payload)
            case .cancelled:
                self.deliverError(code: "cancelled", message: "Scan cancelled.")
            case .failed(let code, let message):
                self.deliverError(code: code, message: message)
            }
        }
        present(scanner, animated: true)
    }

    // MARK: - Delivery to the web page

    private func deliver(_ payload: ScanPayload) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            deliverError(code: "encode-failed",
                         message: "The scan could not be prepared for the estimator.")
            return
        }
        // The payload JSON is a valid JavaScript object literal, and
        // handleScanResult accepts an object as well as a string.
        evaluate("window.handleScanResult && window.handleScanResult(\(json));")
    }

    private func deliverError(code: String, message: String) {
        let error = ScanErrorMessage(code: code, message: message)
        guard let data = try? JSONEncoder().encode(error),
              let json = String(data: data, encoding: .utf8) else { return }
        evaluate("window.handleScanError && window.handleScanError(\(json));")
    }

    private func evaluate(_ javaScript: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(javaScript, completionHandler: nil)
        }
    }

    // MARK: - Alerts

    private func showAlert(title: String, message: String, offerSettings: Bool = false) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if offerSettings,
           let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
                UIApplication.shared.open(settingsURL)
            })
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Estimator load failure

    private func showLoadError(_ message: String) {
        hideLoadError()
        let container = UIView(frame: view.bounds)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        var retryConfig = UIButton.Configuration.filled()
        retryConfig.title = "Try again"
        let retryButton = UIButton(configuration: retryConfig)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.addTarget(self, action: #selector(retryLoad), for: .touchUpInside)

        container.addSubview(label)
        container.addSubview(retryButton)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -32),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -32),
            retryButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            retryButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 20)
        ])
        view.addSubview(container)
        loadErrorView = container
        loadErrorLabel = label
    }

    private func hideLoadError() {
        loadErrorView?.removeFromSuperview()
        loadErrorView = nil
        loadErrorLabel = nil
    }

    @objc private func retryLoad() {
        hideLoadError()
        webView.load(URLRequest(url: AppConfig.estimatorURL))
    }
}

// MARK: - Bridge messages from the web page

extension ShellViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == AppConfig.scanHandlerName else { return }
        // Message body is { roomId: <number> } — informational only;
        // the page tracks the pending room itself. See file header.
        beginScan()
    }
}

// MARK: - Load state

extension ShellViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        showLoadError("The estimator could not be loaded. Check the connection and try again.")
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        showLoadError("The estimator stopped loading. Try again.")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideLoadError()
    }
}

// MARK: - Weak script-message handler

/// WKUserContentController retains its message handlers strongly.
/// Registering the view controller directly would keep it (and the
/// web view) alive forever, so messages are routed through this
/// weak proxy instead — the standard fix for the classic WKWebView
/// handler retain cycle.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
