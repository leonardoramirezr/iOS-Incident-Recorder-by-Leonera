import SwiftUI

/// Incidencias grabadas en este iPhone y su estado de subida.
struct IncidentListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.incidents.incidents.isEmpty {
                    ContentUnavailableView(
                        "Sin incidencias",
                        systemImage: "film.stack",
                        description: Text("Las grabaciones aparecerán aquí, divididas en bloques de 1 minuto.")
                    )
                } else {
                    List {
                        ForEach(model.incidents.incidents) { incident in
                            NavigationLink(value: incident.id) {
                                IncidentRow(incident: incident, isActive: incident.id == model.activeIncidentID)
                            }
                            .deleteDisabled(incident.id == model.activeIncidentID)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { model.incidents.incidents[$0].id }
                            for id in ids {
                                model.deleteIncident(id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Incidencias")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                IncidentDetailView(incidentID: id)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }
}

private struct IncidentRow: View {
    let incident: Incident
    let isActive: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = model.uploads.progress(for: incident)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(incident.title)
                    .font(.headline)
                if isActive {
                    Text("EN CURSO")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                }
            }
            Text("\(OverlayFormat.duration(incident.totalDuration)) · \(incident.chunks.count) bloque(s) · \(incident.totalBytes.formattedBytes)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label(
                "\(progress.uploaded)/\(progress.total) en Google Drive",
                systemImage: progress.uploaded == progress.total ? "checkmark.icloud" : "icloud.and.arrow.up"
            )
            .font(.caption)
            .foregroundStyle(progress.uploaded == progress.total ? Color.green : Color.orange)
        }
        .padding(.vertical, 4)
    }
}

/// Detalle de una incidencia: reproducción completa, carpeta en Drive y estado por bloque.
struct IncidentDetailView: View {
    let incidentID: UUID
    @Environment(AppModel.self) private var model
    @State private var showPlayer = false

    var body: some View {
        if let incident = model.incidents.incident(incidentID) {
            List {
                Section {
                    LabeledContent("Inicio", value: incident.startedAt.formatted(date: .abbreviated, time: .standard))
                    if let endedAt = incident.endedAt {
                        LabeledContent("Fin", value: endedAt.formatted(date: .abbreviated, time: .standard))
                    }
                    LabeledContent("Duración", value: OverlayFormat.duration(incident.totalDuration))
                    LabeledContent("Tamaño", value: incident.totalBytes.formattedBytes)
                    Button {
                        showPlayer = true
                    } label: {
                        Label("Ver video completo", systemImage: "play.rectangle.fill")
                    }
                    .disabled(incident.chunks.isEmpty)
                    if let url = model.uploads.folderURL(for: incident.id) {
                        Link(destination: url) {
                            Label("Abrir carpeta en Google Drive", systemImage: "folder")
                        }
                    }
                }

                Section("Bloques de 1 minuto") {
                    ForEach(incident.chunks) { chunk in
                        ChunkRow(chunk: chunk, state: model.uploads.state(forChunk: chunk.id))
                    }
                }
            }
            .navigationTitle(incident.title)
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showPlayer) {
                IncidentPlayerView(incident: incident)
                    .environment(model)
            }
        } else {
            ContentUnavailableView("Incidencia eliminada", systemImage: "trash")
        }
    }
}

private struct ChunkRow: View {
    let chunk: IncidentChunk
    let state: UploadStatus.ChunkState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "Bloque %d", chunk.index))
                    .font(.subheadline.weight(.semibold))
                Text("\(chunk.startedAt.formatted(date: .omitted, time: .standard)) · \(OverlayFormat.duration(chunk.duration)) · \(chunk.byteCount.formattedBytes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
    }

    private var symbol: String {
        switch state {
        case .uploaded: return "checkmark.icloud.fill"
        case .uploading: return "icloud.and.arrow.up"
        case .waiting, .notQueued: return "clock"
        case .failed: return "exclamationmark.icloud"
        }
    }

    private var color: Color {
        switch state {
        case .uploaded: return .green
        case .uploading: return .blue
        case .waiting, .notQueued: return .secondary
        case .failed: return .orange
        }
    }

    private var detail: String? {
        switch state {
        case .failed(let message): return message
        case .waiting(let message): return message
        default: return nil
        }
    }
}
