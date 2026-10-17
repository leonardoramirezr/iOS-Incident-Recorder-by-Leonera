import AVFoundation

/// Reconstruye el video completo de una incidencia uniendo, en orden, los bloques
/// guardados en el teléfono.
enum CompositionBuilder {
    enum BuildError: LocalizedError {
        case noChunks
        case exportFailed(String?)

        var errorDescription: String? {
            switch self {
            case .noChunks: return "Esta incidencia todavía no tiene bloques guardados en el iPhone."
            case .exportFailed(let message): return message ?? "No se pudo exportar el video."
            }
        }
    }

    static func composition(for chunkURLs: [URL]) async throws -> AVComposition {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw BuildError.noChunks
        }
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        var hasAudio = false

        for url in chunkURLs {
            let asset = AVURLAsset(url: url)
            do {
                guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { continue }
                let videoRange = try await sourceVideo.load(.timeRange)
                guard videoRange.duration.isValid, videoRange.duration.seconds > 0 else { continue }
                try videoTrack.insertTimeRange(videoRange, of: sourceVideo, at: cursor)
                if cursor == .zero {
                    videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
                }
                if let audioTrack, let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                    let audioRange = try await sourceAudio.load(.timeRange)
                    let range = CMTimeRangeGetIntersection(audioRange, otherRange: videoRange)
                    if range.duration.seconds > 0 {
                        try audioTrack.insertTimeRange(range, of: sourceAudio, at: CMTimeAdd(cursor, CMTimeSubtract(range.start, videoRange.start)))
                        hasAudio = true
                    }
                }
                cursor = CMTimeAdd(cursor, videoRange.duration)
            } catch {
                // Un bloque dañado (p. ej. la app se cerró mientras se escribía) no impide ver el resto.
                continue
            }
        }
        if !hasAudio, let audioTrack {
            composition.removeTrack(audioTrack)
        }
        guard cursor.seconds > 0 else { throw BuildError.noChunks }
        return composition
    }

    /// Exporta el video completo a un archivo temporal para compartirlo.
    static func export(chunkURLs: [URL], name: String) async throws -> URL {
        let composition = try await composition(for: chunkURLs)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).mov")
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw BuildError.exportFailed(nil)
        }
        if #available(iOS 18.0, *) {
            try await session.export(to: output, as: .mov)
        } else {
            session.outputURL = output
            session.outputFileType = .mov
            await session.export()
            guard session.status == .completed else {
                throw BuildError.exportFailed(session.error?.localizedDescription)
            }
        }
        return output
    }
}
