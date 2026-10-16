import Foundation
import UIKit

/// Cola persistente de subidas a Google Drive.
///
/// Flujo de cada archivo:
/// 1. Asegura la carpeta raíz y la carpeta del incidente en Drive.
/// 2. Crea una sesión de subida reanudable (petición pequeña, con token).
/// 3. Envía el contenido con un PUT a la URL de sesión (no necesita token):
///    - con la app en primer plano, mediante la sesión en segundo plano de
///      URLSession, que sigue aunque la app se suspenda o el teléfono se bloquee;
///    - con la app ya en segundo plano (viva gracias a la ubicación), con una
///      sesión normal, porque iOS difiere las tareas en segundo plano creadas ahí.
/// 4. Si algo falla a medias, pregunta a Drive cuántos bytes recibió y continúa.
/// Sin internet los trabajos esperan; al volver la red (NWPathMonitor), al
/// despertar la app o al volver a primer plano, la cola se reanuda sola.
actor UploadCoordinator {
    static let shared = UploadCoordinator()

    private static let maxConcurrentRuns = 3

    private var state: UploadQueueState
    private var running: Set<UUID> = []
    private var isProcessing = false
    private var needsAnotherPass = false
    private var blockedReason: String?
    private var folderTasks: [String: Task<String, Error>] = [:]
    private var retryTask: Task<Void, Never>?
    private let drive = DriveAPI()

    private static var stateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("upload-queue.json")
    }

    static var partsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UploadParts", isDirectory: true)
    }

    init() {
        if let data = try? Data(contentsOf: Self.stateURL),
           let decoded = try? JSONDecoder().decode(UploadQueueState.self, from: data) {
            state = decoded
        } else {
            state = UploadQueueState()
        }
    }

    // MARK: - API pública

    func enqueueChunk(incident: Incident, chunk: IncidentChunk) {
        guard !state.jobs.contains(where: { $0.chunkID == chunk.id }) else { return }
        let url = IncidentStore.chunkURL(chunk, incidentID: incident.id)
        state.jobs.append(UploadJob(
            kind: .videoChunk,
            incidentID: incident.id,
            chunkID: chunk.id,
            chunkIndex: chunk.index,
            folderName: incident.driveFolderName,
            relativePath: IncidentStore.relativePath(of: url),
            remoteName: chunk.remoteName,
            mimeType: "video/quicktime"
        ))
        persist()
        publish()
        scheduleProcessing()
    }

    /// Programa (o reprograma) la subida de la bitácora de ubicaciones del incidente.
    func enqueueLocationLog(incident: Incident) {
        if let index = state.jobs.firstIndex(where: { $0.kind == .locationLog && $0.incidentID == incident.id }) {
            var job = state.jobs[index]
            if job.phase == .transferring || running.contains(job.id) {
                job.contentChanged = true
            } else if job.phase != .abandoned {
                job.phase = .waiting
                job.sessionURL = nil
                job.sessionSize = nil
                job.needsStatusQuery = false
                job.attempts = 0
                job.notBefore = nil
            }
            state.jobs[index] = job
        } else {
            let url = IncidentStore.locationLogURL(for: incident.id)
            state.jobs.append(UploadJob(
                kind: .locationLog,
                incidentID: incident.id,
                chunkID: nil,
                chunkIndex: nil,
                folderName: incident.driveFolderName,
                relativePath: IncidentStore.relativePath(of: url),
                remoteName: IncidentStore.locationLogFileName,
                mimeType: "text/csv"
            ))
        }
        persist()
        publish()
        scheduleProcessing()
    }

    /// Olvida los trabajos de un incidente borrado.
    func removeJobs(for incidentID: UUID) async {
        let taskIDs = state.jobs.filter { $0.incidentID == incidentID }.compactMap(\.backgroundTaskID)
        state.jobs.removeAll { $0.incidentID == incidentID }
        state.incidentFolders[incidentID] = nil
        persist()
        publish()
        await BackgroundTransfer.shared.cancel(taskIDs: Set(taskIDs))
    }

    /// Reintenta de inmediato todo lo pendiente (botón "Reintentar").
    func retryNow() {
        for index in state.jobs.indices where state.jobs[index].phase == .waiting {
            state.jobs[index].notBefore = nil
        }
        persist()
        scheduleProcessing()
    }

    func hasPendingWork() -> Bool {
        state.jobs.contains { $0.isPending }
    }

    func publishCurrentState() {
        publish()
    }

    nonisolated func kick() {
        Task { await self.process() }
    }

    /// Procesa la cola hasta que no quede nada que hacer en este momento.
    func process() async {
        if isProcessing {
            needsAnotherPass = true
            return
        }
        isProcessing = true
        repeat {
            needsAnotherPass = false
            await processPass()
        } while needsAnotherPass
        isProcessing = false
        publish()
    }

    /// Espera (hasta `timeout`) a que no haya pasos en curso; útil en tareas de fondo.
    func waitUntilIdle(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        await process()
        while (!running.isEmpty || isProcessing) && Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    /// Al arrancar: las tareas en segundo plano que iOS ya no conoce se reanudan
    /// consultando a Drive cuántos bytes recibió.
    func reconcileBackgroundTasks() async {
        let active = await BackgroundTransfer.shared.activeTaskIDs()
        var changed = false
        for index in state.jobs.indices where state.jobs[index].phase == .transferring {
            if let taskID = state.jobs[index].backgroundTaskID, active.contains(taskID) { continue }
            state.jobs[index].phase = .waiting
            state.jobs[index].backgroundTaskID = nil
            state.jobs[index].needsStatusQuery = true
            changed = true
        }
        if changed { persist() }
        publish()
        scheduleProcessing()
    }

    /// Resultado de una tarea de la sesión en segundo plano.
    func handleBackgroundCompletion(jobID: UUID, taskID: Int, statusCode: Int?, body: Data, error: Error?) {
        guard let job = findJob(jobID), job.backgroundTaskID == taskID else { return }
        mutate(jobID) { job in
            job.backgroundTaskID = nil
            job.phase = .waiting
        }
        if let error {
            handleFailure(jobID: jobID, error: error)
        } else {
            handleTransferResponse(jobID: jobID, statusCode: statusCode ?? 0, body: body)
        }
        scheduleProcessing()
    }

    // MARK: - Procesamiento

    private func scheduleProcessing() {
        Task { await self.process() }
    }

    private func processPass() async {
        guard AppConfig.googleClientID != nil else {
            blockedReason = "Google Drive no está configurado en este build."
            return
        }
        guard await GoogleTokenStore.shared.isSignedIn else {
            let needsReauth = await GoogleTokenStore.shared.needsReauthorization
            blockedReason = needsReauth
                ? "Google pidió volver a iniciar sesión: conecta Google Drive de nuevo."
                : "Conecta Google Drive para subir los videos."
            return
        }
        guard NetworkMonitor.shared.isReachable else {
            blockedReason = "Sin internet: se subirá en cuanto haya conexión."
            return
        }
        blockedReason = nil

        let now = Date()
        let ready = state.jobs
            .filter { $0.phase == .waiting && !running.contains($0.id) && ($0.notBefore ?? .distantPast) <= now }
            .sorted { lhs, rhs in
                // Los videos primero; la bitácora después.
                if lhs.kind != rhs.kind { return lhs.kind == .videoChunk }
                return lhs.createdAt < rhs.createdAt
            }
        let inForeground = await AppLifecycle.isActive()
        for job in ready {
            guard running.count < Self.maxConcurrentRuns else { break }
            running.insert(job.id)
            Task { await self.run(jobID: job.id, useBackgroundSession: inForeground) }
        }
        scheduleRetryTimer()
    }

    private func run(jobID: UUID, useBackgroundSession: Bool) async {
        defer {
            running.remove(jobID)
            scheduleProcessing()
        }
        do {
            guard let initial = findJob(jobID), initial.phase == .waiting else { return }
            let parentID = try await ensureIncidentFolder(incidentID: initial.incidentID, name: initial.folderName)

            // 1) Archivo a subir (puede reiniciar la sesión si la bitácora cambió).
            guard let candidate = findJob(jobID), candidate.phase == .waiting else { return }
            let source = try prepareSource(for: candidate)
            guard let current = findJob(jobID) else { return }

            // 2) ¿Se interrumpió una transferencia anterior?
            var offset: Int64 = 0
            if let sessionURL = current.sessionURL, current.needsStatusQuery {
                switch try await drive.uploadStatus(sessionURL: sessionURL, totalSize: source.size) {
                case .complete(let fileID):
                    complete(jobID: jobID, remoteFileID: fileID)
                    return
                case .incomplete(let nextOffset):
                    offset = min(nextOffset, source.size)
                case .expired:
                    mutate(jobID) { job in
                        job.sessionURL = nil
                        job.sessionSize = nil
                    }
                }
            }

            // 3) Sesión reanudable.
            guard let beforeSession = findJob(jobID) else { return }
            if beforeSession.sessionURL == nil {
                let sessionURL: URL
                if beforeSession.kind == .locationLog, let fileID = beforeSession.remoteFileID {
                    sessionURL = try await drive.startResumableUpdate(fileID: fileID, mimeType: beforeSession.mimeType, size: source.size)
                } else {
                    sessionURL = try await drive.startResumableUpload(
                        name: beforeSession.remoteName,
                        parentID: parentID,
                        mimeType: beforeSession.mimeType,
                        size: source.size
                    )
                }
                mutate(jobID) { job in
                    job.sessionURL = sessionURL
                    job.sessionSize = source.size
                }
                offset = 0
            }

            // 4) Contenido.
            guard let ready = findJob(jobID), let sessionURL = ready.sessionURL else { return }
            let request = DriveAPI.contentRequest(sessionURL: sessionURL, offset: offset, totalSize: source.size, mimeType: ready.mimeType)
            let body = try Self.bodyFile(for: source.url, offset: offset, jobID: jobID)
            mutate(jobID) { job in
                job.needsStatusQuery = true
                job.lastError = nil
            }

            if useBackgroundSession {
                let taskID = BackgroundTransfer.shared.startUpload(request: request, fileURL: body, jobID: jobID)
                mutate(jobID) { job in
                    job.phase = .transferring
                    job.backgroundTaskID = taskID
                }
            } else {
                let (data, response) = try await URLSession.shared.upload(for: request, fromFile: body)
                handleTransferResponse(jobID: jobID, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
            }
        } catch {
            handleFailure(jobID: jobID, error: error)
        }
    }

    private struct Source {
        let url: URL
        let size: Int64
    }

    /// Videos: el archivo tal cual. Bitácora: una copia fija mientras dure la sesión.
    private func prepareSource(for job: UploadJob) throws -> Source {
        let fm = FileManager.default
        switch job.kind {
        case .videoChunk:
            let url = IncidentStore.rootDirectory.appendingPathComponent(job.relativePath)
            guard let size = Self.fileSize(url) else { throw DriveError.missingLocalFile }
            return Source(url: url, size: size)
        case .locationLog:
            let snapshot = Self.partsDirectory.appendingPathComponent("\(job.id.uuidString)-snapshot.csv")
            if job.sessionURL != nil, let size = Self.fileSize(snapshot), size == job.sessionSize {
                return Source(url: snapshot, size: size)
            }
            guard fm.fileExists(atPath: IncidentStore.locationLogURL(for: job.incidentID).path) else {
                throw DriveError.missingLocalFile
            }
            let size = try IncidentStore.makeLocationLogSnapshot(for: job.incidentID, to: snapshot)
            mutate(job.id) { job in
                job.sessionURL = nil
                job.sessionSize = nil
                job.needsStatusQuery = false
            }
            return Source(url: snapshot, size: size)
        }
    }

    private func handleTransferResponse(jobID: UUID, statusCode: Int, body: Data) {
        switch statusCode {
        case 200, 201:
            complete(jobID: jobID, remoteFileID: DriveAPI.decodeID(body))
        case 308:
            mutate(jobID) { job in
                job.phase = .waiting
                job.needsStatusQuery = true
                job.notBefore = Date().addingTimeInterval(2)
            }
        case 404, 410:
            mutate(jobID) { job in
                job.sessionURL = nil
                job.sessionSize = nil
                job.needsStatusQuery = false
            }
            backoff(jobID: jobID, message: "La sesión de subida expiró; se volverá a empezar.")
        case 400..<500 where statusCode != 408 && statusCode != 429:
            // Según la guía de Drive, ante otros 4xx hay que empezar una sesión nueva.
            mutate(jobID) { job in
                job.sessionURL = nil
                job.sessionSize = nil
                job.needsStatusQuery = false
            }
            backoff(jobID: jobID, message: DriveError.fromDrive(status: statusCode, data: body).localizedDescription)
        default:
            backoff(jobID: jobID, message: DriveError.fromDrive(status: statusCode, data: body).localizedDescription)
        }
    }

    private func handleFailure(jobID: UUID, error: Error) {
        switch error {
        case DriveError.notSignedIn, DriveError.reauthorizationRequired, DriveError.notConfigured:
            mutate(jobID) { job in
                job.phase = .waiting
                job.backgroundTaskID = nil
                job.lastError = error.localizedDescription
            }
        case DriveError.missingLocalFile:
            mutate(jobID) { job in
                job.phase = .abandoned
                job.backgroundTaskID = nil
                job.lastError = error.localizedDescription
            }
        case DriveError.http(let status, let reason, _) where status == 404 && reason == "notFound":
            // La carpeta de destino ya no existe (la borraron en Drive): recrearla.
            if let job = findJob(jobID) {
                state.incidentFolders[job.incidentID] = nil
            }
            state.rootFolderID = nil
            mutate(jobID) { job in
                job.sessionURL = nil
                job.sessionSize = nil
                job.needsStatusQuery = false
            }
            backoff(jobID: jobID, message: error.localizedDescription)
        default:
            if let urlError = error as? URLError, Self.isConnectivityError(urlError) {
                mutate(jobID) { job in
                    job.phase = .waiting
                    job.backgroundTaskID = nil
                    job.needsStatusQuery = job.sessionURL != nil
                    job.lastError = "Sin conexión."
                    job.notBefore = Date().addingTimeInterval(5)
                }
            } else {
                backoff(jobID: jobID, message: error.localizedDescription)
            }
        }
    }

    private func complete(jobID: UUID, remoteFileID: String?) {
        Self.removePart(for: jobID)
        mutate(jobID) { job in
            job.backgroundTaskID = nil
            if let remoteFileID { job.remoteFileID = remoteFileID }
            job.sessionURL = nil
            job.sessionSize = nil
            job.needsStatusQuery = false
            job.attempts = 0
            job.notBefore = nil
            job.lastError = nil
            job.uploadedAt = Date()
            if job.kind == .locationLog && job.contentChanged {
                job.contentChanged = false
                job.phase = .waiting
            } else {
                job.phase = .done
            }
        }
    }

    private func backoff(jobID: UUID, message: String) {
        mutate(jobID) { job in
            job.phase = .waiting
            job.backgroundTaskID = nil
            job.attempts += 1
            let delay = min(600, 5 * pow(2, Double(min(job.attempts, 7))))
            job.notBefore = Date().addingTimeInterval(delay)
            job.lastError = message
        }
    }

    /// Despierta la cola cuando vence el reintento más próximo (mientras la app viva).
    private func scheduleRetryTimer() {
        retryTask?.cancel()
        let now = Date()
        let next = state.jobs
            .filter { $0.phase == .waiting && !running.contains($0.id) }
            .compactMap(\.notBefore)
            .filter { $0 > now }
            .min()
        guard let next else { return }
        let delay = max(1, next.timeIntervalSince(now))
        retryTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.process()
        }
    }

    // MARK: - Carpetas en Drive

    private func ensureRootFolder() async throws -> String {
        if let id = state.rootFolderID { return id }
        return try await singleFlight(key: "root") {
            let drive = DriveAPI()
            if let existing = try await drive.findFolder(named: AppConfig.driveRootFolderName, parentID: nil) {
                return existing
            }
            return try await drive.createFolder(named: AppConfig.driveRootFolderName, parentID: nil)
        } store: { id in
            self.state.rootFolderID = id
        }
    }

    private func ensureIncidentFolder(incidentID: UUID, name: String) async throws -> String {
        if let id = state.incidentFolders[incidentID] { return id }
        let rootID = try await ensureRootFolder()
        return try await singleFlight(key: incidentID.uuidString) {
            let drive = DriveAPI()
            if let existing = try await drive.findFolder(named: name, parentID: rootID) {
                return existing
            }
            return try await drive.createFolder(named: name, parentID: rootID)
        } store: { id in
            self.state.incidentFolders[incidentID] = id
        }
    }

    /// Evita crear la misma carpeta dos veces cuando varios trabajos la necesitan a la vez.
    private func singleFlight(
        key: String,
        operation: @escaping @Sendable () async throws -> String,
        store: (String) -> Void
    ) async throws -> String {
        if let existing = folderTasks[key] {
            return try await existing.value
        }
        let task = Task { try await operation() }
        folderTasks[key] = task
        do {
            let id = try await task.value
            folderTasks[key] = nil
            store(id)
            persist()
            publish()
            return id
        } catch {
            folderTasks[key] = nil
            throw error
        }
    }

    // MARK: - Estado

    private func findJob(_ id: UUID) -> UploadJob? {
        state.jobs.first { $0.id == id }
    }

    private func mutate(_ id: UUID, _ change: (inout UploadJob) -> Void) {
        guard let index = state.jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&state.jobs[index])
        persist()
        publish()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        let url = Self.stateURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func publish() {
        let snapshot = UploadSnapshot(
            jobs: state.jobs,
            blockedReason: blockedReason,
            rootFolderID: state.rootFolderID,
            incidentFolders: state.incidentFolders
        )
        Task { @MainActor in
            UploadStatus.shared.apply(snapshot)
        }
    }

    // MARK: - Archivos

    private static func fileSize(_ url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.size] as? NSNumber)?.int64Value
    }

    /// Para continuar desde `offset` se envía una copia con los bytes restantes.
    private static func bodyFile(for source: URL, offset: Int64, jobID: UUID) throws -> URL {
        guard offset > 0 else { return source }
        let fm = FileManager.default
        try fm.createDirectory(at: partsDirectory, withIntermediateDirectories: true)
        let part = partsDirectory.appendingPathComponent("\(jobID.uuidString).part")
        if fm.fileExists(atPath: part.path) {
            try fm.removeItem(at: part)
        }
        _ = fm.createFile(atPath: part.path, contents: nil)
        let reader = try FileHandle(forReadingFrom: source)
        let writer = try FileHandle(forWritingTo: part)
        defer {
            try? reader.close()
            try? writer.close()
        }
        try reader.seek(toOffset: UInt64(offset))
        while let chunk = try reader.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            try writer.write(contentsOf: chunk)
        }
        return part
    }

    private static func removePart(for jobID: UUID) {
        let fm = FileManager.default
        try? fm.removeItem(at: partsDirectory.appendingPathComponent("\(jobID.uuidString).part"))
        try? fm.removeItem(at: partsDirectory.appendingPathComponent("\(jobID.uuidString)-snapshot.csv"))
    }

    private static func isConnectivityError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
             .callIsActive, .secureConnectionFailed, .backgroundSessionWasDisconnected:
            return true
        default:
            return false
        }
    }
}

/// Estado de la app consultado desde código asíncrono.
enum AppLifecycle {
    static func isActive() async -> Bool {
        await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
    }
}
