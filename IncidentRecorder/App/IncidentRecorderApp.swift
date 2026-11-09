import SwiftUI

@main
struct IncidentRecorderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { url in
                    // Widget «IR» de la pantalla de bloqueo (también en arranque en frío).
                    model.handleOpenURL(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    model.scenePhaseChanged(newPhase)
                }
        }
    }
}
