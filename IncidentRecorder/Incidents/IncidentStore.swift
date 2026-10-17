import Foundation
import Observation

/// Guarda las incidencias en `Application Support/Incidents/<id>/`:
/// - `incident.json`: metadatos y lista de bloques.
/// - `bloque-0001.mov`, `bloque-0002.mov`, …: video en bloques de 1 minuto.
/// - `ubicaciones.csv`: bitácora de ubicaciones durante la incidencia.
@Observable
final class IncidentStore {
    private(set) var incidents: [Incident] = []

    @ObservationIgnored private let ioQueue = DispatchQueue(label: "incident.store.io")

    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Incidents", isDirectory: true)
    }

    static let locationLogFileName = "ubicaciones.csv"
    private static let metadataFileName = "incident.json"

    init() {
        Self.prepareRootDirectory()
        incidents = Self.loadAll()
    }

    // MARK: - Consultas

    func incident(_ id: UUID) -> Incident? {
        incidents.first { $0.id == id }
    }

    static func directory(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func chunkURL(_ chunk: IncidentChunk, incidentID: UUID) -> URL {
        directory(for: incidentID).appendingPathComponent(chunk.fileName)
    }

    static func locationLogURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent(locationLogFileName)
    }

    /// Ruta relativa a `rootDirectory` (así sobrevive a cambios del contenedor de la app).
    static func relativePath(of url: URL) -> String {
        let root = rootDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1))
        }
        return url.lastPathComponent
    }

    func localChunkURLs(for id: UUID) -> [URL] {
        guard let incident = incident(id) else { return [] }
        return incident.chunks
            .sorted { $0.index < $1.index }
            .map { Self.chunkURL($0, incidentID: id) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Cambios (hilo principal)

    func createIncident() -> Incident {
        let now = Date()
        let incident = Incident(
            id: UUID(),
            startedAt: now,
            endedAt: nil,
            driveFolderName: "Incidente " + OverlayFormat.fileSafeTimestamp(now),
            chunks: []
        )
        let directory = Self.directory(for: incident.id)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logURL = Self.locationLogURL(for: incident.id)
        ioQueue.sync {
            if !FileManager.default.fileExists(atPath: logURL.path) {
                try? Data((LocationSample.csvHeader + "\n").utf8).write(to: logURL)
            }
        }
        incidents.insert(incident, at: 0)
        persist(incident)
        return incident
    }

    @discardableResult
    func addChunk(_ chunk: IncidentChunk, to id: UUID) -> Incident? {
        guard let index = incidents.firstIndex(where: { $0.id == id }) else { return nil }
        if !incidents[index].chunks.contains(where: { $0.index == chunk.index }) {
            incidents[index].chunks.append(chunk)
            incidents[index].chunks.sort { $0.index < $1.index }
        }
        persist(incidents[index])
        return incidents[index]
    }

    func markEnded(_ id: UUID) {
        guard let index = incidents.firstIndex(where: { $0.id == id }) else { return }
        incidents[index].endedAt = Date()
        persist(incidents[index])
    }

    func delete(_ id: UUID) {
        incidents.removeAll { $0.id == id }
        let directory = Self.directory(for: id)
        ioQueue.async {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Añade una lectura a la bitácora de ubicaciones del incidente.
    func appendLocation(_ sample: LocationSample, to id: UUID) {
        let url = Self.locationLogURL(for: id)
        let line = Data((sample.csvLine + "\n").utf8)
        ioQueue.async {
            if !FileManager.default.fileExists(atPath: url.path) {
                try? Data((LocationSample.csvHeader + "\n").utf8).write(to: url)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }

    /// Copia fija de la bitácora para subirla sin que cambie a mitad de la subida.
    static func makeLocationLogSnapshot(for id: UUID, to destination: URL) throws -> Int64 {
        let source = locationLogURL(for: id)
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
        let attributes = try fm.attributesOfItem(atPath: destination.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - Persistencia

    private func persist(_ incident: Incident) {
        let url = Self.directory(for: incident.id).appendingPathComponent(Self.metadataFileName)
        ioQueue.async {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(incident) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func loadAll() -> [Incident] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let incidents: [Incident] = entries.compactMap { directory in
            let url = directory.appendingPathComponent(metadataFileName)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Incident.self, from: data)
        }
        return incidents.sorted { $0.startedAt > $1.startedAt }
    }

    private static func prepareRootDirectory() {
        var root = rootDirectory
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Los videos ya se respaldan en Google Drive: no duplicarlos en iCloud.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }
}
