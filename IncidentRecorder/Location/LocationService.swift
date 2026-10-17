import CoreLocation
import Foundation
import Observation

extension LocationAccuracyOption {
    var coreLocationValue: CLLocationAccuracy {
        switch self {
        case .nearestTenMeters: return kCLLocationAccuracyNearestTenMeters
        case .best: return kCLLocationAccuracyBest
        }
    }
}

extension LocationSample {
    init(_ location: CLLocation) {
        self.init(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.altitude,
            verticalAccuracy: location.verticalAccuracy,
            speed: location.speed,
            course: location.course
        )
    }
}

/// Ubicación para las coordenadas del video y la bitácora del incidente.
///
/// Para ahorrar batería con intervalos largos (≥ 15 s) el GPS solo se enciende
/// alrededor de cada lectura; entre lecturas se piden actualizaciones de baja
/// precisión (antenas celulares) que mantienen viva la app en segundo plano.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum Mode: Equatable {
        /// Sin ubicación.
        case off
        /// Pantalla de cámara visible (solo en primer plano).
        case preview
        /// Incidencia en curso: sigue en segundo plano.
        case incident
        /// Sin incidencia pero con bloques pendientes de subir: mantiene viva la app con mínimo consumo.
        case keepAlive
    }

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var accuracyAuthorization: CLAccuracyAuthorization
    private(set) var latest: LocationSample?
    private(set) var mode: Mode = .off

    /// Cada lectura publicada (hilo principal).
    @ObservationIgnored var onSample: ((LocationSample) -> Void)?

    private let manager = CLLocationManager()
    @ObservationIgnored private var accuracy: LocationAccuracyOption = .best
    @ObservationIgnored private var interval: LocationUpdateInterval = .minutes1
    @ObservationIgnored private var sampleTimer: Timer?
    @ObservationIgnored private var windowTimer: Timer?
    @ObservationIgnored private var isSamplingWindow = false
    @ObservationIgnored private var bestInWindow: CLLocation?
    @ObservationIgnored private var lastPublished: Date?
    @ObservationIgnored private var wantsAlwaysUpgrade = false
    @ObservationIgnored private var isUpdating = false

    override init() {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        super.init()
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    var hasAlwaysAuthorization: Bool { authorizationStatus == .authorizedAlways }

    var hasPreciseLocation: Bool { accuracyAuthorization == .fullAccuracy }

    /// Pide "Al usar la app" y, en cuanto se concede, "Siempre".
    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            wantsAlwaysUpgrade = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func configure(mode: Mode, accuracy: LocationAccuracyOption, interval: LocationUpdateInterval) {
        let changed = mode != self.mode || accuracy != self.accuracy || interval != self.interval
        self.mode = mode
        self.accuracy = accuracy
        self.interval = interval
        if changed {
            applyConfiguration()
        }
    }

    /// Fuerza una lectura inmediata (p. ej. al empezar a grabar).
    func requestFreshSample() {
        guard isAuthorized, mode == .preview || mode == .incident else { return }
        if interval.keepsGPSOn {
            lastPublished = nil
        } else {
            beginSamplingWindow()
        }
    }

    private func applyConfiguration() {
        sampleTimer?.invalidate()
        sampleTimer = nil
        windowTimer?.invalidate()
        windowTimer = nil
        isSamplingWindow = false
        bestInWindow = nil

        guard isAuthorized, mode != .off else {
            stopUpdates()
            return
        }

        let runsInBackground = mode == .incident || mode == .keepAlive
        manager.allowsBackgroundLocationUpdates = runsInBackground
        manager.showsBackgroundLocationIndicator = runsInBackground
        if runsInBackground && hasAlwaysAuthorization {
            // Si iOS cierra la app, un cambio significativo de ubicación la vuelve a abrir
            // en segundo plano para terminar de subir los bloques.
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
        }
        manager.distanceFilter = kCLDistanceFilterNone

        switch mode {
        case .off:
            break
        case .keepAlive:
            manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
            startUpdates()
        case .preview, .incident:
            if interval.keepsGPSOn {
                manager.desiredAccuracy = accuracy.coreLocationValue
                startUpdates()
            } else {
                startUpdates()
                beginSamplingWindow()
                let timer = Timer(timeInterval: interval.seconds, repeats: true) { [weak self] _ in
                    self?.beginSamplingWindow()
                }
                timer.tolerance = min(5, interval.seconds * 0.1)
                RunLoop.main.add(timer, forMode: .common)
                sampleTimer = timer
            }
        }
    }

    private func startUpdates() {
        guard !isUpdating else { return }
        manager.startUpdatingLocation()
        isUpdating = true
    }

    private func stopUpdates() {
        if isUpdating {
            manager.stopUpdatingLocation()
            isUpdating = false
        }
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
    }

    private func beginSamplingWindow() {
        isSamplingWindow = true
        bestInWindow = nil
        manager.desiredAccuracy = accuracy.coreLocationValue
        windowTimer?.invalidate()
        let timer = Timer(timeInterval: 20, repeats: false) { [weak self] _ in
            self?.endSamplingWindow()
        }
        RunLoop.main.add(timer, forMode: .common)
        windowTimer = timer
    }

    private func endSamplingWindow() {
        windowTimer?.invalidate()
        windowTimer = nil
        if let best = bestInWindow {
            publish(best)
        }
        bestInWindow = nil
        isSamplingWindow = false
        if (mode == .preview || mode == .incident) && !interval.keepsGPSOn {
            // El GPS descansa hasta la siguiente lectura, pero la app sigue recibiendo
            // actualizaciones de baja precisión y no se suspende.
            manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        }
    }

    private func handle(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0 else { return }
        switch mode {
        case .off, .keepAlive:
            return
        case .preview, .incident:
            // Ignora lecturas viejas que iOS devuelve de caché.
            if abs(location.timestamp.timeIntervalSinceNow) > 60 { return }
            if interval.keepsGPSOn {
                if let lastPublished, Date().timeIntervalSince(lastPublished) < interval.seconds - 0.2 {
                    return
                }
                publish(location)
            } else if isSamplingWindow {
                if bestInWindow == nil || location.horizontalAccuracy < (bestInWindow?.horizontalAccuracy ?? .greatestFiniteMagnitude) {
                    bestInWindow = location
                }
                if location.horizontalAccuracy <= accuracy.acceptableHorizontalAccuracy {
                    endSamplingWindow()
                }
            } else if latest == nil {
                publish(location)
            }
        }
    }

    private func publish(_ location: CLLocation) {
        lastPublished = Date()
        let sample = LocationSample(location)
        latest = sample
        onSample?(sample)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        if authorizationStatus == .authorizedWhenInUse && wantsAlwaysUpgrade {
            wantsAlwaysUpgrade = false
            manager.requestAlwaysAuthorization()
        }
        applyConfiguration()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            handle(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown es temporal; los demás errores se reflejan en el estado de autorización.
    }
}
