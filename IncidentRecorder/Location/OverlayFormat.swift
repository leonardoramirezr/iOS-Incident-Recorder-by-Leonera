import Foundation

/// Formatos de los textos que se imprimen sobre el video.
enum OverlayFormat {
    /// Ejemplo: `2026-10-16T12:00:00-06:00`.
    static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        return formatter.string(from: date)
    }

    /// Ejemplo: `19.432608 N, -99.133209 W` (seis decimales ≈ 11 cm, lo máximo
    /// que tiene sentido para el GPS del iPhone).
    static func coordinates(latitude: Double, longitude: Double) -> String {
        let lat = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), latitude)
        let lon = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), longitude)
        let ns = latitude < 0 ? "S" : "N"
        let ew = longitude < 0 ? "W" : "E"
        return "\(lat) \(ns), \(lon) \(ew)"
    }

    /// Nombre de archivo/carpeta seguro: `2026-10-16T12-00-00-0600`.
    static func fileSafeTimestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ssxx"
        return formatter.string(from: date)
    }

    /// Duración legible: `1:02:03` o `02:03`.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

/// Reutiliza un `DateFormatter` para generar el texto de la hora en cada cuadro.
/// No es thread-safe: úsalo siempre desde la misma cola.
final class TimestampCache {
    private let formatter: DateFormatter
    private var lastSecond: Int = .min
    private var lastValue = ""

    init(timeZone: TimeZone = .current) {
        formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
    }

    func string(for date: Date) -> String {
        let second = Int(date.timeIntervalSince1970.rounded(.down))
        if second != lastSecond {
            lastSecond = second
            formatter.timeZone = TimeZone.current
            lastValue = formatter.string(from: date)
        }
        return lastValue
    }
}
