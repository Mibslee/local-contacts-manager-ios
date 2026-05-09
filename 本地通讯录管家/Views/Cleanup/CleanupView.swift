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
        ScrollView {
            VStack(spacing: AppTheme.sectionSpacing) {
                // 备份状态卡片
                if cleanupVM.hasBackup {
                    backupCard
                }

                // 说明
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                    Text("选择需要优化的项目，系统会自动备份后执行清理")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)

                // 全选控制
                HStack {
                    Button {
                        if cleanupVM.selectedOptions.count == CleanupOption.allCases.count {
                            cleanupVM.selectedOptions.removeAll()
                        } else {
                            cleanupVM.selectedOptions = Set(CleanupOption.allCases)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: cleanupVM.selectedOptions.count == CleanupOption.allCases.count ? "checkmark.square.fill" : "square")
                                .foregroundStyle(cleanupVM.selectedOptions.count == CleanupOption.allCases.count ? .blue : .secondary)
                            Text(cleanupVM.selectedOptions.count == CleanupOption.allCases.count ? "取消全选" : "全选")
                                .font(.subheadline.bold())
                        }
                    }
                    Spacer()
                    Text("\(cleanupVM.selectedOptions.count)/\(CleanupOption.allCases.count)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 4)

                // 选项列表
                VStack(spacing: 8) {
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

                // 合并策略
                if cleanupVM.selectedOptions.contains(.contactDeduplicate) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("合并策略")
                            .font(.subheadline.bold())
                        Picker("策略", selection: $cleanupVM.mergeStrategy) {
                            ForEach(MergeStrategy.allCases, id: \.self) { strategy in
                                Text(strategy.rawValue).tag(strategy)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding()
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                }

                // 开始按钮
                Button {
                    showConfirmCleanup = true
                } label: {
                    HStack {
                        Spacer()
                        if cleanupVM.isProcessing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "wand.and.stars")
                            Text("开始整理")
                        }
                        Spacer()
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.vertical, 16)
                    .background(cleanupVM.selectedOptions.isEmpty ? Color.gray.opacity(0.4) : AppTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: cleanupVM.selectedOptions.isEmpty ? .clear : Color(hex: "4F7DF5").opacity(0.3), radius: 8, y: 4)
                }
                .disabled(cleanupVM.selectedOptions.isEmpty || cleanupVM.isProcessing)
            }
            .padding()
        }
        .background(AppTheme.pageBackground)
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
                    Task { writeBackResult = await cleanupVM.writeBackToSystemDirect() }
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
                Task { try? await Task.sleep(nanoseconds: 500_000_000); await appVM.refresh() }
            }
        } message: {
            if let r = writeBackResult {
                Text("成功写入 \(r.success) 位联系人" + (r.failed > 0 ? "，失败 \(r.failed) 位" : ""))
            }
        }
        .alert("恢复通讯录", isPresented: $showRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认恢复", role: .destructive) {
                Task { if await cleanupVM.restoreFromBackup() { await appVM.refresh() } }
            }
        } message: { Text("将从备份文件恢复通讯录到备份时的状态") }
    }

    private var backupCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("已备份通讯录").font(.subheadline.bold())
                Text("如需恢复，请点击下方按钮").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) { showRestoreConfirm = true } label: {
                Text("恢复")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
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
                    .foregroundStyle(isSelected ? Color(hex: "4F7DF5") : .secondary)
                    .font(.system(size: 20))

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color(hex: "4F7DF5").opacity(0.12) : Color.secondary.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: option.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? Color(hex: "4F7DF5") : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.rawValue)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(option.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.smallRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.smallRadius)
                    .stroke(isSelected ? Color(hex: "4F7DF5").opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
