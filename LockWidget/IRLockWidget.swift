import SwiftUI
import WidgetKit

/// Enlace que abre la app y muestra la animación del gesto antes de grabar.
/// Debe coincidir con el esquema y host que reconoce `AppModel.handleOpenURL`.
enum IRLink {
    static let url = URL(string: "incidentrecorder://ir")!
}

/// El widget es estático: solo abre la app, así que basta con una entrada.
struct IRLockWidgetEntry: TimelineEntry {
    let date: Date
}

struct IRLockWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> IRLockWidgetEntry {
        IRLockWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (IRLockWidgetEntry) -> Void) {
        completion(IRLockWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<IRLockWidgetEntry>) -> Void) {
        completion(Timeline(entries: [IRLockWidgetEntry(date: Date())], policy: .never))
    }
}

/// Botón circular "IR" de la pantalla de bloqueo. Al tocarlo se abre la app.
struct IRLockWidgetView: View {
    var body: some View {
        Link(destination: IRLink.url) {
            ZStack {
                AccessoryWidgetBackground()
                Text("IR")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .widgetAccentable()
            }
        }
        .accessibilityLabel("Iniciar grabación de incidencia")
    }
}

struct IRLockWidget: Widget {
    static let kind = "IRLockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: IRLockWidgetProvider()) { _ in
            IRLockWidgetView()
        }
        .configurationDisplayName("Grabar incidencia")
        .description("Abre la app, muestra el gesto de desbloqueo y empieza la grabación al pulsar Entendido.")
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct IRLockWidgetBundle: WidgetBundle {
    var body: some Widget {
        IRLockWidget()
    }
}
