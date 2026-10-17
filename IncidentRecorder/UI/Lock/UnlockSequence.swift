import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Esquinas de la pantalla usadas por el gesto de desbloqueo.
enum ScreenCorner: Int, CaseIterable {
    case bottomLeft, topLeft, topRight, bottomRight

    var label: String {
        switch self {
        case .bottomLeft: return "abajo a la izquierda"
        case .topLeft: return "arriba a la izquierda"
        case .topRight: return "arriba a la derecha"
        case .bottomRight: return "abajo a la derecha"
        }
    }

    var title: String {
        switch self {
        case .bottomLeft: return "Abajo a la izquierda"
        case .topLeft: return "Arriba a la izquierda"
        case .topRight: return "Arriba a la derecha"
        case .bottomRight: return "Abajo a la derecha"
        }
    }

    /// Devuelve la esquina tocada o `nil` si el toque cayó fuera de las zonas activas.
    /// - Parameters:
    ///   - point: punto del toque en coordenadas de la vista (origen arriba a la izquierda).
    ///   - size: tamaño de la vista que cubre toda la pantalla.
    static func corner(at point: CGPoint, in size: CGSize) -> ScreenCorner? {
        let zone = UnlockSequence.zoneSide(for: size)
        let isLeft = point.x <= zone
        let isRight = point.x >= size.width - zone
        let isTop = point.y <= zone
        let isBottom = point.y >= size.height - zone
        switch (isLeft, isRight, isTop, isBottom) {
        case (true, false, false, true): return .bottomLeft
        case (true, false, true, false): return .topLeft
        case (false, true, true, false): return .topRight
        case (false, true, false, true): return .bottomRight
        default: return nil
        }
    }
}

/// Reconoce la secuencia de desbloqueo: tocar las 4 esquinas empezando abajo a la
/// izquierda y en sentido horario (abajo-izq → arriba-izq → arriba-der → abajo-der).
struct UnlockSequence {
    static let order: [ScreenCorner] = [.bottomLeft, .topLeft, .topRight, .bottomRight]

    /// Tiempo máximo entre dos toques consecutivos antes de reiniciar la secuencia.
    var maxInterval: TimeInterval = 4

    private(set) var progress = 0
    private var lastTap: Date?

    /// Lado de la zona cuadrada activa de cada esquina.
    static func zoneSide(for size: CGSize) -> CGFloat {
        max(64, min(size.width, size.height) * 0.3)
    }

    mutating func reset() {
        progress = 0
        lastTap = nil
    }

    /// Registra un toque. Devuelve `true` cuando la secuencia se completa.
    mutating func register(_ corner: ScreenCorner?, at date: Date = Date()) -> Bool {
        if let lastTap, date.timeIntervalSince(lastTap) > maxInterval {
            progress = 0
        }
        lastTap = date

        guard let corner else {
            progress = 0
            return false
        }

        if corner == Self.order[progress] {
            progress += 1
        } else {
            // Un toque equivocado reinicia; si fue la primera esquina cuenta como nuevo inicio.
            progress = corner == Self.order[0] ? 1 : 0
        }

        if progress == Self.order.count {
            reset()
            return true
        }
        return false
    }
}
