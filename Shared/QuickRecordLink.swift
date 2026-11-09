import Foundation

/// Enlace con el que el widget «IR» de la pantalla de bloqueo abre la app. La app
/// muestra la animación del gesto de desbloqueo y la grabación empieza al pulsar
/// «Entendido».
///
/// Se compila en la app y en la extensión del widget. El esquema debe coincidir con
/// `CFBundleURLTypes` de `Config/IncidentRecorder-Info.plist`.
enum QuickRecordLink {
    static let scheme = "irleonera"
    static let host = "grabar"

    static let url = URL(string: "\(scheme)://\(host)")!

    static func matches(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == host
    }
}
