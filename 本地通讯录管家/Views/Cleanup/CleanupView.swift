import SwiftUI

struct CleanupView: View {
    @ObservedObject var appVM: AppViewModel
    @StateObject private var cleanupVM = CleanupViewModel()
    @State private var showConfirmCleanup = false
    @State private var showWriteBack = false
    @State private var showRestoreConfirm = false
    @State private var writeBackResult: (success: Int, failed: Int)?
    @State private var backupDone = false

    var body: some View {
        List {
            if cleanupVM.hasBackup {
                Section {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text("已备份通讯录")
                                .font(.subheadline.bold())
                            Text("如需恢复，请点击下方按钮")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Button(role: .destructive) {
                        showRestoreConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.counterclockwise")
                            Text("恢复通讯录")
                            Spacer()
                        }
                    }
                } header: {
                    Text("备份与恢复")
                }
            }

            Section {
                Text("选择需要优化的项目，系统会自动备份后执行清理")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("整理选项") {
                HStack {
                    Button {
                        if cleanupVM.selectedOptions.count == CleanupOption.allCases.count {
                            cleanupVM.selectedOptions.removeAll()
                        } else {
                            cleanupVM.selectedOptions = Set(CleanupOption.allCases)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: cleanupVM.selectedOptions.count == CleanupOption.allCases.count ? "checkmark.square.fill" : "square")
                            Text(cleanupVM.selectedOptions.count == CleanupOption.allCases.count ? "取消全选" : "全选")
                                .font(.subheadline)
                        }
                    }
                    Spacer()
                    Text("\(cleanupVM.selectedOptions.count)/\(CleanupOption.allCases.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(CleanupOption.allCases) { option in
                    CleanupOptionRow(option: option, isSelected: cleanupVM.selectedOptions.contains(option)) {
                        if cleanupVM.selectedOptions.contains(option) {
                            cleanupVM.selectedOptions.remove(option)
                        } else {
                            cleanupVM.selectedOptions.insert(option)
                        }
                    }
                }
            }

            if cleanupVM.selectedOptions.contains(.contactDeduplicate) {
                Section("合并策略") {
                    Picker("策略", selection: $cleanupVM.mergeStrategy) {
                        ForEach(MergeStrategy.allCases, id: \.self) { strategy in
                            Text(strategy.rawValue).tag(strategy)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                Button {
                    showConfirmCleanup = true
                } label: {
                    HStack {
                        Spacer()
                        if cleanupVM.isProcessing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "wand.and.stars")
                            Text("开始整理")
                        }
                        Spacer()
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(cleanupVM.selectedOptions.isEmpty ? .gray : .blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(cleanupVM.selectedOptions.isEmpty || cleanupVM.isProcessing)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("通讯录整理")
        .alert("确认整理", isPresented: $showConfirmCleanup) {
            Button("取消", role: .cancel) {}
            Button("开始整理", role: .destructive) {
                Task {
                    _ = await cleanupVM.backupContacts(appVM.contacts)
                    let processed = await cleanupVM.runCleanup(on: appVM.contacts)
                    appVM.contacts = processed
                    appVM.healthReport = HealthAnalyzer.analyze(processed)
                }
            }
        } message: {
            Text("将先备份通讯录，然后对 \(appVM.contacts.count) 位联系人执行 \(cleanupVM.selectedOptions.count) 项整理")
        }
        .sheet(isPresented: $cleanupVM.showResult) {
            CleanupResultView(
                summary: cleanupVM.cleanupSummary,
                processedContacts: cleanupVM.processedContacts,
                onWriteBack: { showWriteBack = true },
                onExport: {}
            )
        }
        .alert("写入系统通讯录", isPresented: $showWriteBack) {
            Button("取消", role: .cancel) {}
            if !cleanupVM.isWritingBack {
                Button("确认写入", role: .destructive) {
                    Task {
                        writeBackResult = await cleanupVM.writeBackToSystemDirect()
                    }
                }
            }
        } message: {
            if cleanupVM.isWritingBack {
                Text("正在写入，请稍候...")
            } else {
                Text("将清空系统通讯录并重新写入 \(cleanupVM.processedContacts.count) 位联系人（已自动备份）")
            }
        }
        .alert("写入完成", isPresented: .init(
            get: { writeBackResult != nil },
            set: { if !$0 { writeBackResult = nil } }
        )) {
            Button("确定") {
                writeBackResult = nil
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await appVM.refresh()
                }
            }
        } message: {
            if let result = writeBackResult {
                Text("成功写入 \(result.success) 位联系人" + (result.failed > 0 ? "，失败 \(result.failed) 位" : ""))
            }
        }
        .alert("恢复通讯录", isPresented: $showRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认恢复", role: .destructive) {
                Task {
                    let ok = await cleanupVM.restoreFromBackup()
                    if ok {
                        await appVM.refresh()
                    }
                }
            }
        } message: {
            Text("将从备份文件恢复通讯录到备份时的状态")
        }
    }
}

struct CleanupOptionRow: View {
    let option: CleanupOption
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)

                Image(systemName: option.icon)
                    .foregroundStyle(.blue)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.rawValue)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(option.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
