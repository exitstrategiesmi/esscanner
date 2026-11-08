//  SceneDelegate.swift
//  ESScanner — Exit Strategies Field Estimator (native shell)
//
//  Creates the window programmatically (no storyboard) with the
//  web-view shell as the root and only screen.

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = ShellViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
