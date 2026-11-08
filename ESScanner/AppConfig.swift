//  AppConfig.swift
//  ESScanner — Exit Strategies Field Estimator (native shell)
//
//  The two constants the shell is built around. Everything else is
//  derived from these.

import Foundation

enum AppConfig {

    /// The web estimator hosted inside the shell.
    ///
    /// Currently the STAGING estimator (same URL the earlier one-file
    /// shell prototype used) so the first builds can be field-tested
    /// without touching production. BEFORE the first cloud build:
    /// confirm this is the live served path of the estimator, and only
    /// switch it to production on the owner's explicit approval.
    static let estimatorURL = URL(string: "https://exitstrategiesmi-quotes-staging.exitstrategiesmi.workers.dev/estimator/")!

    /// Name of the WKScriptMessageHandler the web page calls.
    ///
    /// Must match the web side EXACTLY: js/app.js (and the drop-in
    /// web-bridge/scan-bridge.js) test for
    /// `window.webkit.messageHandlers.scanRoom` and post
    /// `{ roomId: <number> }` to it.
    static let scanHandlerName = "scanRoom"
}
