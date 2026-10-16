import SwiftUI

/// Pantalla principal: video en vivo de la cámara trasera y la frontal, botón de
/// grabar abajo al centro. Durante la grabación se cubre con la pantalla negra.
struct MainCameraView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var showIncidents = false
    @State private var playerIncident: Incident?
    @State private var confirmFinish = false

    var body: some View {
        ZStack {
            CameraPreview(preview: model.capture.backPreview)
                .ignoresSafeArea()

            cameraUnavailableMessage

            VStack(spacing: 0) {
                topBar
                Spacer()
                statusBanner
                    .padding(.bottom, 14)
                bottomControls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if model.isLocked {
                LockScreenView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.isLocked)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(model)
        }
        .sheet(isPresented: $showIncidents) {
            IncidentListView()
                .environment(model)
        }
        .fullScreenCover(item: $playerIncident) { incident in
            IncidentPlayerView(incident: incident)
                .environment(model)
        }
        .confirmationDialog("¿Finalizar la incidencia?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finalizar incidencia", role: .destructive) {
                model.finishIncident()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Lo próximo que grabes será una incidencia nueva. Los bloques ya guardados se siguen subiendo a Google Drive.")
        }
        .alert(
            "Aviso",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onAppear {
            model.startCameraIfPossible()
        }
    }

    // MARK: - Partes

    private var topBar: some View {
        HStack(alignment: .top) {
            OverlayPreview()
            Spacer(minLength: 8)
            if model.hasFrontCamera {
                CameraPreview(preview: model.capture.frontPreview)
                    .frame(width: 104, height: 185)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.85), lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 6)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var cameraUnavailableMessage: some View {
        switch model.cameraAccess {
        case .denied:
            messageCard(
                icon: "video.slash",
                text: "La app no tiene acceso a la cámara.",
                action: ("Abrir Ajustes", openAppSettings)
            )
        case .notDetermined:
            messageCard(icon: "video", text: "Permite el acceso a la cámara y al micrófono para grabar.", action: ("Permitir", {
                Task { await model.requestCameraAndMicrophone(); model.startCameraIfPossible() }
            }))
        case .authorized:
            if case .failed(let message) = model.sessionState {
                messageCard(icon: "exclamationmark.triangle", text: message, action: ("Reintentar", {
                    model.startCameraIfPossible()
                }))
            }
        }
    }

    private func messageCard(icon: String, text: String, action: (String, () -> Void)) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.largeTitle)
            Text(text)
                .multilineTextAlignment(.center)
            Button(action.0, action: action.1)
                .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(32)
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch model.phase {
        case .recording:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Label("REC \(OverlayFormat.duration(model.recordedDuration(at: context.date)))", systemImage: "record.circle.fill")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.red, in: Capsule())
            }
        case .paused:
            VStack(spacing: 6) {
                Label("En pausa · \(OverlayFormat.duration(model.recordedDuration(at: Date())))", systemImage: "pause.circle.fill")
                    .font(.system(.headline, design: .monospaced))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.orange, in: Capsule())
                UploadBadge()
            }
            .foregroundStyle(.white)
        case .idle:
            UploadBadge()
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        HStack(alignment: .center) {
            switch model.phase {
            case .idle:
                CircleIconButton(systemName: "film.stack", label: "Incidencias") { showIncidents = true }
                Spacer()
                RecordButton(mode: .record) { model.startRecording() }
                    .disabled(model.cameraAccess != .authorized)
                Spacer()
                CircleIconButton(systemName: "gearshape.fill", label: "Ajustes") { showSettings = true }
            case .recording:
                CircleIconButton(systemName: "lock.fill", label: "Pantalla negra") { model.lockAgain() }
                Spacer()
                RecordButton(mode: .pause) { model.pause() }
                Spacer()
                CircleIconButton(systemName: "gearshape.fill", label: "Ajustes") { showSettings = true }
            case .paused:
                CircleIconButton(systemName: "play.rectangle.fill", label: "Ver video") {
                    playerIncident = model.activeIncident
                }
                .disabled((model.activeIncident?.chunks.isEmpty) ?? true)
                Spacer()
                RecordButton(mode: .record) { model.resume() }
                Spacer()
                CircleIconButton(systemName: "stop.fill", label: "Finalizar") { confirmFinish = true }
            }
        }
        .padding(.horizontal, 8)
    }
}

/// Vista previa de los textos que se imprimen en el video.
struct OverlayPreview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.settings.showTimestamp || model.settings.showCoordinates {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    if model.settings.showTimestamp {
                        Text(OverlayFormat.timestamp(context.date))
                    }
                    if model.settings.showCoordinates {
                        Text(model.location.latest?.overlayText ?? "Ubicación no disponible")
                    }
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

/// Estado de las subidas a Google Drive.
struct UploadBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let uploads = model.uploads
        let text: String
        let symbol: String
        switch model.auth.status {
        case .notConfigured:
            text = "Google Drive no configurado en este build"
            symbol = "icloud.slash"
        case .signedOut, .needsReauthorization:
            text = "Google Drive sin conectar · se guarda en el iPhone"
            symbol = "icloud.slash"
        case .signingIn:
            text = "Conectando Google Drive…"
            symbol = "icloud"
        case .signedIn:
            if !uploads.isNetworkReachable && uploads.pendingCount > 0 {
                text = "Sin internet · \(uploads.pendingCount) bloque(s) por subir"
                symbol = "wifi.slash"
            } else if uploads.pendingCount > 0 {
                text = "Subiendo a Drive · \(uploads.pendingCount) pendiente(s)"
                symbol = "icloud.and.arrow.up"
            } else {
                text = "Todo respaldado en Google Drive"
                symbol = "checkmark.icloud"
            }
        }
        return Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
    }
}
