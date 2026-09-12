import SwiftUI

struct KairosSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("saveFocusToCalendar") private var saveFocusToCalendar = true
    @AppStorage("weatherUnit") private var weatherUnit = "automatic"
    @AppStorage("agentServerURL") private var agentServerURL = "http://127.0.0.1:8000"
    @AppStorage("agentMode") private var agentMode = "local"
    @State private var showingPersonalAI = false

    var body: some View {
        NavigationStack {
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
                Section("Weather") {
                    Picker("Temperature", selection: $weatherUnit) {
                        Text("Auto").tag("automatic")
                        Text("°C").tag("celsius")
                        Text("°F").tag("fahrenheit")
                    }.pickerStyle(.segmented)
                    Text("Auto follows the measurement system configured on your iPhone.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Apple Calendar") {
                    Toggle("Save completed focus sessions", isOn: $saveFocusToCalendar)
                    Text("When enabled, completing a focus session creates an event in a dedicated Kairos calendar using the actual start and finish time.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Notifications") { Text("Kairos schedules on-device alerts at each task’s Latest Safe Start. Notification permission is managed in the iPhone Settings app.").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showingPersonalAI) { PersonalAIConnectionView() }
        }
    }
}
