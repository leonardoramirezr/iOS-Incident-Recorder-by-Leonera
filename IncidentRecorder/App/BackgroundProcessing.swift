import BackgroundTasks
import Foundation

/// Tarea de procesamiento en segundo plano (respaldo): iOS despierta la app cuando
/// hay red para terminar subidas pendientes si la app quedó suspendida.
enum BackgroundProcessing {
    static func register() {
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: AppConfig.uploadProcessingTaskID, using: nil) { task in
            handle(task)
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: AppConfig.uploadProcessingTaskID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGTask) {
        let once = OneShot()
        let work = Task {
            await UploadCoordinator.shared.waitUntilIdle(timeout: 25)
            let pending = await UploadCoordinator.shared.hasPendingWork()
            if pending { schedule() }
            if once.fire() { task.setTaskCompleted(success: true) }
        }
        task.expirationHandler = {
            work.cancel()
            schedule()
            if once.fire() { task.setTaskCompleted(success: false) }
        }
    }
}
