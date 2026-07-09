import SwiftUI

struct AdminView: View {
    @EnvironmentObject private var session: AppSession
    @State private var users: [AuthUser] = []
    @State private var cards: [CardKeyItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var newQQ = ""
    @State private var newPassword = ""
    @State private var newExpireDays = "30"
    @State private var cardCount = "10"
    @State private var cardDays = "30"
    @State private var cardNote = ""

    private let client = AuthClient()

    var body: some View {
        NavigationStack {
            List {
                Section("添加用户") {
                    TextField("QQ / 账号", text: $newQQ)
                    SecureField("初始密码", text: $newPassword)
                    TextField("有效天数，例如 30", text: $newExpireDays)
                        .keyboardType(.numberPad)
                    Button("添加管理员用户") { Task { await createUser() } }
                        .disabled(newQQ.isEmpty || newPassword.count < 6)
                }

                Section("生成卡密") {
                    TextField("数量", text: $cardCount).keyboardType(.numberPad)
                    TextField("有效天数", text: $cardDays).keyboardType(.numberPad)
                    TextField("备注", text: $cardNote)
                    Button("生成卡密") { Task { await generateCards() } }
                }

                if !cards.isEmpty {
                    Section("本次生成卡密") {
                        ForEach(cards) { card in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.cardKey).font(.system(.body, design: .monospaced))
                                Text("\(card.durationDays) 天 · \(card.note)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("用户列表") {
                    Button("刷新用户") { Task { await loadUsers() } }
                    ForEach(users) { user in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(user.qq).font(.headline)
                                Spacer()
                                Text(user.displayRole).font(.caption).foregroundStyle(.secondary)
                            }
                            Text("到期：\(user.expiresAt ?? "永久")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("用户管理")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isLoading { ProgressView() }
                }
            }
            .task { await loadUsers() }
        }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadUsers() async {
        guard let token = session.token else { return }
        isLoading = true
        defer { isLoading = false }
        do { users = try await client.users(token: token) }
        catch { errorMessage = error.localizedDescription }
    }

    private func createUser() async {
        guard let token = session.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let days = Int(newExpireDays) ?? 30
            let expire = ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(days) * 86400))
            _ = try await client.createUser(token: token, qq: newQQ, password: newPassword, role: "admin", expiresAt: expire)
            newQQ = ""; newPassword = ""
            await loadUsers()
        } catch { errorMessage = error.localizedDescription }
    }

    private func generateCards() async {
        guard let token = session.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            cards = try await client.generateCards(token: token, count: Int(cardCount) ?? 1, durationDays: Int(cardDays) ?? 30, note: cardNote)
        } catch { errorMessage = error.localizedDescription }
    }
}
