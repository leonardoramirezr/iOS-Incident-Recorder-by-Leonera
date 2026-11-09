import SwiftUI

/// Pantalla completamente negra durante la grabación. No muestra nada más: solo
/// escucha toques en las esquinas para reconocer el gesto de desbloqueo. La animación
/// del gesto se dibuja encima desde `MainCameraView`.
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
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .accessibilityLabel("Pantalla bloqueada")
    }
}
