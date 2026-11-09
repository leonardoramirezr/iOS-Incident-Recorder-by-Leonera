import SwiftUI
import WidgetKit

/// Widget circular de la pantalla de bloqueo con el texto «IR». Al tocarlo iOS abre la
/// app (esté en segundo plano o cerrada) con `QuickRecordLink.url`: la app muestra la
/// animación del gesto y empieza a grabar al pulsar «Entendido».
struct QuickRecordWidget: Widget {
    static let kind = "QuickRecordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: QuickRecordProvider()) { _ in
            QuickRecordWidgetView()
        }
        .configurationDisplayName("IR")
        .description("Abre la app, muestra el gesto para salir de la pantalla negra y graba al pulsar «Entendido».")
        .supportedFamilies([.accessoryCircular])
    }
}

struct QuickRecordEntry: TimelineEntry {
    let date: Date
}

/// El contenido nunca cambia: una sola entrada sin recargas.
struct QuickRecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickRecordEntry {
        QuickRecordEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickRecordEntry) -> Void) {
        completion(QuickRecordEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickRecordEntry>) -> Void) {
        completion(Timeline(entries: [QuickRecordEntry(date: Date())], policy: .never))
    }
}

struct QuickRecordWidgetView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Text("IR")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .widgetAccentable()
        }
        .widgetURL(QuickRecordLink.url)
        .containerBackground(for: .widget) {
            Color.clear
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("IR")
        .accessibilityHint("Abre la app para empezar a grabar")
    }
}
