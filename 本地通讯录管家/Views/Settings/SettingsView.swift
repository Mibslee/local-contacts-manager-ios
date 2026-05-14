import SwiftUI

struct SettingsView: View {
    @AppStorage("phoneDefaultLabel") private var phoneDefaultLabel = "手机"
    @AppStorage("emailDefaultLabel") private var emailDefaultLabel = "邮箱"
    @AppStorage("preservePhonePrefix") private var preservePhonePrefix = false
    @AppStorage("autoBackup") private var autoBackup = true

    @State private var newTagName = ""
    @State private var showOperationHistory = false

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (build \(build))"
    }

    // MARK: - 标签管理

    private var tagManagementSection: some View {
        settingsGroup(title: "联系人标签", icon: "tag.fill") {
            HStack {
                TextField("输入新标签", text: $newTagName)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                Button("添加") {
                    let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    TagManager.shared.addTag(trimmed)
                    newTagName = ""
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: "4F7DF5"))
                .clipShape(Capsule())
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if TagManager.shared.tags.isEmpty {
                HStack {
                    Text("暂无标签，输入名称后添加").font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            } else {
                ForEach(TagManager.shared.tags, id: \.self) { tag in
                    HStack {
                        Image(systemName: "tag.fill").font(.caption2).foregroundStyle(Color(hex: "4F7DF5"))
                        Text(tag).font(.subheadline)
                        Spacer()
                        Button(role: .destructive) {
                            TagManager.shared.removeTag(tag)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    if tag != TagManager.shared.tags.last { Divider() }
                }
            }
        }
    }

    // MARK: - 操作历史

    private var operationHistorySection: some View {
        settingsGroup(title: "操作历史", icon: "clock.arrow.circlepath") {
            Button {
                showOperationHistory = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("查看写入历史").font(.subheadline)
                        Text("回滚到任意历史版本").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showOperationHistory) {
            OperationHistoryView()
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.sectionSpacing) {
                // 隐私保障卡片（最醒目）
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.successGradient)
                            .frame(width: 56, height: 56)
                            .shadow(color: Color.green.opacity(0.25), radius: 8, y: 4)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                    }
                    Text("本应用永不联网")
                        .font(.headline)
                    Text("所有数据仅存储在您的设备上\n不会上传到任何服务器")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2).foregroundStyle(.green)
                        Text("已通过 App Store 隐私审核")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))

                // 标签设置
                settingsGroup(title: "标签设置", icon: "tag.fill") {
                    settingsPicker(title: "手机号默认标签", selection: $phoneDefaultLabel, options: ["手机", "Mobile", "电话"])
                    Divider()
                    settingsPicker(title: "邮箱默认标签", selection: $emailDefaultLabel, options: ["邮箱", "Email", "邮件"])
                }

                // 整理规则
                settingsGroup(title: "整理规则", icon: "gear") {
                    settingsToggle(title: "保留国际区号 (+86)", isOn: $preservePhonePrefix)
                    Divider()
                    settingsToggle(title: "操作前自动备份", isOn: $autoBackup)
                }

                // 联系人标签
                tagManagementSection

                // 操作历史
                operationHistorySection

                // 关于
                settingsGroup(title: "关于", icon: "info.circle.fill") {
                    settingsInfoRow(label: "版本", value: appVersionString)
                    Divider()
                    HStack {
                        Text("数据存储").font(.subheadline)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").font(.caption2)
                            Text("仅本地")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .padding()
        }
        .background(AppTheme.pageBackground)
        .accessibilityIdentifier("tab.settings.root")
        .navigationTitle("设置")
    }

    // MARK: - 通用组件

    private func settingsGroup<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(Color(hex: "4F7DF5"))
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            content()
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private func settingsPicker(title: String, selection: Binding<String>, options: [String]) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func settingsToggle(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func settingsInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
