import Foundation

/// Llamadas a la API REST de Google Drive v3 (solo URLSession, sin SDK).
struct DriveAPI {
    static let folderMimeType = "application/vnd.google-apps.folder"

    enum ResumableStatus {
        case complete(fileID: String?)
        case incomplete(nextOffset: Int64)
        case expired
    }

    var tokens: GoogleTokenStore = .shared
    var session: URLSession = .shared

    // MARK: - Carpetas

    func findFolder(named name: String, parentID: String?) async throws -> String? {
        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        var query = "mimeType = '\(Self.folderMimeType)' and name = '\(escaped)' and trashed = false"
        query += " and '\(parentID ?? "root")' in parents"
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "pageSize", value: "10"),
        ]
        let (data, _) = try await send(URLRequest(url: components.url!))
        struct ListResponse: Decodable {
            struct File: Decodable { let id: String }
            let files: [File]
        }
        return try JSONDecoder().decode(ListResponse.self, from: data).files.first?.id
    }

    func createFolder(named name: String, parentID: String?) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        var metadata: [String: Any] = ["name": name, "mimeType": Self.folderMimeType]
        if let parentID {
            metadata["parents"] = [parentID]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        let (data, _) = try await send(request)
        guard let id = Self.decodeID(data) else { throw DriveError.invalidResponse }
        return id
    }

    func folderExists(_ id: String) async -> Bool {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(id)?fields=id,trashed")!
        guard let result = try? await send(URLRequest(url: url)) else { return false }
        struct File: Decodable { let trashed: Bool? }
        return (try? JSONDecoder().decode(File.self, from: result.0).trashed) != true
    }

    // MARK: - Subidas reanudables

    /// Crea una sesión de subida reanudable para un archivo nuevo. Devuelve la URL de sesión
    /// (válida una semana; no requiere el token para subir el contenido).
    func startResumableUpload(name: String, parentID: String, mimeType: String, size: Int64) async throws -> URL {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id")!)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "parents": [parentID],
            "mimeType": mimeType,
        ])
        return try await sessionURL(from: request)
    }

    /// Sesión reanudable para reemplazar el contenido de un archivo existente.
    func startResumableUpdate(fileID: String, mimeType: String, size: Int64) async throws -> URL {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=resumable&fields=id")!)
        request.httpMethod = "PATCH"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = Data("{}".utf8)
        return try await sessionURL(from: request)
    }

    /// Pregunta a Drive cuántos bytes recibió de una subida interrumpida.
    func uploadStatus(sessionURL: URL, totalSize: Int64) async throws -> ResumableStatus {
        var request = URLRequest(url: sessionURL)
        request.httpMethod = "PUT"
        request.setValue("bytes */\(totalSize)", forHTTPHeaderField: "Content-Range")
        let (data, response) = try await session.upload(for: request, from: Data())
        guard let http = response as? HTTPURLResponse else { throw DriveError.invalidResponse }
        switch http.statusCode {
        case 200, 201:
            return .complete(fileID: Self.decodeID(data))
        case 308:
            return .incomplete(nextOffset: Self.nextOffset(fromRangeHeader: http.value(forHTTPHeaderField: "Range")))
        case 404, 410:
            return .expired
        default:
            throw DriveError.fromDrive(status: http.statusCode, data: data)
        }
    }

    /// Petición PUT para enviar el contenido desde `offset` hasta el final.
    static func contentRequest(sessionURL: URL, offset: Int64, totalSize: Int64, mimeType: String) -> URLRequest {
        var request = URLRequest(url: sessionURL)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        if totalSize > 0 {
            request.setValue("bytes \(offset)-\(totalSize - 1)/\(totalSize)", forHTTPHeaderField: "Content-Range")
        }
        request.timeoutInterval = 120
        return request
    }

    // MARK: - Auxiliares

    static func decodeID(_ data: Data) -> String? {
        struct File: Decodable { let id: String }
        return try? JSONDecoder().decode(File.self, from: data).id
    }

    /// `Range: bytes=0-42` → 43.
    static func nextOffset(fromRangeHeader header: String?) -> Int64 {
        guard let header, let last = header.split(separator: "-").last, let end = Int64(last) else { return 0 }
        return end + 1
    }

    private func sessionURL(from request: URLRequest) async throws -> URL {
        let (_, response) = try await send(request)
        guard let location = response.value(forHTTPHeaderField: "Location"), let url = URL(string: location) else {
            throw DriveError.invalidResponse
        }
        return url
    }

    /// Envía una petición autenticada. Si el token expiró lo renueva y reintenta una vez.
    private func send(_ request: URLRequest, allowRetry: Bool = true) async throws -> (Data, HTTPURLResponse) {
        var authorized = request
        let token = try await tokens.accessToken(forceRefresh: !allowRetry)
        authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: authorized)
        guard let http = response as? HTTPURLResponse else { throw DriveError.invalidResponse }
        if http.statusCode == 401, allowRetry {
            return try await send(request, allowRetry: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DriveError.fromDrive(status: http.statusCode, data: data)
        }
        return (data, http)
    }
}
