import AVKit
import SwiftUI

/// Reproduce la reconstrucción del video completo (todos los bloques locales en orden).
struct IncidentPlayerView: View {
    let incident: Incident

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var exportedURL: URL?
    @State private var isExporting = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: .bottom)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "film.stack")
                            .font(.largeTitle)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)
                    .padding()
                } else {
                    ProgressView("Reconstruyendo el video…")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
            .navigationTitle(incident.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        player?.pause()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let exportedURL {
                        ShareLink(item: exportedURL) {
                            Label("Compartir", systemImage: "square.and.arrow.up")
                        }
                    } else if isExporting {
                        ProgressView()
                    } else {
                        Button {
                            Task { await export() }
                        } label: {
                            Label("Exportar", systemImage: "square.and.arrow.up")
                        }
                        .disabled(player == nil)
                    }
                }
            }
        }
        .task {
            await load()
        }
        .onDisappear {
            player?.pause()
        }
    }

    @MainActor
    private func load() async {
        let urls = model.incidents.localChunkURLs(for: incident.id)
        do {
            let composition = try await CompositionBuilder.composition(for: urls)
            let player = AVPlayer(playerItem: AVPlayerItem(asset: composition))
            self.player = player
            player.play()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func export() async {
        isExporting = true
        defer { isExporting = false }
        let urls = model.incidents.localChunkURLs(for: incident.id)
        do {
            exportedURL = try await CompositionBuilder.export(chunkURLs: urls, name: incident.driveFolderName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
