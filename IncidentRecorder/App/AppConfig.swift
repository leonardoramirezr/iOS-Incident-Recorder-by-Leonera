import Foundation

/// Valores que el build inyecta en el Info.plist (ver project.yml y el workflow).
enum AppConfig {
    static let displayName = "Incident Recorder by Leonera"

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.leonardoramirezr.incidentrecorderbyleonera"
    }

    /// Client ID OAuth de Google (tipo iOS), del build setting `GOOGLE_IOS_CLIENT_ID`.
    static var googleClientID: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$("), value.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return value
    }

    /// `true` si el build incluye la capacidad Family Controls (Tiempo en pantalla).
    static var familyControlsEnabled: Bool {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "IRFamilyControlsEnabled") as? String) ?? ""
        return ["YES", "TRUE", "1"].contains(raw.uppercased())
    }

    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
    }

    static var buildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
    }

    /// Etiqueta del build publicada por el workflow (p. ej. `build-30-1bca82e` o `0.3.0`).
    static var buildTag: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "IRBuildTag") as? String) ?? ""
        return raw.isEmpty || raw.contains("$(") ? "local" : raw
    }

    static var backgroundUploadSessionID: String { bundleIdentifier + ".uploads.session" }
    static var uploadProcessingTaskID: String { bundleIdentifier + ".uploads" }

    /// Nombre de la carpeta raíz en Google Drive.
    static let driveRootFolderName = "Incident Recorder by Leonera"

    /// Duración de cada bloque de video.
    static let segmentDuration: TimeInterval = 60
}
