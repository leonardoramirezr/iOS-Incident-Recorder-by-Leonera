import Foundation

/// Impacto aproximado en la batería de una opción de ubicación.
enum BatteryImpact: Int, Comparable {
    case low, medium, high

    static func < (lhs: BatteryImpact, rhs: BatteryImpact) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .low: return "Consumo bajo"
        case .medium: return "Consumo medio"
        case .high: return "Consumo alto"
        }
    }

    var symbol: String {
        switch self {
        case .low: return "battery.100"
        case .medium: return "battery.50"
        case .high: return "battery.25"
        }
    }
}

/// Precisión pedida a Core Location (kCLLocationAccuracyNearestTenMeters / kCLLocationAccuracyBest).
enum LocationAccuracyOption: String, CaseIterable, Identifiable {
    case nearestTenMeters
    case best

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nearestTenMeters: return "Precisa, a unos 10 metros"
        case .best: return "La máxima que permita el iPhone"
        }
    }

    var detail: String {
        switch self {
        case .nearestTenMeters:
            return "Usa GPS, Wi‑Fi y antenas celulares hasta lograr unos 10 m. Gasta menos batería."
        case .best:
            return "Mantiene el GPS trabajando para afinar al máximo (hasta pocos metros). Es la que más batería gasta."
        }
    }

    var batteryImpact: BatteryImpact {
        switch self {
        case .nearestTenMeters: return .medium
        case .best: return .high
        }
    }

    /// Precisión horizontal (m) con la que una lectura se considera suficientemente buena.
    var acceptableHorizontalAccuracy: Double {
        switch self {
        case .nearestTenMeters: return 15
        case .best: return 8
        }
    }
}

/// Frecuencia con la que se actualizan las coordenadas.
enum LocationUpdateInterval: Int, CaseIterable, Identifiable {
    case seconds1 = 1
    case seconds5 = 5
    case seconds10 = 10
    case seconds15 = 15
    case seconds30 = 30
    case minutes1 = 60
    case minutes2_5 = 150
    case minutes5 = 300
    case minutes10 = 600

    var id: Int { rawValue }

    var seconds: TimeInterval { TimeInterval(rawValue) }

    var title: String {
        switch self {
        case .seconds1: return "Cada 1 s"
        case .seconds5: return "Cada 5 s"
        case .seconds10: return "Cada 10 s"
        case .seconds15: return "Cada 15 s"
        case .seconds30: return "Cada 30 s"
        case .minutes1: return "Cada 1 min"
        case .minutes2_5: return "Cada 2.5 min"
        case .minutes5: return "Cada 5 min"
        case .minutes10: return "Cada 10 min"
        }
    }

    /// Con intervalos cortos el GPS no alcanza a apagarse entre lecturas.
    var keepsGPSOn: Bool { rawValue <= 10 }

    var batteryImpact: BatteryImpact {
        switch rawValue {
        case ...10: return .high
        case ...30: return .medium
        default: return .low
        }
    }

    var detail: String {
        switch batteryImpact {
        case .high: return "El GPS queda encendido todo el tiempo."
        case .medium: return "El GPS se apaga brevemente entre lecturas."
        case .low: return "El GPS descansa entre lecturas."
        }
    }
}
