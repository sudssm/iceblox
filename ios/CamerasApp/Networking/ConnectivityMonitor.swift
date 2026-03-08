import Combine
import Network

final class ConnectivityMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "connectivity.monitor")

    @Published var isConnected = true

    var onReconnect: (() -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let wasDisconnected = !(self?.isConnected ?? true)
            let nowConnected = path.status == .satisfied
            DispatchQueue.main.async {
                self?.isConnected = nowConnected
            }
            if wasDisconnected && nowConnected {
                self?.onReconnect?()
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }
}
