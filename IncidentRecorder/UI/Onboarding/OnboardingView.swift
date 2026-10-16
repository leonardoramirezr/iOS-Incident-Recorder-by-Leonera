import CoreLocation
import SwiftUI

/// Primer arranque: conecta Google Drive y pide los permisos de Tiempo en
/// pantalla, ubicación (siempre) y cámara/micrófono, explicando para qué.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome, drive, screenTime, location, camera
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.red : Color.white.opacity(0.2))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            ScrollView {
                content
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .drive: drive
        case .screenTime: screenTime
        case .location: locationStep
        case .camera: camera
        }
    }

    private func next() {
        if let following = Step(rawValue: step.rawValue + 1) {
            step = following
        }
    }

    // MARK: - Pasos

    private var welcome: some View {
        StepLayout(
            icon: "record.circle",
            title: AppConfig.displayName,
            message: "Graba una incidencia con las cámaras frontal y trasera a la vez. El video se guarda en el iPhone en bloques de 1 minuto y cada bloque se sube a tu Google Drive en cuanto termina."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(symbol: "moon.fill", text: "Mientras grabas la pantalla se ve negra, como apagada.")
                FeatureRow(symbol: "square.stack.3d.up.fill", text: "Bloques de 1 minuto: se suben aunque no termines de grabar.")
                FeatureRow(symbol: "wifi.slash", text: "Sin internet también graba; sube todo cuando vuelve la conexión.")
                FeatureRow(symbol: "clock.badge.checkmark", text: "Fecha, hora y coordenadas impresas en el video.")
            }
            Button("Comenzar", action: next)
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var drive: some View {
        let auth = model.auth
        return StepLayout(
            icon: "externaldrive.badge.icloud",
            title: "Conecta Google Drive",
            message: "Cada bloque de 1 minuto se sube a la carpeta «\(AppConfig.driveRootFolderName)» de tu Drive en cuanto se guarda en el iPhone. Si no hay internet se queda en el teléfono y se sube solo al volver la conexión, aunque la app no esté en pantalla o el teléfono esté bloqueado."
        ) {
            FeatureRow(symbol: "lock.shield", text: "La app solo puede ver y modificar los archivos que ella misma crea en tu Drive.")
            switch auth.status {
            case .notConfigured:
                StatusLabel(kind: .warning, text: "Este build no tiene configurado Google Drive (falta GOOGLE_IOS_CLIENT_ID, ver README). Puedes grabar igualmente: los videos se guardan en el iPhone.")
                Button("Continuar", action: next)
                    .buttonStyle(PrimaryButtonStyle())
            case .signedIn:
                StatusLabel(kind: .ok, text: auth.email.map { "Conectado como \($0)" } ?? "Google Drive conectado")
                Button("Continuar", action: next)
                    .buttonStyle(PrimaryButtonStyle())
            case .signingIn:
                ProgressView("Conectando…")
                    .tint(.white)
            case .signedOut, .needsReauthorization:
                if let error = auth.lastError {
                    StatusLabel(kind: .error, text: error)
                }
                Button("Conectar Google Drive") {
                    Task {
                        if await auth.signIn() {
                            UploadCoordinator.shared.kick()
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Ahora no", action: next)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var screenTime: some View {
        let service = model.screenTime
        return StepLayout(
            icon: "hourglass",
            title: "Permiso de Tiempo en pantalla",
            message: "Se pide para bloquear las demás apps mientras grabas una incidencia: si alguien intenta abrir otra app solo verá una pantalla negra, como si el teléfono estuviera apagado. Se desbloquean con un gesto: tocar las 4 esquinas de la pantalla empezando abajo a la izquierda y en sentido horario."
        ) {
            switch service.status {
            case .approved:
                StatusLabel(kind: .ok, text: "Permiso concedido.")
                Button("Continuar", action: next)
                    .buttonStyle(PrimaryButtonStyle())
            case .unavailableInBuild:
                StatusLabel(kind: .warning, text: "Este build todavía no incluye Tiempo en pantalla: para instalarlo fuera del App Store Apple debe aprobar la capacidad Family Controls (ver README). Mientras tanto la pantalla negra funciona dentro de la app.")
                Button("Continuar", action: next)
                    .buttonStyle(PrimaryButtonStyle())
            case .notDetermined, .denied:
                if let error = service.lastError {
                    StatusLabel(kind: .error, text: error)
                }
                Button("Permitir Tiempo en pantalla") {
                    Task { await service.requestAuthorization() }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Ahora no", action: next)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var locationStep: some View {
        let location = model.location
        return StepLayout(
            icon: "location.fill",
            title: "Ubicación, también en segundo plano",
            message: "La ubicación se imprime como coordenadas en el video. Además, durante una incidencia la app sigue registrando tu recorrido aunque cambies de app o bloquees el teléfono, y eso la mantiene activa para terminar de subir los bloques a Google Drive en cuanto haya internet. Cuando iOS lo pregunte, elige «Permitir al usar la app» y después «Cambiar a Permitir siempre»."
        ) {
            switch location.authorizationStatus {
            case .authorizedAlways:
                StatusLabel(kind: .ok, text: "Ubicación permitida siempre.")
                if !location.hasPreciseLocation {
                    StatusLabel(kind: .warning, text: "Activa «Ubicación exacta» en Ajustes para que las coordenadas sean precisas.")
                }
                Button("Continuar", action: next)
                    .buttonStyle(PrimaryButtonStyle())
            case .authorizedWhenInUse:
                StatusLabel(kind: .warning, text: "Solo «al usar la app». Para que funcione con el teléfono bloqueado cámbiala a «Siempre».")
                Button("Permitir siempre") {
                    location.requestAuthorization()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Abrir Ajustes", action: openAppSettings)
                Button("Continuar así", action: next)
                    .foregroundStyle(.secondary)
            case .notDetermined:
                Button("Permitir ubicación") {
                    location.requestAuthorization()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Ahora no", action: next)
                    .foregroundStyle(.secondary)
            default:
                StatusLabel(kind: .error, text: "La ubicación está desactivada para esta app.")
                Button("Abrir Ajustes", action: openAppSettings)
                    .buttonStyle(PrimaryButtonStyle())
                Button("Continuar sin ubicación", action: next)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var camera: some View {
        StepLayout(
            icon: "video.fill",
            title: "Cámara y micrófono",
            message: "Para grabar con la cámara trasera y la frontal al mismo tiempo, con audio."
        ) {
            switch model.cameraAccess {
            case .authorized:
                StatusLabel(kind: model.microphoneAuthorized ? .ok : .warning, text: model.microphoneAuthorized ? "Cámara y micrófono permitidos." : "Cámara permitida; sin micrófono el video no tendrá audio.")
                Button("Empezar") {
                    model.completeOnboarding()
                }
                .buttonStyle(PrimaryButtonStyle())
            case .notDetermined:
                Button("Permitir cámara y micrófono") {
                    Task { await model.requestCameraAndMicrophone() }
                }
                .buttonStyle(PrimaryButtonStyle())
            case .denied:
                StatusLabel(kind: .error, text: "Sin acceso a la cámara no se puede grabar.")
                Button("Abrir Ajustes", action: openAppSettings)
                    .buttonStyle(PrimaryButtonStyle())
                Button("Continuar") {
                    model.completeOnboarding()
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StepLayout<Actions: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: icon)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.red)
                .frame(height: 80)
                .padding(.top, 24)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 14) {
                actions()
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: 520)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.red)
                .frame(width: 26)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
