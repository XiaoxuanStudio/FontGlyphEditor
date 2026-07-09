import Foundation

struct UploadFilePart {
    let fieldName: String
    let fileName: String
    let mimeType: String
    let data: Data
}

final class FontEngineClient {
    var baseURL: URL
    var authToken: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // Font export can take a while on real devices, especially when writing
        // sbix color glyph bitmaps. The default timeout is often too short.
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 7200
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    init(baseURL: URL = URL(string: "https://font-line1.example.com")!, authToken: String? = nil) {
        self.baseURL = baseURL
        self.authToken = authToken
    }

    func health() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        if let authToken { request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization") }
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func inferImages(files: [URL]) async throws -> [InferredImageItem] {
        let parts = try files.map { url in
            UploadFilePart(fieldName: "files", fileName: url.lastPathComponent, mimeType: mimeType(for: url), data: try Data(contentsOf: url))
        }
        let (data, response) = try await multipartPOST(path: "infer-images", textFields: [:], files: parts)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw EngineClientError.server(String(data: data, encoding: .utf8) ?? "infer failed")
        }
        return try JSONDecoder().decode(InferImagesResponse.self, from: data).items
    }

    func exportFont(fontURL: URL, request: EngineExportRequest, attachmentURLs: [URL], preferredName: String) async throws -> URL {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        let requestData = try encoder.encode(request)
        let requestJSON = String(data: requestData, encoding: .utf8) ?? "{}"

        var parts: [UploadFilePart] = []
        parts.append(UploadFilePart(fieldName: "font", fileName: fontURL.lastPathComponent, mimeType: mimeType(for: fontURL), data: try Data(contentsOf: fontURL)))
        let uniqueURLs = Array(Set(attachmentURLs)).sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in uniqueURLs {
            parts.append(UploadFilePart(fieldName: "images", fileName: url.lastPathComponent, mimeType: mimeType(for: url), data: try Data(contentsOf: url)))
        }

        let (data, response) = try await multipartPOST(path: "export", textFields: ["request_json": requestJSON], files: parts)
        guard let http = response as? HTTPURLResponse else { throw EngineClientError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            throw EngineClientError.server(String(data: data, encoding: .utf8) ?? "export failed")
        }

        let trimmed = preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "修符字体" : trimmed
        let filename = baseName.lowercased().hasSuffix(".ttf") ? baseName : "\(baseName).ttf"
        let savedURL = try FileStore.shared.saveDataExact(data, filename: filename, folder: "exports")
        return savedURL
    }

    private func multipartPOST(path: String, textFields: [String: String], files: [UploadFilePart]) async throws -> (Data, URLResponse) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 3600
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let authToken { request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization") }
        request.httpBody = makeMultipartBody(boundary: boundary, textFields: textFields, files: files)
        return try await session.data(for: request)
    }

    private func makeMultipartBody(boundary: String, textFields: [String: String], files: [UploadFilePart]) -> Data {
        var body = Data()
        let lineBreak = "\r\n"
        for (key, value) in textFields {
            body.appendString("--\(boundary)\(lineBreak)")
            body.appendString("Content-Disposition: form-data; name=\"\(key)\"\(lineBreak + lineBreak)")
            body.appendString("\(value)\(lineBreak)")
        }
        for file in files {
            body.appendString("--\(boundary)\(lineBreak)")
            body.appendString("Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.fileName)\"\(lineBreak)")
            body.appendString("Content-Type: \(file.mimeType)\(lineBreak + lineBreak)")
            body.append(file.data)
            body.appendString(lineBreak)
        }
        body.appendString("--\(boundary)--\(lineBreak)")
        return body
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "ttc": return "font/collection"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }

    private func suggestedFilename(from response: HTTPURLResponse) -> String? {
        guard let disposition = response.value(forHTTPHeaderField: "Content-Disposition") else { return nil }
        let pieces = disposition.components(separatedBy: "filename=")
        guard pieces.count > 1 else { return nil }
        return pieces[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }
}

enum EngineClientError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "字体引擎返回无效响应"
        case .server(let message): return message
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
