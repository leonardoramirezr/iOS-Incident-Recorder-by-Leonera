import AVFoundation
import UIKit

/// Controla las cámaras (trasera + frontal a la vez cuando el iPhone lo permite),
/// el micrófono y la escritura del video en bloques de 1 minuto.
///
/// Colas:
/// - `sessionQueue`: configuración y arranque de la sesión.
/// - `dataQueue`: cuadros de video/audio, composición y escritura.
/// Los callbacks públicos se invocan siempre en el hilo principal.
final class CaptureEngine: NSObject {
    struct RecordingTarget {
        let incidentID: UUID
        let directory: URL
        var nextIndex: Int
    }

    enum SessionState: Equatable {
        case idle
        case running
        case interrupted
        case failed(String)
    }

    struct OverlayConfiguration: Equatable {
        var showTimestamp = true
        var showCoordinates = true
        var coordinateText: String?
    }

    /// Tamaño del video final (vertical, 1080 × 1920).
    static let outputSize = CGSize(width: 1080, height: 1920)

    let backPreview: CameraPreviewView
    let frontPreview: CameraPreviewView
    let supportsDualCamera: Bool

    /// Bloque terminado y guardado (hilo principal).
    var onSegmentFinished: ((FinishedSegment) -> Void)?
    /// Cambios de estado de la sesión (hilo principal).
    var onStateChange: ((SessionState, Bool) -> Void)?
    /// Errores al grabar (hilo principal).
    var onRecordingError: ((String) -> Void)?

    private let session: AVCaptureSession
    private let sessionQueue = DispatchQueue(label: "capture.session")
    private let dataQueue = DispatchQueue(label: "capture.data", qos: .userInitiated)
    private let backVideoOutput = AVCaptureVideoDataOutput()
    private let frontVideoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    // sessionQueue
    private var isConfigured = false
    private var backDevice: AVCaptureDevice?
    private var frontDevice: AVCaptureDevice?
    private var hasAudio = false

    // dataQueue
    private var isRecording = false
    private var target: RecordingTarget?
    private var writer: SegmentWriter?
    private var compositor: FrameCompositor?
    private var latestFrontBuffer: CVPixelBuffer?
    private var retryAfter: CMTime?
    private var useHEVC: Bool?
    /// Siguiente índice libre por incidente (un bloque puede seguir cerrándose al reanudar).
    private var reservedNextIndex: [UUID: Int] = [:]
    private let timestampCache = TimestampCache()

    private let overlayLock = NSLock()
    private var overlayConfiguration = OverlayConfiguration()

    /// Debe crearse en el hilo principal (crea vistas).
    override init() {
        supportsDualCamera = AVCaptureMultiCamSession.isMultiCamSupported
        session = supportsDualCamera ? AVCaptureMultiCamSession() : AVCaptureSession()
        backPreview = CameraPreviewView()
        frontPreview = CameraPreviewView()
        super.init()
        backPreview.previewLayer.setSessionWithNoConnection(session)
        frontPreview.previewLayer.setSessionWithNoConnection(session)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(sessionWasInterrupted(_:)), name: AVCaptureSession.wasInterruptedNotification, object: session)
        center.addObserver(self, selector: #selector(sessionInterruptionEnded(_:)), name: AVCaptureSession.interruptionEndedNotification, object: session)
        center.addObserver(self, selector: #selector(sessionRuntimeError(_:)), name: AVCaptureSession.runtimeErrorNotification, object: session)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Sesión

    func startSession() {
        sessionQueue.async {
            if !self.isConfigured {
                do {
                    try self.configureSession()
                    self.isConfigured = true
                } catch {
                    self.notify(.failed(error.localizedDescription))
                    return
                }
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            self.notify(self.session.isRunning ? .running : .failed("No se pudo iniciar la cámara."))
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.notify(.idle)
        }
    }

    private func notify(_ state: SessionState) {
        let hasFront = frontDevice != nil
        DispatchQueue.main.async {
            self.onStateChange?(state, hasFront)
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        var committed = false
        defer {
            if !committed { session.commitConfiguration() }
        }

        let isMultiCam = session is AVCaptureMultiCamSession
        if !isMultiCam, session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }

        guard let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video) else {
            throw CaptureError.noCamera
        }
        let backInput = try AVCaptureDeviceInput(device: back)
        guard session.canAddInput(backInput) else {
            throw CaptureError.configuration("No se pudo usar la cámara trasera.")
        }
        session.addInputWithNoConnections(backInput)
        if isMultiCam {
            selectMultiCamFormat(for: back, width: 1920, height: 1080)
        }
        try connectVideo(input: backInput, device: back, output: backVideoOutput, previewLayer: backPreview.previewLayer, mirrorPreview: false)
        backDevice = back

        if isMultiCam, let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            do {
                let frontInput = try AVCaptureDeviceInput(device: front)
                if session.canAddInput(frontInput) {
                    session.addInputWithNoConnections(frontInput)
                    selectMultiCamFormat(for: front, width: 1280, height: 720)
                    try connectVideo(input: frontInput, device: front, output: frontVideoOutput, previewLayer: frontPreview.previewLayer, mirrorPreview: true)
                    frontDevice = front
                }
            } catch {
                frontDevice = nil
            }
        }

        connectAudio()

        session.commitConfiguration()
        committed = true

        if let multiCam = session as? AVCaptureMultiCamSession {
            reduceHardwareCostIfNeeded(multiCam)
        }
    }

    private func connectVideo(
        input: AVCaptureDeviceInput,
        device: AVCaptureDevice,
        output: AVCaptureVideoDataOutput,
        previewLayer: AVCaptureVideoPreviewLayer,
        mirrorPreview: Bool
    ) throws {
        guard let port = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: device.position).first
            ?? input.ports.first(where: { $0.mediaType == .video }) else {
            throw CaptureError.configuration("La cámara no ofrece video.")
        }
        guard session.canAddOutput(output) else {
            throw CaptureError.configuration("No se pudo preparar la grabación de video.")
        }
        session.addOutputWithNoConnections(output)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: dataQueue)

