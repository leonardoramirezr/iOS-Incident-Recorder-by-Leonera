import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Recrea la sesión en segundo plano para recibir resultados de subidas
        // que terminaron mientras la app no estaba en ejecución.
        BackgroundTransfer.shared.activate()
        NetworkMonitor.shared.start()
        BackgroundProcessing.register()
        Task {
            await UploadCoordinator.shared.reconcileBackgroundTasks()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == AppConfig.backgroundUploadSessionID else {
            completionHandler()
            return
        }
        BackgroundTransfer.shared.systemCompletionHandler = completionHandler
        BackgroundTransfer.shared.activate()
    }
}
