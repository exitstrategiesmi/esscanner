//  AppDelegate.swift
//  ESScanner — Exit Strategies Field Estimator (native shell)
//
//  Minimal UIKit app delegate. The real work lives in
//  ShellViewController (WKWebView host + JS bridge) and
//  RoomScanViewController (RoomPlan capture).
//
//  UIKit was chosen over SwiftUI for this shell on purpose: the app is a
//  single full-screen view controller, and a pure UIKit lifecycle keeps
//  the WKWebView and its script-message handler alive for exactly as
//  long as the window — no UIViewControllerRepresentable coordinator
//  lifetime edge cases on a first cloud build.

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // The name must match UISceneConfigurationName in Info.plist.
        return UISceneConfiguration(name: "Default Configuration",
                                    sessionRole: connectingSceneSession.role)
    }
}
