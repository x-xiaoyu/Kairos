import SwiftUI

struct KairosSettingsView: View {
    @AppStorage("saveFocusToCalendar") private var saveFocusToCalendar = true
    @AppStorage("weatherUnit") private var weatherUnit = "automatic"
    @AppStorage("agentServerURL") private var agentServerURL = "http://127.0.0.1:8000"
    @AppStorage("agentMode") private var agentMode = "local"
    @State private var showingPersonalAI = false

    var body: some View {
            Form {
                Section("Kairos Agent") {
                    Picker("运行模式", selection: $agentMode) {
                        Text("本地").tag("local")
                        Text("Kairos AI").tag("ai")
                        Text("我的 AI").tag("personal")
                    }.pickerStyle(.segmented)
                        .onChange(of: agentMode) { _, mode in if mode == "personal" { showingPersonalAI = true } }
                    if agentMode == "ai" {
                        TextField("服务地址", text: $agentServerURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                        Text("模拟器可使用 http://127.0.0.1:8000。AI 模式需要后端启用 Bedrock；连接失败时会明确提示并临时使用本地规则。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if agentMode == "personal" {
                        Button { showingPersonalAI = true } label: {
                            HStack { Label("连接 OpenAI API", systemImage: "person.crop.circle.badge.plus"); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                        }
                        Text("费用使用你自己的 OpenAI API 账户。密钥保存在本机 Keychain。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("本地模式不需要网络，但只能理解 App 已内置的常见任务操作。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("天气") {
                    Picker("温度单位", selection: $weatherUnit) {
                        Text("跟随系统").tag("automatic")
                        Text("°C").tag("celsius")
                        Text("°F").tag("fahrenheit")
                    }.pickerStyle(.segmented)
                    Text("跟随系统会使用 iPhone 的度量单位。").font(.caption).foregroundStyle(.secondary)
                }
                Section("Apple 日历") {
                    Toggle("保存完成的专注时段", isOn: $saveFocusToCalendar)
                    Text("开启后，点击“完成任务”会将实际开始和结束时间写入 iPhone 当前默认日历。首次使用时请允许 Kairos 完全访问日历。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("通知") { Text("Kairos 会在计划开始时间和最晚安全开始时间发送本地提醒。高认知负荷任务会在开始前 10 分钟多一条轻量预热。文案由本地规则立即生成，连接“我的 AI”后可在打开 App 时异步精炼。通知权限在 iPhone 设置中管理。").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .sheet(isPresented: $showingPersonalAI) { PersonalAIConnectionView() }
    }
}
