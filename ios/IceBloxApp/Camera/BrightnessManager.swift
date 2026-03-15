import UIKit

struct BrightnessManager {
    private(set) var isDimmed = false
    private(set) var savedBrightness: CGFloat?
    private var restoreWorkItem: DispatchWorkItem?

    mutating func dim() {
        guard AppConfig.dimScreenDuringScanning else { return }
        if savedBrightness == nil {
            savedBrightness = UIScreen.main.brightness
        }
        UIScreen.main.brightness = AppConfig.dimBrightnessLevel
        isDimmed = true
    }

    mutating func restore() {
        guard isDimmed, let saved = savedBrightness else { return }
        cancelPendingRestore()
        UIScreen.main.brightness = saved
        isDimmed = false
    }

    mutating func temporarilyRestore(for duration: TimeInterval = 5.0) {
        guard isDimmed, let saved = savedBrightness else { return }
        cancelPendingRestore()
        UIScreen.main.brightness = saved
        isDimmed = false

        let workItem = DispatchWorkItem { [saved] in
            guard AppConfig.dimScreenDuringScanning else { return }
            if UIScreen.main.brightness == saved {
                UIScreen.main.brightness = AppConfig.dimBrightnessLevel
            }
        }
        restoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)

        // Re-mark as dimmed so the pending re-dim is expected
        isDimmed = true
    }

    mutating func teardown() {
        cancelPendingRestore()
        if let saved = savedBrightness {
            UIScreen.main.brightness = saved
        }
        savedBrightness = nil
        isDimmed = false
    }

    private mutating func cancelPendingRestore() {
        restoreWorkItem?.cancel()
        restoreWorkItem = nil
    }
}
