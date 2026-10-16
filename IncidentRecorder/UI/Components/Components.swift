import SwiftUI
import UIKit

/// Abre la página de la app en Ajustes de iOS.
func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}

/// Etiqueta de estado con icono (✓, aviso, etc.).
struct StatusLabel: View {
    enum Kind {
        case ok, warning, error, info

        var color: Color {
            switch self {
            case .ok: return .green
            case .warning: return .orange
            case .error: return .red
            case .info: return .secondary
            }
        }

        var symbol: String {
            switch self {
            case .ok: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    let kind: Kind
    let text: String

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.color)
        }
        .font(.subheadline)
    }
}

/// Botón principal con fondo lleno.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = .red

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
    }
}

/// Botón redondo translúcido de la pantalla de cámara.
struct CircleIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(width: 84)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Botón central: grabar (círculo rojo) o pausar (dos barras).
struct RecordButton: View {
    enum Mode { case record, pause }

    let mode: Mode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 5)
                    .frame(width: 84, height: 84)
                switch mode {
                case .record:
                    Circle()
                        .fill(.red)
                        .frame(width: 66, height: 66)
                case .pause:
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).frame(width: 12, height: 32)
                        RoundedRectangle(cornerRadius: 3).frame(width: 12, height: 32)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(.red, in: Circle())
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .record ? "Grabar" : "Pausar")
    }
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
