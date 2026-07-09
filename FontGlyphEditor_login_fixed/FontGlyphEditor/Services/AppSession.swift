import Foundation
import SwiftUI

@MainActor
final class AppSession: ObservableObject {
    @Published var token: String?
    @Published var user: AuthUser?
    @Published var lines: [EngineLine] = []
    @Published var selectedLineID: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let client = AuthClient()

    init() {
        token = UserDefaults.standard.string(forKey: "auth_token")
        selectedLineID = UserDefaults.standard.string(forKey: "selected_line_id")
        Task { await bootstrap() }
    }

    var isLoggedIn: Bool { token != nil && user != nil }
    var selectedLine: EngineLine? { lines.first { $0.id == selectedLineID } ?? lines.first }
    var engineURLString: String { selectedLine?.url ?? "" }

    func bootstrap() async {
        guard let token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            user = try await client.me(token: token)
            try await refreshLines()
        } catch {
            logout()
        }
    }

    func login(qq: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let auth = try await client.login(qq: qq, password: password)
            apply(auth)
            try await refreshLines()
        } catch {
            errorMessage = "登录失败：\(error.localizedDescription)"
        }
    }

    func register(qq: String, password: String, confirm: String, cardKey: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let auth = try await client.register(qq: qq, password: password, passwordConfirm: confirm, cardKey: cardKey)
            apply(auth)
            try await refreshLines()
        } catch {
            errorMessage = "注册失败：\(error.localizedDescription)"
        }
    }

    func refreshLines() async throws {
        guard let token else { return }
        let loaded = try await client.lines(token: token)
        lines = loaded
        if selectedLineID == nil || !loaded.contains(where: { $0.id == selectedLineID }) {
            selectedLineID = loaded.first?.id
            UserDefaults.standard.set(selectedLineID, forKey: "selected_line_id")
        }
    }

    func updateSelectedLine(_ id: String) {
        selectedLineID = id
        UserDefaults.standard.set(id, forKey: "selected_line_id")
    }

    func logout() {
        token = nil
        user = nil
        lines = []
        selectedLineID = nil
        UserDefaults.standard.removeObject(forKey: "auth_token")
        UserDefaults.standard.removeObject(forKey: "selected_line_id")
    }

    private func apply(_ auth: AuthResponse) {
        token = auth.token
        user = auth.user
        UserDefaults.standard.set(auth.token, forKey: "auth_token")
    }
}
