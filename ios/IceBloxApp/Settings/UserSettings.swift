import Foundation

final class UserSettings: ObservableObject {
    static let shared = UserSettings()

    @Published var pushNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(pushNotificationsEnabled, forKey: Self.pushNotificationsKey)
        }
    }

    @Published var userDebugEnabled: Bool {
        didSet {
            UserDefaults.standard.set(userDebugEnabled, forKey: Self.userDebugKey)
        }
    }

    private static let pushNotificationsKey = "pushNotificationsEnabled"
    private static let userDebugKey = "userDebugEnabled"

    private init() {
        if UserDefaults.standard.object(forKey: Self.pushNotificationsKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.pushNotificationsKey)
        }
        self.pushNotificationsEnabled = UserDefaults.standard.bool(forKey: Self.pushNotificationsKey)
        self.userDebugEnabled = UserDefaults.standard.bool(forKey: Self.userDebugKey)
    }
}
