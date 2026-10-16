import CoreLocation
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showTutorial = false

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $settings.showTimestamp) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fecha y hora en el video")
                            Text("2026-10-16T12:00:00-06:00 · arriba a la izquierda")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $settings.showCoordinates) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Coordenadas en el video")
                            Text("19.432608 N, -99.133209 W")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Video")
                } footer: {
                    Text("Se imprimen en cada cuadro del video, así que quedan también en Google Drive.")
                }

                Section {
                    Picker("Precisión", selection: $settings.locationAccuracy) {
                        ForEach(LocationAccuracyOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    BatteryNote(impact: settings.locationAccuracy.batteryImpact, text: settings.locationAccuracy.detail)
                } header: {
                    Text("Precisión de la ubicación")
                }

                Section {
                    Picker("Frecuencia", selection: $settings.locationInterval) {
                        ForEach(LocationUpdateInterval.allCases) { interval in
                            HStack {
                                Text(interval.title)
                                Spacer()
                                Text(interval.batteryImpact.label)
                                    .font(.caption)
                                    .foregroundStyle(color(for: interval.batteryImpact))
                            }
                            .tag(interval)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    BatteryNote(impact: settings.locationInterval.batteryImpact, text: settings.locationInterval.detail)
                } header: {
                    Text("Frecuencia de actualización de coordenadas")
                } footer: {
                    Text("Lo que más batería gasta es actualizar muy seguido (1 s, 5 s o 10 s): el GPS no se apaga nunca. Desde 15 s el GPS se enciende solo para cada lectura y descansa entre una y otra; con 1 min o más el consumo es bajo. «La máxima que permita el iPhone» gasta más que «a unos 10 metros».")
                }

                driveSection
                permissionsSection

                Section {
                    Button {
                        showTutorial = true
                    } label: {
                        Label("Ver animación del gesto", systemImage: "hand.tap")
                    }
                } header: {
                    Text("Desbloqueo")
                } footer: {
                    Text("Mientras grabas, la pantalla queda negra. Para volver a la app toca las 4 esquinas empezando abajo a la izquierda y en sentido horario: abajo-izquierda, arriba-izquierda, arriba-derecha y abajo-derecha.")
                }

                Section("Acerca de") {
                    LabeledContent("Versión", value: "\(AppConfig.version) (\(AppConfig.buildNumber))")
                    LabeledContent("Build", value: AppConfig.buildTag)
                    LabeledContent("Tiempo en pantalla", value: AppConfig.familyControlsEnabled ? "Incluido" : "No incluido en este build")
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showTutorial) {
                GestureTutorialView(autoDismiss: false) { showTutorial = false }
            }
        }
    }

    private func color(for impact: BatteryImpact) -> Color {
        switch impact {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    @ViewBuilder
    private var driveSection: some View {
        let auth = model.auth
        Section {
            switch auth.status {
            case .notConfigured:
                StatusLabel(kind: .warning, text: "Este build no tiene el client ID de Google (GOOGLE_IOS_CLIENT_ID). Los videos se guardan solo en el iPhone.")
            case .signedIn:
                StatusLabel(kind: .ok, text: auth.email.map { "Conectado como \($0)" } ?? "Conectado")
                if let url = model.uploads.rootFolderURL {
                    Link(destination: url) {
                        Label("Abrir carpeta en Google Drive", systemImage: "folder")
                    }
                }
                LabeledContent("Bloques pendientes", value: "\(model.uploads.pendingCount)")
                if let reason = model.uploads.blockedReason {
                    StatusLabel(kind: .info, text: reason)
                }
                Button {
                    Task { await UploadCoordinator.shared.retryNow() }
                } label: {
                    Label("Reintentar subidas ahora", systemImage: "arrow.clockwise.icloud")
                }
                Button(role: .destructive) {
                    Task { await auth.signOut() }
                } label: {
                    Label("Desconectar Google Drive", systemImage: "xmark.icloud")
                }
            case .signingIn:
                ProgressView("Conectando…")
            case .signedOut, .needsReauthorization:
                if auth.status == .needsReauthorization {
                    StatusLabel(kind: .warning, text: "Google pidió volver a iniciar sesión.")
                }
                Button {
                    Task {
                        if await auth.signIn() {
                            UploadCoordinator.shared.kick()
                        }
                    }
                } label: {
                    Label("Conectar Google Drive", systemImage: "icloud.and.arrow.up")
                }
                if let error = auth.lastError {
                    StatusLabel(kind: .error, text: error)
                }
            }
        } header: {
            Text("Google Drive")
        } footer: {
            Text("Cada bloque de 1 minuto se sube a la carpeta «\(AppConfig.driveRootFolderName)» en cuanto termina. Sin internet se guarda en el iPhone y se sube solo cuando vuelve la conexión.")
        }
    }

    @ViewBuilder
    private var permissionsSection: some View {
        Section("Permisos") {
            switch model.screenTime.status {
            case .approved:
                StatusLabel(kind: .ok, text: "Tiempo en pantalla: las demás apps se bloquean al grabar.")
            case .unavailableInBuild:
                StatusLabel(kind: .warning, text: "Tiempo en pantalla no está incluido en este build (requiere aprobación de Apple, ver README).")
            case .denied, .notDetermined:
                Button {
                    Task { await model.screenTime.requestAuthorization() }
                } label: {
                    Label("Permitir Tiempo en pantalla", systemImage: "hourglass")
                }
                if let error = model.screenTime.lastError {
                    StatusLabel(kind: .error, text: error)
                }
            }

            switch model.location.authorizationStatus {
            case .authorizedAlways:
                StatusLabel(kind: .ok, text: "Ubicación: siempre.")
            case .authorizedWhenInUse:
                StatusLabel(kind: .warning, text: "Ubicación: solo al usar la app. Cámbiala a «Siempre» para registrar el recorrido y subir en segundo plano.")
                Button("Abrir Ajustes", action: openAppSettings)
            case .notDetermined:
                Button {
                    model.location.requestAuthorization()
                } label: {
                    Label("Permitir ubicación", systemImage: "location")
                }
            default:
                StatusLabel(kind: .error, text: "Ubicación denegada.")
                Button("Abrir Ajustes", action: openAppSettings)
            }
            if model.location.isAuthorized && !model.location.hasPreciseLocation {
                StatusLabel(kind: .warning, text: "Activa «Ubicación exacta» en Ajustes para obtener coordenadas precisas.")
            }

            if model.cameraAccess != .authorized || !model.microphoneAuthorized {
                StatusLabel(kind: .warning, text: "Falta acceso a la cámara o al micrófono.")
                Button("Abrir Ajustes", action: openAppSettings)
            } else {
                StatusLabel(kind: .ok, text: "Cámara y micrófono.")
            }
        }
    }
}

private struct BatteryNote: View {
    let impact: BatteryImpact
    let text: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(impact.label).font(.subheadline.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: impact.symbol)
                .foregroundStyle(impact == .high ? Color.red : (impact == .medium ? Color.orange : Color.green))
        }
    }
}