        let connection = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(connection) else {
            throw CaptureError.configuration("No se pudo conectar la cámara.")
        }
        session.addConnection(connection)
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        // En el video la cámara frontal NO va en espejo (se ve como la ve otra persona).
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }

        let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
        if session.canAddConnection(previewConnection) {
            session.addConnection(previewConnection)
            if previewConnection.isVideoRotationAngleSupported(90) {
                previewConnection.videoRotationAngle = 90
            }
            if previewConnection.isVideoMirroringSupported {
                previewConnection.automaticallyAdjustsVideoMirroring = false
                previewConnection.isVideoMirrored = mirrorPreview
            }
        }
    }

    private func connectAudio() {
        guard let microphone = AVCaptureDevice.default(for: .audio),
              let micInput = try? AVCaptureDeviceInput(device: microphone),
              session.canAddInput(micInput) else {
            hasAudio = false
            return
        }
        session.addInputWithNoConnections(micInput)
        let positional = micInput.ports(for: .audio, sourceDeviceType: microphone.deviceType, sourceDevicePosition: .back)
        guard let port = positional.first ?? micInput.ports.first(where: { $0.mediaType == .audio }),
              session.canAddOutput(audioOutput) else {
            hasAudio = false
            return
        }
        session.addOutputWithNoConnections(audioOutput)
        audioOutput.setSampleBufferDelegate(self, queue: dataQueue)
        let connection = AVCaptureConnection(inputPorts: [port], output: audioOutput)
        if session.canAddConnection(connection) {
            session.addConnection(connection)
            hasAudio = true
        }
    }

    // MARK: - Formatos (multicámara)

    private static func supports30fps(_ format: AVCaptureDevice.Format) -> Bool {
        format.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }
    }

    private static func area(_ format: AVCaptureDevice.Format) -> Int {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return Int(dimensions.width) * Int(dimensions.height)
    }

    private func selectMultiCamFormat(for device: AVCaptureDevice, width: Int, height: Int) {
        let candidates = device.formats.filter { $0.isMultiCamSupported && Self.supports30fps($0) }
        guard !candidates.isEmpty else { return }
        let targetArea = width * height
        func score(_ format: AVCaptureDevice.Format) -> Int {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            var value = abs(Int(dimensions.width) * Int(dimensions.height) - targetArea)
            if Int(dimensions.width) * 9 != Int(dimensions.height) * 16 {
                value += 50_000_000
            }
            if CMFormatDescriptionGetMediaSubType(format.formatDescription) != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
                value += 1_000_000
            }
            return value
        }
        guard let best = candidates.min(by: { score($0) < score($1) }) else { return }
        apply(format: best, to: device)
    }

    private func apply(format: AVCaptureDevice.Format, to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            let frameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            device.unlockForConfiguration()
        } catch {
            // Si no se puede bloquear el dispositivo se conserva su formato actual.
        }
    }

    /// Las sesiones multicámara tienen un límite de hardware: si se excede, se baja
    /// la resolución (primero la frontal).
    private func reduceHardwareCostIfNeeded(_ multiCam: AVCaptureMultiCamSession) {
        var attempts = 0
        while multiCam.hardwareCost > 1.0, attempts < 8 {
            attempts += 1
            multiCam.beginConfiguration()
            var changed = false
            for device in [frontDevice, backDevice].compactMap({ $0 }) {
                let currentArea = Self.area(device.activeFormat)
                let smaller = device.formats.filter {
                    $0.isMultiCamSupported && Self.supports30fps($0) && Self.area($0) < currentArea
                }
                if let next = smaller.max(by: { Self.area($0) < Self.area($1) }) {
                    apply(format: next, to: device)
                    changed = true
                    break
                }
            }
            multiCam.commitConfiguration()
            if !changed { break }
        }
    }

    // MARK: - Grabación

    func updateOverlay(_ configuration: OverlayConfiguration) {
        overlayLock.lock()
        overlayConfiguration = configuration
        overlayLock.unlock()
    }

    func startRecording(target: RecordingTarget) {
        dataQueue.async {
            self.finishCurrentSegment(endTime: nil, completion: nil)
            var target = target
            if let reserved = self.reservedNextIndex[target.incidentID] {
                target.nextIndex = max(target.nextIndex, reserved)
            }
            self.target = target
            self.retryAfter = nil
            self.isRecording = true
        }
    }

    func stopRecording(completion: (() -> Void)? = nil) {
        dataQueue.async {
            self.isRecording = false
            self.finishCurrentSegment(endTime: nil, completion: completion)
            self.target = nil
            self.latestFrontBuffer = nil
        }
    }

    /// Cierra el bloque en curso (p. ej. al pasar a segundo plano). Si se sigue
    /// grabando, el siguiente cuadro abre un bloque nuevo.
    func flushCurrentSegment(completion: (() -> Void)? = nil) {
        dataQueue.async {
            self.finishCurrentSegment(endTime: nil, completion: completion)
        }
    }

    private func finishCurrentSegment(endTime: CMTime?, completion: (() -> Void)?) {
        guard let current = writer else {
            if let completion { DispatchQueue.main.async(execute: completion) }
            return
        }
        writer = nil
        current.finish(endTime: endTime) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let segment):
                    self?.onSegmentFinished?(segment)
                case .failure(let error):
                    if case CaptureError.emptySegment = error {
                        break
                    }
                    self?.onRecordingError?(error.localizedDescription)
                }
                completion?()
            }
        }
    }

    private func startSegment(at time: CMTime) -> Bool {
        guard var target else { return false }
        if let retryAfter, CMTimeCompare(time, retryAfter) < 0 { return false }

        let fm = FileManager.default
        var index = target.nextIndex
        func fileURL(_ index: Int) -> URL {
            target.directory.appendingPathComponent(String(format: "bloque-%04d.mov", index))
        }
        // Nunca sobrescribir un bloque existente.
        while fm.fileExists(atPath: fileURL(index).path) {
            index += 1
        }
        let url = fileURL(index)
        do {
            try fm.createDirectory(at: target.directory, withIntermediateDirectories: true)
            if useHEVC == nil {
                useHEVC = backVideoOutput.availableVideoCodecTypesForAssetWriter(writingTo: .mov).contains(.hevc)
            }
            let audioSettings = hasAudio
                ? audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) as? [String: Any]
                : nil
            writer = try SegmentWriter(
                url: url,
                incidentID: target.incidentID,
                index: index,
                startTime: time,
                startDate: Date(),
                videoSize: Self.outputSize,
                useHEVC: useHEVC ?? false,
                audioSettings: audioSettings
            )
            target.nextIndex = index + 1
            self.target = target
            reservedNextIndex[target.incidentID] = index + 1
            retryAfter = nil
            return true
        } catch {
            writer = nil
            retryAfter = CMTimeAdd(time, CMTime(seconds: 2, preferredTimescale: 600))
            let message = "No se pudo crear el bloque \(index): \(error.localizedDescription)"
            DispatchQueue.main.async {
                self.onRecordingError?(message)
            }
            return false
        }
    }

    private func overlayLines() -> [String] {
        overlayLock.lock()
        let configuration = overlayConfiguration
        overlayLock.unlock()
        var lines: [String] = []
        if configuration.showTimestamp {
            lines.append(timestampCache.string(for: Date()))
        }
        if configuration.showCoordinates {
            lines.append(configuration.coordinateText ?? "Ubicación no disponible")
        }
        return lines
    }

    private func processVideo(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, target != nil,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if let current = writer,
           CMTimeGetSeconds(CMTimeSubtract(time, current.startTime)) >= AppConfig.segmentDuration {
            finishCurrentSegment(endTime: time, completion: nil)
        }
        if writer == nil, !startSegment(at: time) {
            return
        }
        guard let writer, let pool = writer.pixelBufferPool else { return }

        if compositor == nil {
            compositor = FrameCompositor(outputSize: Self.outputSize)
        }
        guard let composed = compositor?.render(
            back: pixelBuffer,
            front: latestFrontBuffer,
            overlayLines: overlayLines(),
            pool: pool
        ) else { return }
        writer.appendVideo(composed, at: time)
    }

    private func processAudio(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, let writer else { return }
        writer.appendAudio(sampleBuffer)
    }

    // MARK: - Interrupciones

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        flushCurrentSegment()
        notify(.interrupted)
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        notify(.running)
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        flushCurrentSegment()
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        if error?.code == .mediaServicesWereReset {
            sessionQueue.async {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                self.notify(self.session.isRunning ? .running : .failed("La cámara se reinició y no pudo volver a arrancar."))
            }
        } else {
            notify(.failed(error?.localizedDescription ?? "Error de la cámara."))
            sessionQueue.asyncAfter(deadline: .now() + 1) {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                if self.session.isRunning {
                    self.notify(.running)
                }
            }
        }
    }
}

extension CaptureEngine: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === backVideoOutput {
            processVideo(sampleBuffer)
        } else if output === frontVideoOutput {
            if isRecording {
                latestFrontBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            }
        } else if output === audioOutput {
            processAudio(sampleBuffer)
        }
    }
}
