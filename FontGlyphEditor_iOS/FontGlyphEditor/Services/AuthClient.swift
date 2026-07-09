import Foundation

final class AuthClient {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = AppConfig.masterBaseURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    func login(qq: String, password: String) async throws -> AuthResponse {
        // 登录接口现在要求 username 字段；这里把输入框内容作为“账号标识”发送。
        // 用户输入 QQ 或账号名都走同一个 username 字段，由后端按 username/qq 进行匹配。
        // 兼容旧后端：如果旧接口仍只接收 qq 字段，则自动回退再请求一次。
        let identifier = qq.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try await postAny(
                path: "auth/login",
                token: nil,
                body: ["username": identifier, "password": password],
                response: AuthResponse.self
            )
        } catch {
            let usernameError = error
            do {
                return try await postAny(
                    path: "auth/login",
                    token: nil,
                    body: ["qq": identifier, "password": password],
                    response: AuthResponse.self
                )
            } catch {
                if AuthClient.isRequestSchemaError(usernameError) { throw error }
                throw usernameError
            }
        }
    }

    func register(qq: String, password: String, passwordConfirm: String, cardKey: String) async throws -> AuthResponse {
        try await post(path: "auth/register", token: nil, body: ["qq": qq, "password": password, "password_confirm": passwordConfirm, "card_key": cardKey], response: AuthResponse.self)
    }

    func me(token: String) async throws -> AuthUser {
        try await get(path: "auth/me", token: token, response: AuthUser.self)
    }

    func lines(token: String) async throws -> [EngineLine] {
        try await get(path: "config/lines", token: token, response: [EngineLine].self)
    }

    func users(token: String) async throws -> [AuthUser] {
        try await get(path: "admin/users", token: token, response: [AuthUser].self)
    }

    func createUser(token: String, qq: String, password: String, role: String, expiresAt: String?) async throws -> AuthUser {
        var body: [String: Any] = ["qq": qq, "password": password, "role": role, "is_active": true]
        if let expiresAt { body["expires_at"] = expiresAt }
        return try await postAny(path: "admin/users", token: token, body: body, response: AuthUser.self)
    }

    func generateCards(token: String, count: Int, durationDays: Int, note: String) async throws -> [CardKeyItem] {
        try await postAny(path: "admin/cards/generate", token: token, body: ["count": count, "duration_days": durationDays, "note": note], response: [CardKeyItem].self)
    }

    private static func isRequestSchemaError(_ error: Error) -> Bool {
        guard case AuthError.server(let message) = error else { return false }
        return message.contains("Field required")
            || message.contains("extra_forbidden")
            || message.contains("\"type\":\"missing\"")
            || message.contains("\"loc\"")
    }

    private func get<T: Decodable>(path: String, token: String?, response: T.Type) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, urlResponse) = try await session.data(for: request)
        return try decode(data: data, response: urlResponse, as: T.self)
    }

    private func post<T: Decodable, Body: Encodable>(path: String, token: String?, body: Body, response: T.Type) async throws -> T {
        let data = try JSONEncoder().encode(body)
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = data
        let (reply, urlResponse) = try await session.data(for: request)
        return try decode(data: reply, response: urlResponse, as: T.self)
    }

    private func postAny<T: Decodable>(path: String, token: String?, body: [String: Any], response: T.Type) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = data
        let (reply, urlResponse) = try await session.data(for: request)
        return try decode(data: reply, response: urlResponse, as: T.self)
    }

    private func decode<T: Decodable>(data: Data, response: URLResponse, as type: T.Type) throws -> T {
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            throw AuthError.server(AuthClient.errorMessage(from: data))
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let dict = object as? [String: Any] {
            if let detail = dict["detail"] as? String { return detail }
            if let errors = dict["detail"] as? [[String: Any]] {
                let messages = errors.compactMap { $0["msg"] as? String }
                if !messages.isEmpty { return messages.joined(separator: "；") }
            }
            if let message = dict["message"] as? String { return message }
            if let error = dict["error"] as? String { return error }
        }
        return String(data: data, encoding: .utf8) ?? "请求失败"
    }
}

enum AuthError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "服务器返回无效响应"
        case .server(let message): return message
        }
    }
}
