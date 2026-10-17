import SwiftUI

/// Pantalla completamente negra durante la grabación. No muestra nada más: solo
/// escucha toques en las esquinas para reconocer el gesto de desbloqueo.
struct LockScreenView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            Color.black
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        model.registerUnlockTap(at: value.location, in: proxy.size)
                    }
                )
        }
        .ignoresSafeArea()
        .overlay {
            if model.showGestureTutorial {
                GestureTutorialView {
                    model.showGestureTutorial = false
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: model.showGestureTutorial)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .accessibilityLabel("Pantalla bloqueada")
    }
}
