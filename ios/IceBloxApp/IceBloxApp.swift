import Combine
import os
import SwiftUI
import UIKit
import UserNotifications

private let appLog = Logger(subsystem: "com.iceblox.app", category: "network")

class NavigationState: ObservableObject {
    @Published var showMap = false
    @Published var returnToCamera = false
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var navigationState: NavigationState?
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .all
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if !AppConfig.skipNotificationRequest && UserSettings.shared.pushNotificationsEnabled {
            requestNotificationPermission(application: application)
        }
        // Connectivity probe at launch (synchronous for console capture)
        let baseURL = AppConfig.serverBaseURL
        NSLog("[Probe] Server URL: %@", baseURL.absoluteString)
        let healthURL = baseURL.appendingPathComponent("/healthz")
        NSLog("[Probe] Testing: %@", healthURL.absoluteString)
        let sem = DispatchSemaphore(value: 0)
        var probeRequest = URLRequest(url: healthURL)
        probeRequest.timeoutInterval = 5
        URLSession.shared.dataTask(with: probeRequest) { _, response, error in
            if let error {
                NSLog("[Probe] FAILED: %@", error.localizedDescription)
            } else if let http = response as? HTTPURLResponse {
                NSLog("[Probe] OK: status=%d", http.statusCode)
            } else {
                NSLog("[Probe] No HTTP response")
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 6)
        NSLog("[Probe] Done")
        return true
    }

    private func requestNotificationPermission(application: UIApplication) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                DebugLog.shared.e("Push", "Authorization error: \(error.localizedDescription)")
                return
            }
            if granted {
                DebugLog.shared.d("Push", "Notification permission granted")
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            } else {
                DebugLog.shared.d("Push", "Notification permission denied")
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = DeviceTokenHelper.hexString(from: deviceToken)
        DebugLog.shared.d("Push", "APNs token: \(token)")
        DeviceTokenHelper.registerToken(token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        DebugLog.shared.e("Push", "Failed to register: \(error.localizedDescription)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        if let sightingId = userInfo["sighting_id"] {
            DebugLog.shared.d("Push", "Foreground notification, sighting_id: \(sightingId)")
        }
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        if identifier == "background-pause" {
            DebugLog.shared.d("Push", "Notification tapped, returning to camera")
            DispatchQueue.main.async { [weak self] in
                self?.navigationState?.returnToCamera = true
            }
        } else {
            DebugLog.shared.d("Push", "Notification tapped, opening map")
            DispatchQueue.main.async { [weak self] in
                self?.navigationState?.showMap = true
            }
        }
        completionHandler()
    }
}

enum DeviceTokenHelper {
    static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func registerToken(_ token: String) {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let url = AppConfig.serverBaseURL.appendingPathComponent(AppConfig.devicesEndpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")

        let body: [String: String] = ["token": token, "platform": "ios"]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            DebugLog.shared.e("Push", "Failed to serialize device registration body")
            return
        }
        request.httpBody = httpBody

        registerWithRetry(request: request, attempt: 0)
    }

    private static func registerWithRetry(request: URLRequest, attempt: Int) {
        guard attempt < AppConfig.retryMaxAttempts else {
            DebugLog.shared.e("Push", "Device registration failed after \(attempt) attempts")
            return
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                DebugLog.shared.w("Push", "Device registration attempt \(attempt + 1) failed: \(error.localizedDescription)")
                let delay = min(AppConfig.retryInitialDelay * pow(2.0, Double(attempt)), AppConfig.retryMaxDelay)
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    registerWithRetry(request: request, attempt: attempt + 1)
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                DebugLog.shared.d("Push", "Device registered successfully")
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                DebugLog.shared.w("Push", "Device registration returned status \(statusCode)")
                let delay = min(AppConfig.retryInitialDelay * pow(2.0, Double(attempt)), AppConfig.retryMaxDelay)
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    registerWithRetry(request: request, attempt: attempt + 1)
                }
            }
        }.resume()
    }
}

@main
struct IceBloxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var navigationState = NavigationState()
    @State private var showCamera = AppConfig.autoStartCamera

    var body: some Scene {
        WindowGroup {
            Group {
                if showCamera {
                    ContentView(onExitToSplash: { showCamera = false })
                        .preferredColorScheme(.dark)
                } else {
                    SplashScreenView(onStartCamera: { showCamera = true })
                        .preferredColorScheme(.dark)
                }
            }
            .sheet(isPresented: $navigationState.showMap) {
                MapView()
            }
            .onAppear {
                appDelegate.navigationState = navigationState
            }
            .onReceive(navigationState.$returnToCamera) { shouldReturn in
                if shouldReturn {
                    showCamera = true
                    navigationState.returnToCamera = false
                }
            }
        }
    }
}
