import SwiftUI

struct SettingsView: View {
    @AppStorage("phoneDefaultLabel") private var phoneDefaultLabel = "手机"
    @AppStorage("emailDefaultLabel") private var emailDefaultLabel = "邮箱"
    @AppStorage("preservePhonePrefix") private var preservePhonePrefix = false
    @AppStorage("autoBackup") private var autoBackup = true

    var body: some View {
        NavigationStack {
            List {
                Section("标签设置") {
                    Picker("手机号默认标签", selection: $phoneDefaultLabel) {
                        Text("手机").tag("手机")
                        Text("Mobile").tag("Mobile")
                        Text("电话").tag("电话")
                    }

                    Picker("邮箱默认标签", selection: $emailDefaultLabel) {
                        Text("邮箱").tag("邮箱")
                        Text("Email").tag("Email")
                        Text("邮件").tag("邮件")
                    }
                }

                Section("整理规则") {
                    Toggle("保留国际区号 (+86)", isOn: $preservePhonePrefix)
                    Toggle("操作前自动备份", isOn: $autoBackup)
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("数据存储")
                        Spacer()
                        Text("仅本地")
                            .foregroundStyle(.green)
                    }

                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        HStack {
                            Text("隐私政策")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                        Text("本应用永不联网")
                            .font(.headline)
                        Text("所有数据仅存储在您的设备上\n不会上传到任何服务器")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }
            }
            .accessibilityIdentifier("tab.settings.root")
            .navigationTitle("设置")
        }
    }
}
