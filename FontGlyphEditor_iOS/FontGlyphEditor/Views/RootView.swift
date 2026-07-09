import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        Group {
            if session.isLoggedIn {
                MainShellView()
            } else if session.isLoading {
                ProgressView("正在加载账号...")
            } else {
                LoginView()
            }
        }
    }
}

struct MainShellView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("字体修符", systemImage: "textformat") }
            if session.user?.isSuperAdmin == true {
                AdminView()
                    .tabItem { Label("用户管理", systemImage: "person.2") }
            }
            AccountView()
                .tabItem { Label("账号", systemImage: "person.crop.circle") }
        }
    }
}

struct AccountView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        NavigationStack {
            List {
                if let user = session.user {
                    Section("账号") {
                        LabeledContent("QQ", value: user.qq)
                        LabeledContent("身份", value: user.displayRole)
                        LabeledContent("到期时间", value: user.expiresAt ?? "永久")
                    }
                }
                Section("线路") {
                    ForEach(session.lines) { line in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(line.name)
                                Text(line.url).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if session.selectedLineID == line.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { session.updateSelectedLine(line.id) }
                    }
                    Button("刷新线路") {
                        Task { try? await session.refreshLines() }
                    }
                }
                Section {
                    Button("退出登录", role: .destructive) { session.logout() }
                }
            }
            .navigationTitle("账号")
        }
    }
}
