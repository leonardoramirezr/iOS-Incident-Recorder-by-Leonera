import Foundation

/// Sesión de URLSession en segundo plano: iOS sigue subiendo aunque la app se
/// suspenda o el teléfono se bloquee, y despierta la app al terminar.
final class BackgroundTransfer: NSObject, URLSessionDataDelegate {
    static let shared = BackgroundTransfer()

    /// Lo entrega iOS al despertar la app por eventos de esta sesión (ver AppDelegate).
    var systemCompletionHandler: (() -> Void)?

    private let lock = NSLock()
    private var responseBodies: [Int: Data] = [:]
    private var session: URLSession!

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: AppConfig.backgroundUploadSessionID)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// Crea la sesión (y con ello recibe los eventos pendientes de ejecuciones anteriores).
    func activate() {
        _ = session
    }

    /// Inicia la subida del archivo y devuelve el identificador de la tarea.
    func startUpload(request: URLRequest, fileURL: URL, jobID: UUID) -> Int {
        let task = session.uploadTask(with: request, fromFile: fileURL)
        task.taskDescription = jobID.uuidString
        task.resume()
        return task.taskIdentifier
    }

    func activeTaskIDs() async -> Set<Int> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Set<Int>, Never>) in
            session.getAllTasks { tasks in
                continuation.resume(returning: Set(tasks.map(\.taskIdentifier)))
            }
        }
    }

    func cancel(taskIDs: Set<Int>) async {
        guard !taskIDs.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.getAllTasks { tasks in
                for task in tasks where taskIDs.contains(task.taskIdentifier) {
                    task.cancel()
                }
                continuation.resume()
            }
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        responseBodies[dataTask.taskIdentifier, default: Data()].append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let body = responseBodies.removeValue(forKey: task.taskIdentifier) ?? Data()
        lock.unlock()
        guard let description = task.taskDescription, let jobID = UUID(uuidString: description) else { return }
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode
        let taskID = task.taskIdentifier
        Task {
            await UploadCoordinator.shared.handleBackgroundCompletion(
                jobID: jobID,
                taskID: taskID,
                statusCode: statusCode,
                body: body,
                error: error
            )
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task {
            // Da tiempo a encadenar el siguiente paso antes de que iOS vuelva a suspender la app.
            await UploadCoordinator.shared.waitUntilIdle(timeout: 20)
            await MainActor.run {
                let handler = self.systemCompletionHandler
                self.systemCompletionHandler = nil
                handler?()
            }
        }
    }
}
