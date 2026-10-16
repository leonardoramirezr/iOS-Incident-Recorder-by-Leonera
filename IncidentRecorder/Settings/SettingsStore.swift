import Foundation
import Observation

/// Ajustes del usuario, guardados en `UserDefaults`.
@Observable
final class SettingsStore {
    private enum Keys {
        static let showTimestamp = "settings.showTimestamp"
        static let showCoordinates = "settings.showCoordinates"
        static let accuracy = "settings.locationAccuracy"
        static let interval = "settings.locationInterval"
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// Se invoca (en el hilo principal) cada vez que cambia algún ajuste.
    @ObservationIgnored var onChange: (() -> Void)?

    /// Imprime la fecha y hora (`2026-10-16T12:00:00-06:00`) arriba a la izquierda del video.
    var showTimestamp: Bool {
        didSet { defaults.set(showTimestamp, forKey: Keys.showTimestamp); onChange?() }
    }

    /// Imprime las coordenadas (`19.432608 N, -99.133209 W`) en el video.
    var showCoordinates: Bool {
        didSet { defaults.set(showCoordinates, forKey: Keys.showCoordinates); onChange?() }
    }

    var locationAccuracy: LocationAccuracyOption {
        didSet { defaults.set(locationAccuracy.rawValue, forKey: Keys.accuracy); onChange?() }
    }

    var locationInterval: LocationUpdateInterval {
        didSet { defaults.set(locationInterval.rawValue, forKey: Keys.interval); onChange?() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showTimestamp = defaults.object(forKey: Keys.showTimestamp) as? Bool ?? true
        showCoordinates = defaults.object(forKey: Keys.showCoordinates) as? Bool ?? true
        locationAccuracy = (defaults.string(forKey: Keys.accuracy)).flatMap(LocationAccuracyOption.init(rawValue:)) ?? .best
        let storedInterval = defaults.object(forKey: Keys.interval) as? Int
        locationInterval = storedInterval.flatMap(LocationUpdateInterval.init(rawValue:)) ?? .minutes1
    }
}
