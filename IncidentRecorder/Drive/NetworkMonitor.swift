import Foundation
import Network

/// Detecta cuándo vuelve el internet para reanudar las subidas de inmediato.
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// Cambios de conectividad (hilo principal).
    var onChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "network.monitor")
    private let lock = NSLock()
    private var reachable = true
    private var started = false

    var isReachable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reachable
    }

    func start() {
        lock.lock()
        let alreadyStarted = started
        started = true
        lock.unlock()
        guard !alreadyStarted else { return }

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isSatisfied = path.status == .satisfied
            self.lock.lock()
            let changed = isSatisfied != self.reachable
            self.reachable = isSatisfied
            self.lock.unlock()
            if isSatisfied {
                UploadCoordinator.shared.kick()
            }
            if changed {
                DispatchQueue.main.async {
                    self.onChange?(isSatisfied)
                }
            }
        }
        monitor.start(queue: queue)
    }
}
