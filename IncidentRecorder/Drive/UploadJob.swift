import Foundation

/// Un archivo pendiente de subir a Google Drive.
struct UploadJob: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case videoChunk
        case locationLog
    }

    enum Phase: String, Codable {
        /// Esperando turno (o reintento).
        case waiting
        /// El contenido se está enviando con la sesión en segundo plano de iOS.
        case transferring
        /// Subido.
        case done
        /// No se puede subir (p. ej. el archivo local ya no existe).
        case abandoned
    }

    var id: UUID
    var kind: Kind
    var incidentID: UUID
    var chunkID: UUID?
    var chunkIndex: Int?
    var folderName: String
    /// Ruta relativa a `IncidentStore.rootDirectory`.
    var relativePath: String
    var remoteName: String
    var mimeType: String
    var createdAt: Date

    var phase: Phase = .waiting
    /// URL de la sesión reanudable de Drive.
    var sessionURL: URL?
    /// Tamaño del archivo con el que se creó la sesión.
    var sessionSize: Int64?
    /// La última transferencia pudo quedar a medias: preguntar a Drive desde dónde seguir.
    var needsStatusQuery = false
    var remoteFileID: String?
    var attempts = 0
    var notBefore: Date?
    var lastError: String?
    /// Identificador de la tarea de la sesión en segundo plano de URLSession.
    var backgroundTaskID: Int?
    /// (Bitácora) el archivo cambió mientras se subía: volver a subirlo al terminar.
    var contentChanged = false
    var uploadedAt: Date?

    init(
        kind: Kind,
        incidentID: UUID,
        chunkID: UUID?,
        chunkIndex: Int?,
        folderName: String,
        relativePath: String,
        remoteName: String,
        mimeType: String
    ) {
        id = UUID()
        self.kind = kind
        self.incidentID = incidentID
        self.chunkID = chunkID
        self.chunkIndex = chunkIndex
        self.folderName = folderName
        self.relativePath = relativePath
        self.remoteName = remoteName
        self.mimeType = mimeType
        createdAt = Date()
    }

    var isPending: Bool { phase == .waiting || phase == .transferring }
}

/// Estado persistido de la cola de subidas.
struct UploadQueueState: Codable {
    var rootFolderID: String?
    /// incidentID → id de su carpeta en Drive.
    var incidentFolders: [UUID: String] = [:]
    var jobs: [UploadJob] = []
}

/// Resumen para la interfaz.
struct UploadSnapshot {
    var jobs: [UploadJob]
    var blockedReason: String?
    var rootFolderID: String?
    var incidentFolders: [UUID: String]
}
