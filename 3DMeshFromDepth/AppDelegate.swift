//
//  AppDelegate.swift
//  3DMeshFromDepth
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        
        let mainVC = MainViewController()
        let mainNavController = UINavigationController(rootViewController: mainVC)
        let appCoordinator = AppCoordinator()
        mainVC.coordinator = appCoordinator
        self.window?.rootViewController = mainNavController
        self.window?.makeKeyAndVisible()
        return true
    }
}

