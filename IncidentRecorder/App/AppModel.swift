import AVFoundation
import Observation
import SwiftUI
import UIKit

enum RecorderPhase: String, Codable {
    case idle
    case recording
    case paused
}

enum CameraAccess: Equatable {
    case notDetermined
    case denied
    case authorized
}

/// Estado central de la app. Se usa desde el hilo principal.
@Observable
final class AppModel {
    let settings = SettingsStore()
    let incidents = IncidentStore()
    let location = LocationService()
    let auth = GoogleAuthService()
    let screenTime = ScreenTimeService()
    let uploads = UploadStatus.shared
    let capture: CaptureEngine

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }

    private(set) var phase: RecorderPhase = .idle
    /// Pantalla negra activa (solo se quita con el gesto de las 4 esquinas).
    private(set) var isLocked = false
    var showGestureTutorial = false
    private(set) var activeIncidentID: UUID?
    private(set) var cameraAccess: CameraAccess = .notDetermined
    private(set) var microphoneAuthorized = false
    private(set) var sessionState: CaptureEngine.SessionState = .idle
    private(set) var hasFrontCamera = false
    private(set) var runStartedAt: Date?
    private(set) var accumulatedBeforeRun: TimeInterval = 0
    private(set) var lastRecordingError: String?
    var alertMessage: String?

    @ObservationIgnored private var unlockSequence = UnlockSequence()
    @ObservationIgnored private var savedBrightness: CGFloat?
    @ObservationIgnored private var resumeRecordingWhenReady = false
    @ObservationIgnored private var isInForeground = true
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private enum Keys {
        static let onboarding = "app.hasCompletedOnboarding"
        static let recorderState = "app.recorderState"
    }

    private struct PersistedState: Codable {
        var incidentID: UUID?
        var phase: RecorderPhase
        var isLocked: Bool
    }

    init() {
        capture = CaptureEngine()
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.onboarding)
        restorePersistedState()
        wireCallbacks()
        refreshPermissions()
        updateOverlay()
        configureLocation()
        if !isLocked {
            // Por si la app se cerró con las demás apps bloqueadas.
            screenTime.removeShield()
        }
    }

    // MARK: - Estado derivado

    var activeIncident: Incident? {
        activeIncidentID.flatMap { incidents.incident($0) }
    }

    func recordedDuration(at date: Date) -> TimeInterval {
        accumulatedBeforeRun + (runStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    var isCameraReady: Bool {
        cameraAccess == .authorized && sessionState == .running
    }

    // MARK: - Configuración

    private func wireCallbacks() {
        capture.onSegmentFinished = { [weak self] segment in
            self?.handleFinishedSegment(segment)
        }
        capture.onStateChange = { [weak self] state, hasFront in
            self?.handleSessionState(state, hasFront: hasFront)
        }
        capture.onRecordingError = { [weak self] message in
            self?.lastRecordingError = message
        }
        location.onSample = { [weak self] sample in
            self?.handleLocationSample(sample)
        }
        settings.onChange = { [weak self] in
            self?.updateOverlay()
            self?.configureLocation()
        }
        NetworkMonitor.shared.onChange = { reachable in
            UploadStatus.shared.setNetworkReachable(reachable)
        }
        uploads.onChange = { [weak self] in
            // En segundo plano la ubicación mantiene viva la app solo mientras haya subidas pendientes.
            guard let self, !self.isInForeground else { return }
            self.configureLocation()
        }
    }

    private func updateOverlay() {
        capture.updateOverlay(CaptureEngine.OverlayConfiguration(
            showTimestamp: settings.showTimestamp,
            showCoordinates: settings.showCoordinates,
            coordinateText: location.latest?.overlayText
        ))
    }

    /// Decide cuándo y cómo se usa la ubicación.
    func configureLocation() {
        let mode: LocationService.Mode
        if !hasCompletedOnboarding {
            mode = .off
        } else if phase != .idle {
            mode = .incident
        } else if isInForeground {
            mode = settings.showCoordinates ? .preview : .off
        } else if uploads.hasPending {
            mode = .keepAlive
        } else {
            mode = .off
        }
        location.configure(mode: mode, accuracy: settings.locationAccuracy, interval: settings.locationInterval)
    }

    func refreshPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: cameraAccess = .authorized
        case .notDetermined: cameraAccess = .notDetermined
        default: cameraAccess = .denied
        }
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        screenTime.refresh()
    }

    @MainActor
    func requestCameraAndMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refreshPermissions()
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        configureLocation()
        startCameraIfPossible()
        UploadCoordinator.shared.kick()
    }

    func startCameraIfPossible() {
        guard hasCompletedOnboarding, cameraAccess == .authorized else { return }
        capture.startSession()
    }

    // MARK: - Grabación

    func startRecording() {
        guard phase != .recording else { return }
        guard cameraAccess == .authorized else {
            alertMessage = "Permite el acceso a la cámara en Ajustes para grabar."
            return
        }
        let incident: Incident
        if let id = activeIncidentID, let existing = incidents.incident(id) {
            incident = existing
        } else {
            incident = incidents.createIncident()
            activeIncidentID = incident.id
        }
        capture.startRecording(target: CaptureEngine.RecordingTarget(
            incidentID: incident.id,
            directory: IncidentStore.directory(for: incident.id),
            nextIndex: incident.nextChunkIndex
        ))
        accumulatedBeforeRun = incident.totalDuration
        runStartedAt = Date()
        phase = .recording
        lastRecordingError = nil
        UIApplication.shared.isIdleTimerDisabled = true
        lock(showTutorial: true)
        configureLocation()
        location.requestFreshSample()
        persistState()
    }

    func pause() {
        guard phase == .recording else { return }
        capture.stopRecording()
        if let runStartedAt {
            accumulatedBeforeRun += Date().timeIntervalSince(runStartedAt)
        }
        runStartedAt = nil
        phase = .paused
        UIApplication.shared.isIdleTimerDisabled = false
        if isLocked {
            unlock()
        }
        screenTime.removeShield()
        persistState()
    }

    func resume() {
        startRecording()
    }

    /// Termina la incidencia: lo siguiente que se grabe será una incidencia nueva.
    func finishIncident() {
        if phase == .recording {
            capture.stopRecording()
        }
        if let id = activeIncidentID {
            incidents.markEnded(id)
            if let incident = incidents.incident(id) {
                Task { await UploadCoordinator.shared.enqueueLocationLog(incident: incident) }
            }
        }
        activeIncidentID = nil
        phase = .idle
        runStartedAt = nil
        accumulatedBeforeRun = 0
        UIApplication.shared.isIdleTimerDisabled = false
        if isLocked {
            unlock()
        }
        screenTime.removeShield()
        configureLocation()
        persistState()
    }

    func deleteIncident(_ id: UUID) {
        guard id != activeIncidentID else { return }
        incidents.delete(id)
        Task { await UploadCoordinator.shared.removeJobs(for: id) }
    }

    private func handleFinishedSegment(_ segment: FinishedSegment) {
        let chunk = IncidentChunk(
            id: UUID(),
            index: segment.index,
            fileName: segment.url.lastPathComponent,
            remoteName: String(format: "bloque-%04d_", segment.index) + OverlayFormat.fileSafeTimestamp(segment.startedAt) + ".mov",
            startedAt: segment.startedAt,
            duration: segment.duration,
            byteCount: segment.byteCount
        )
        guard let incident = incidents.addChunk(chunk, to: segment.incidentID) else { return }
        Task {
            await UploadCoordinator.shared.enqueueChunk(incident: incident, chunk: chunk)
            await UploadCoordinator.shared.enqueueLocationLog(incident: incident)
        }
    }

    private func handleSessionState(_ state: CaptureEngine.SessionState, hasFront: Bool) {
        sessionState = state
        hasFrontCamera = hasFront
        if state == .running, resumeRecordingWhenReady {
            resumeRecordingWhenReady = false
            startRecording()
        }
    }

    private func handleLocationSample(_ sample: LocationSample) {
        updateOverlay()
        if phase != .idle, let id = activeIncidentID {
            incidents.appendLocation(sample, to: id)
        }
    }

    // MARK: - Pantalla negra y gesto de desbloqueo

    private func lock(showTutorial: Bool) {
        isLocked = true
        showGestureTutorial = showTutorial
        unlockSequence.reset()
        screenTime.applyShield()
        dimScreen()
        persistState()
    }

    /// Vuelve a poner la pantalla negra sin pausar la grabación.
    func lockAgain() {
        guard phase == .recording else { return }
        lock(showTutorial: false)
    }

    func registerUnlockTap(at point: CGPoint, in size: CGSize) {
        guard isLocked else { return }
        if showGestureTutorial {
            showGestureTutorial = false
        }
        if unlockSequence.register(ScreenCorner.corner(at: point, in: size)) {
            unlock()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func unlock() {
        isLocked = false
        showGestureTutorial = false
        unlockSequence.reset()
        screenTime.removeShield()
        restoreBrightness()
        persistState()
    }

    private func currentScreen() -> UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen
    }

    private func dimScreen() {
        guard isInForeground, let screen = currentScreen() else { return }
        if savedBrightness == nil {
            savedBrightness = screen.brightness
        }
        screen.brightness = 0
    }

    private func restoreBrightness() {
        guard let savedBrightness else { return }
        currentScreen()?.brightness = savedBrightness
        self.savedBrightness = nil
    }

    // MARK: - Ciclo de vida

    func scenePhaseChanged(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            didBecomeActive()
        case .background:
            didEnterBackground()
        default:
            break
        }
    }

    private func didBecomeActive() {
        isInForeground = true
        refreshPermissions()
        startCameraIfPossible()
        if isLocked {
            dimScreen()
            screenTime.applyShield()
        }
        configureLocation()
        Task { @MainActor in
            await self.auth.refreshStatus()
        }
        Task {
            await UploadCoordinator.shared.reconcileBackgroundTasks()
        }
    }

    private func didEnterBackground() {
        isInForeground = false
        restoreBrightness()
        if phase == .recording {
            // iOS no deja usar la cámara en segundo plano: se cierra el bloque en curso
            // y se sube; al volver a primer plano la grabación continúa en un bloque nuevo.
            beginBackgroundTask()
            capture.flushCurrentSegment { [weak self] in
                self?.endBackgroundTask()
            }
        }
        configureLocation()
        if uploads.hasPending {
            BackgroundProcessing.schedule()
        }
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "finish-segment") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Persistencia

    private func persistState() {
        let state = PersistedState(incidentID: activeIncidentID, phase: phase, isLocked: isLocked)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Keys.recorderState)
        }
    }

    /// Si la app se cerró a mitad de una incidencia, la retoma (y sigue grabando).
    private func restorePersistedState() {
        guard let data = UserDefaults.standard.data(forKey: Keys.recorderState),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data),
              let id = state.incidentID,
              let incident = incidents.incident(id),
              !incident.isFinished else { return }
        activeIncidentID = id
        accumulatedBeforeRun = incident.totalDuration
        switch state.phase {
        case .recording:
            phase = .paused
            resumeRecordingWhenReady = true
        case .paused:
            phase = .paused
        case .idle:
            phase = .idle
            activeIncidentID = nil
        }
        isLocked = state.isLocked && phase != .idle
    }
}
