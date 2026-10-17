import AVFoundation
import CoreGraphics

/// Bloque de video ya cerrado y guardado en el teléfono.
struct FinishedSegment {
    let incidentID: UUID
    let index: Int
    let url: URL
    let startedAt: Date
    let duration: TimeInterval
    let byteCount: Int64
}

enum CaptureError: LocalizedError {
    case noCamera
    case configuration(String)
    case writer(String)
    case emptySegment

    var errorDescription: String? {
        switch self {
        case .noCamera: return "No se encontró una cámara disponible."
        case .configuration(let message): return message
        case .writer(let message): return message
        case .emptySegment: return "El bloque no tenía cuadros de video."
        }
    }
}

/// Escribe un bloque (.mov) con AVAssetWriter. Todas las llamadas deben hacerse
/// desde la cola de datos del motor de captura.
final class SegmentWriter {
    let url: URL
    let incidentID: UUID
    let index: Int
    let startTime: CMTime
    let startDate: Date

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private var lastVideoTime: CMTime
    private var frameCount = 0

    init(
        url: URL,
        incidentID: UUID,
        index: Int,
        startTime: CMTime,
        startDate: Date,
        videoSize: CGSize,
        useHEVC: Bool,
        audioSettings: [String: Any]?
    ) throws {
        let assetWriter = try AVAssetWriter(outputURL: url, fileType: .mov)
        // Fragmentos cada 2 s: si la app se cierra de golpe, el archivo sigue siendo legible.
        assetWriter.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)

        let width = Int(videoSize.width)
        let height = Int(videoSize.height)
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: useHEVC ? 4_500_000 : 7_000_000,
            AVVideoExpectedSourceFrameRateKey: 30,
            AVVideoMaxKeyFrameIntervalKey: 60,
        ]
        if !useHEVC {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: useHEVC ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
        ]
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        video.expectsMediaDataInRealTime = true
        let pixelAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        let pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: video,
            sourcePixelBufferAttributes: pixelAttributes
        )
        guard assetWriter.canAdd(video) else {
            throw CaptureError.writer("No se pudo configurar el video del bloque.")
        }
        assetWriter.add(video)

        var audio: AVAssetWriterInput?
        if let audioSettings {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(input) {
                assetWriter.add(input)
                audio = input
            }
        }

        guard assetWriter.startWriting() else {
            throw assetWriter.error ?? CaptureError.writer("No se pudo empezar a escribir el bloque.")
        }
        assetWriter.startSession(atSourceTime: startTime)

        self.url = url
        self.incidentID = incidentID
        self.index = index
        self.startTime = startTime
        self.startDate = startDate
        self.writer = assetWriter
        self.videoInput = video
        self.adaptor = pixelAdaptor
        self.audioInput = audio
        self.lastVideoTime = startTime
    }

    var pixelBufferPool: CVPixelBufferPool? { adaptor.pixelBufferPool }

    var isWriting: Bool { writer.status == .writing }

    @discardableResult
    func appendVideo(_ pixelBuffer: CVPixelBuffer, at time: CMTime) -> Bool {
        guard writer.status == .writing, videoInput.isReadyForMoreMediaData else { return false }
        guard frameCount == 0 || CMTimeCompare(time, lastVideoTime) > 0 else { return false }
        guard adaptor.append(pixelBuffer, withPresentationTime: time) else { return false }
        lastVideoTime = time
        frameCount += 1
        return true
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let audioInput, writer.status == .writing, audioInput.isReadyForMoreMediaData else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard CMTimeCompare(time, startTime) >= 0 else { return }
        _ = audioInput.append(sampleBuffer)
    }

    /// Cierra el archivo. `endTime` es el inicio del siguiente bloque (o `nil` para usar el último cuadro).
    func finish(endTime: CMTime?, completion: @escaping (Result<FinishedSegment, Error>) -> Void) {
        guard writer.status == .writing else {
            completion(.failure(writer.error ?? CaptureError.writer("El bloque \(index) no se pudo escribir.")))
            return
        }
        guard frameCount > 0 else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            completion(.failure(CaptureError.emptySegment))
            return
        }

        let frameDuration = CMTime(value: 1, timescale: 30)
        var end = endTime ?? CMTimeAdd(lastVideoTime, frameDuration)
        if CMTimeCompare(end, lastVideoTime) <= 0 {
            end = CMTimeAdd(lastVideoTime, frameDuration)
        }

        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        writer.endSession(atSourceTime: end)

        let writer = self.writer
        let url = self.url
        let incidentID = self.incidentID
        let index = self.index
        let startDate = self.startDate
        let duration = CMTimeGetSeconds(CMTimeSubtract(end, startTime))
        writer.finishWriting {
            if writer.status == .completed {
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
                completion(.success(FinishedSegment(
                    incidentID: incidentID,
                    index: index,
                    url: url,
                    startedAt: startDate,
                    duration: duration,
                    byteCount: size
                )))
            } else {
                completion(.failure(writer.error ?? CaptureError.writer("No se pudo cerrar el bloque \(index).")))
            }
        }
    }
}
