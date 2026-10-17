import Foundation

/// Un bloque de video (≈1 minuto) guardado en el teléfono.
struct IncidentChunk: Codable, Identifiable, Hashable {
    var id: UUID
    var index: Int
    var fileName: String
    /// Nombre con el que se sube a Google Drive.
    var remoteName: String
    var startedAt: Date
    var duration: TimeInterval
    var byteCount: Int64
}

/// Una incidencia: todos los bloques grabados desde que se pulsa grabar hasta que se finaliza.
struct Incident: Codable, Identifiable, Hashable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    /// Carpeta de Google Drive donde se suben sus bloques.
    var driveFolderName: String
    var chunks: [IncidentChunk]

    var totalDuration: TimeInterval { chunks.reduce(0) { $0 + $1.duration } }
    var totalBytes: Int64 { chunks.reduce(0) { $0 + $1.byteCount } }
    var nextChunkIndex: Int { (chunks.map(\.index).max() ?? 0) + 1 }
    var isFinished: Bool { endedAt != nil }

    var title: String {
        startedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Lectura de ubicación que se guarda en la bitácora `ubicaciones.csv` del incidente.
struct LocationSample: Equatable {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var altitude: Double
    var verticalAccuracy: Double
    var speed: Double
    var course: Double

    var overlayText: String {
        OverlayFormat.coordinates(latitude: latitude, longitude: longitude)
    }

    static let csvHeader = "timestamp,latitude,longitude,horizontal_accuracy_m,altitude_m,vertical_accuracy_m,speed_mps,course_deg"

    var csvLine: String {
        func number(_ value: Double, _ digits: Int) -> String {
            String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        return [
            OverlayFormat.timestamp(timestamp),
            number(latitude, 6),
            number(longitude, 6),
            number(horizontalAccuracy, 1),
            number(altitude, 1),
            number(verticalAccuracy, 1),
            number(speed, 2),
            number(course, 1),
        ].joined(separator: ",")
    }
}
