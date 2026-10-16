import FamilyControls
import Foundation
import ManagedSettings
import Observation

/// Permiso de Tiempo en pantalla (Family Controls) y bloqueo de las demás apps
/// mientras se graba una incidencia.
///
/// Mientras está activo, iOS muestra una pantalla negra (ver la extensión
/// ShieldConfiguration) al abrir cualquier otra app. Las apps autorizadas con
/// Family Controls —esta misma— nunca se bloquean.
@Observable
final class ScreenTimeService {
    enum Status: Equatable {
        /// El build no incluye la capacidad Family Controls (ver README).
        case unavailableInBuild
        case notDetermined
        case denied
        case approved
    }

    private(set) var status: Status = .notDetermined
    private(set) var lastError: String?
    private(set) var isShieldActive = false

    /// Solo se crea si el build tiene la capacidad Family Controls.
    private let store: ManagedSettingsStore? = AppConfig.familyControlsEnabled
        ? ManagedSettingsStore(named: ManagedSettingsStore.Name("incident-recording"))
        : nil

    init() {
        refresh()
    }

    var isAvailableInBuild: Bool { AppConfig.familyControlsEnabled }

    func refresh() {
        guard AppConfig.familyControlsEnabled else {
            status = .unavailableInBuild
            return
        }
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: status = .approved
        case .denied: status = .denied
        case .notDetermined: status = .notDetermined
        @unknown default: status = .notDetermined
        }
    }

    @MainActor
    func requestAuthorization() async {
        guard AppConfig.familyControlsEnabled else {
            status = .unavailableInBuild
            return
        }
        lastError = nil
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            lastError = Self.describe(error)
        }
        refresh()
    }

    /// Bloquea todas las demás apps y sitios web con la pantalla negra.
    func applyShield() {
        guard status == .approved, let store else { return }
        store.shield.applicationCategories = .all()
        store.shield.webDomainCategories = .all()
        isShieldActive = true
    }

    /// Quita el bloqueo.
    func removeShield() {
        guard let store else { return }
        store.clearAllSettings()
        isShieldActive = false
    }

    private static func describe(_ error: Error) -> String {
        if let familyError = error as? FamilyControlsError {
            switch familyError {
            case .restricted:
                return "Tiempo en pantalla está restringido en este iPhone."
            case .unavailable:
                return "Tiempo en pantalla no está disponible ahora. Revisa que esté activado en Ajustes."
            case .invalidAccountType:
                return "Esta cuenta de Apple no permite usar Tiempo en pantalla con apps."
            case .authorizationConflict:
                return "Otra app de control parental ya tiene este permiso."
            case .authorizationCanceled:
                return "Cancelaste la solicitud."
            case .networkError:
                return "Se necesita internet para conceder el permiso."
            default:
                return familyError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
