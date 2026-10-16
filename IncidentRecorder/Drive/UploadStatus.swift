import Foundation
import Observation

/// Estado de la cola de subidas para la interfaz (hilo principal).
@Observable
final class UploadStatus {
    static let shared = UploadStatus()

    enum ChunkState: Equatable {
        case notQueued
        case waiting(String?)
        case uploading
        case uploaded
        case failed(String?)
    }

    private(set) var jobs: [UploadJob] = []
    private(set) var blockedReason: String?
    private(set) var rootFolderID: String?
    private(set) var incidentFolders: [UUID: String] = [:]
    private(set) var isNetworkReachable = true
    /// Se invoca tras cada actualización (hilo principal).
    @ObservationIgnored var onChange: (() -> Void)?

    var pendingCount: Int { jobs.filter { $0.isPending && $0.kind == .videoChunk }.count }
    var uploadedCount: Int { jobs.filter { $0.phase == .done && $0.kind == .videoChunk }.count }
    var hasPending: Bool { jobs.contains { $0.isPending } }

    func apply(_ snapshot: UploadSnapshot) {
        jobs = snapshot.jobs
        blockedReason = snapshot.blockedReason
        rootFolderID = snapshot.rootFolderID
        incidentFolders = snapshot.incidentFolders
        onChange?()
    }

    func setNetworkReachable(_ reachable: Bool) {
        isNetworkReachable = reachable
    }

    func state(forChunk id: UUID) -> ChunkState {
        guard let job = jobs.first(where: { $0.chunkID == id }) else { return .notQueued }
        switch job.phase {
        case .done: return .uploaded
        case .transferring: return .uploading
        case .abandoned: return .failed(job.lastError)
        case .waiting: return job.attempts > 0 ? .failed(job.lastError) : .waiting(job.lastError)
        }
    }

    /// (subidos, total) de los bloques de video de un incidente.
    func progress(for incident: Incident) -> (uploaded: Int, total: Int) {
        let chunkIDs = Set(incident.chunks.map(\.id))
        let uploaded = jobs.filter { $0.kind == .videoChunk && $0.phase == .done && chunkIDs.contains($0.chunkID ?? UUID()) }.count
        return (uploaded, incident.chunks.count)
    }

    func folderURL(for incidentID: UUID) -> URL? {
        guard let id = incidentFolders[incidentID] else { return nil }
        return URL(string: "https://drive.google.com/drive/folders/\(id)")
    }

    var rootFolderURL: URL? {
        guard let rootFolderID else { return nil }
        return URL(string: "https://drive.google.com/drive/folders/\(rootFolderID)")
    }
}
