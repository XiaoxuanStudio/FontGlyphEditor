import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: AppSession
    @State private var mode: Mode = .login
    @State private var qq = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var cardKey = ""

    enum Mode: String, CaseIterable, Identifiable {
        case login = "登录"
        case register = "注册"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer(minLength: 30)
                VStack(spacing: 8) {
                    Text("XFonts")
                        .font(.largeTitle.bold())
                    Text("本软件免费无售后，可随时关停，收费售卖均为骗局")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker("模式", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
                    TextField("QQ / 账号", text: $qq)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)
                    SecureField("密码", text: $password)
                        .textFieldStyle(.roundedBorder)
                    if mode == .register {
                        SecureField("再次输入密码", text: $confirm)
                            .textFieldStyle(.roundedBorder)
                        TextField("卡密", text: $cardKey)
                            .textInputAutocapitalization(.characters)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Button {
                    Task {
                        switch mode {
                        case .login:
                            await session.login(qq: qq, password: password)
                        case .register:
                            await session.register(qq: qq, password: password, confirm: confirm, cardKey: cardKey)
                        }
                    }
                } label: {
                    HStack {
                        if session.isLoading { ProgressView().tint(.white) }
                        Text(mode.rawValue).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.isLoading || qq.isEmpty || password.isEmpty || (mode == .register && (confirm.isEmpty || cardKey.isEmpty)))

                Text("©2026 小轩 XFonts")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(24)
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("提示", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }
}
