import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .all
    }
}

@main
struct CamerasApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showCamera = AppConfig.autoStartCamera

    var body: some Scene {
        WindowGroup {
            if showCamera {
                ContentView()
                    .preferredColorScheme(.dark)
            } else {
                SplashScreenView(onStartCamera: { showCamera = true })
                    .preferredColorScheme(.dark)
            }
        }
    }
}
