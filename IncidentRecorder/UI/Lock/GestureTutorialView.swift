import SwiftUI

/// Animación que explica el gesto de desbloqueo: tocar las 4 esquinas empezando
/// abajo a la izquierda y en sentido horario. Se muestra cada vez que empieza
/// una grabación.
struct GestureTutorialView: View {
    var autoDismiss = true
    var onDismiss: () -> Void

    @State private var startDate = Date()

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 22) {
                Label("Grabando", systemImage: "record.circle")
                    .font(.headline)
                    .foregroundStyle(.red)

                Text("La pantalla se verá apagada. Para volver a la app toca las 4 esquinas en este orden:")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)

                TimelineView(.animation) { timeline in
                    PhoneGestureDiagram(time: timeline.date.timeIntervalSince(startDate))
                }
                .frame(width: 170, height: 320)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(UnlockSequence.order.enumerated()), id: \.offset) { index, corner in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .frame(width: 22, height: 22)
                                .background(.red, in: Circle())
                            Text(corner.title)
                                .font(.subheadline)
                        }
                    }
                }
                .foregroundStyle(.white)

                Button("Entendido", action: onDismiss)
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: 220)
            }
            .padding()
        }
        .task {
            guard autoDismiss else { return }
            try? await Task.sleep(nanoseconds: UInt64(PhoneGestureDiagram.cycle * 2 * 1_000_000_000))
            if !Task.isCancelled {
                onDismiss()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Para desbloquear toca las esquinas: abajo a la izquierda, arriba a la izquierda, arriba a la derecha y abajo a la derecha.")
    }
}

/// Teléfono esquemático con un dedo que recorre las esquinas.
struct PhoneGestureDiagram: View {
    let time: TimeInterval

    static let tapDuration: Double = 0.35
    static let moveDuration: Double = 0.6
    static let cycle: Double = 4.6

    private struct Frame {
        /// Posición a lo largo del recorrido, en unidades de esquina (0...3).
        var position: Double
        /// Esquinas ya tocadas.
        var reached: Int
        /// 0...1 mientras el dedo "toca" una esquina.
        var tap: Double?
    }

    private static func frame(at time: TimeInterval) -> Frame {
        let t = time.truncatingRemainder(dividingBy: cycle)
        if t < tapDuration {
            return Frame(position: 0, reached: 0, tap: t / tapDuration)
        }
        var cursor = tapDuration
        for segment in 0..<3 {
            if t < cursor + moveDuration {
                let progress = (t - cursor) / moveDuration
                let eased = progress * progress * (3 - 2 * progress)
                return Frame(position: Double(segment) + eased, reached: segment + 1, tap: nil)
            }
            cursor += moveDuration
            if t < cursor + tapDuration {
                return Frame(position: Double(segment + 1), reached: segment + 1, tap: (t - cursor) / tapDuration)
            }
            cursor += tapDuration
        }
        return Frame(position: 3, reached: 4, tap: nil)
    }

    private static func point(_ corner: Int, in size: CGSize) -> CGPoint {
        let inset: CGFloat = 26
        switch corner {
        case 0: return CGPoint(x: inset, y: size.height - inset)
        case 1: return CGPoint(x: inset, y: inset)
        case 2: return CGPoint(x: size.width - inset, y: inset)
        default: return CGPoint(x: size.width - inset, y: size.height - inset)
        }
    }

    private static func interpolate(_ position: Double, in size: CGSize) -> CGPoint {
        let lower = min(Int(position.rounded(.down)), 3)
        let upper = min(lower + 1, 3)
        let fraction = CGFloat(position - Double(lower))
        let a = point(lower, in: size)
        let b = point(upper, in: size)
        return CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let current = Self.frame(at: time)
            let finger = Self.interpolate(current.position, in: size)
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.white.opacity(0.75), lineWidth: 3)
                Capsule()
                    .fill(.white.opacity(0.4))
                    .frame(width: 50, height: 5)
                    .position(x: size.width / 2, y: 14)

                Path { path in
                    path.move(to: Self.point(0, in: size))
                    let completed = min(3, Int(current.position.rounded(.down)))
                    if completed >= 1 {
                        for corner in 1...completed {
                            path.addLine(to: Self.point(corner, in: size))
                        }
                    }
                    path.addLine(to: finger)
                }
                .stroke(.red.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))

                ForEach(0..<4, id: \.self) { corner in
                    Text("\(corner + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(corner < current.reached ? Color.red : Color.white.opacity(0.15), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                        .position(Self.point(corner, in: size))
                }

                if let tap = current.tap {
                    Circle()
                        .stroke(.white.opacity(1 - tap), lineWidth: 3)
                        .frame(width: 30 + 40 * tap, height: 30 + 40 * tap)
                        .position(finger)
                }

                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                    .scaleEffect(current.tap.map { 1 - 0.25 * sin($0 * .pi) } ?? 1)
                    .position(finger)
            }
        }
    }
}
