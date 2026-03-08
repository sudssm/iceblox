import Foundation
import Combine

enum LogLevel {
    case debug, warning, error
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let tag: String
    let message: String
}

final class DebugLog: ObservableObject {
    static let shared = DebugLog()

    private let maxEntries = 50
    @Published var entries: [LogEntry] = []

    private let lock = NSLock()

    func d(_ tag: String, _ message: String) {
        #if DEBUG
        NSLog("[\(tag)] \(message)")
        print("[\(tag)] \(message)")
        #endif
        add(LogEntry(timestamp: Date(), level: .debug, tag: tag, message: message))
    }

    func w(_ tag: String, _ message: String) {
        #if DEBUG
        NSLog("[WARN][\(tag)] \(message)")
        print("[WARN][\(tag)] \(message)")
        #endif
        add(LogEntry(timestamp: Date(), level: .warning, tag: tag, message: message))
    }

    func e(_ tag: String, _ message: String) {
        #if DEBUG
        NSLog("[ERROR][\(tag)] \(message)")
        print("[ERROR][\(tag)] \(message)")
        #endif
        add(LogEntry(timestamp: Date(), level: .error, tag: tag, message: message))
    }

    private func add(_ entry: LogEntry) {
        lock.lock()
        defer { lock.unlock() }
        let update = {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async { update() }
        }
    }
}
