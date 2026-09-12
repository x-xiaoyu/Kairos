import SwiftUI

struct PersonalAIConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("openAIModel") private var model = "gpt-5-mini"
    @State private var apiKey = ""
    @State private var saved = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "brain.head.profile.fill").font(.title).foregroundStyle(Color.kairosIndigo)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("连接 OpenAI API").font(.headline)
                            Text("使用你自己的 API 余额").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if saved { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                }

                Section("第一步") {
                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                        Label("登录 OpenAI Platform 并创建 API Key", systemImage: "safari")
                    }
                    Text("ChatGPT Plus/Pro 订阅与 OpenAI API 余额相互独立。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("第二步") {
                    SecureField("粘贴 API Key", text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("模型", text: $model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(saved ? "更新连接" : "保存并连接") { save() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                }

                Section("安全") {
                    Text("API Key 使用 iOS Keychain 保存，仅限本机解锁后读取，不写入 SwiftData、日志或 iCloud。个人密钥直连适合自用；公开发布版本应改为短期授权或用户自己的安全代理。")
                        .font(.caption).foregroundStyle(.secondary)
                    if saved { Button("断开并删除凭证", role: .destructive) { disconnect() } }
                }
            }
            .navigationTitle("我的 AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .onAppear {
                saved = KeychainStore.read(account: "openai-api-key") != nil
            }
        }
    }

    private func save() {
        do {
            try KeychainStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: "openai-api-key")
            apiKey = ""
            saved = true
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = "无法保存凭证，请稍后再试。"
        }
    }

    private func disconnect() {
        KeychainStore.delete(account: "openai-api-key")
        apiKey = ""
        saved = false
    }
}
