import Foundation

final class UserSettings: ObservableObject {
    static let shared = UserSettings()

    @Published var pushNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(pushNotificationsEnabled, forKey: Self.pushNotificationsKey)
        }
    }

    private static let pushNotificationsKey = "pushNotificationsEnabled"

    init() {
        if UserDefaults.standard.object(forKey: Self.pushNotificationsKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.pushNotificationsKey)
        }
        self.pushNotificationsEnabled = UserDefaults.standard.bool(forKey: Self.pushNotificationsKey)
    }
}
