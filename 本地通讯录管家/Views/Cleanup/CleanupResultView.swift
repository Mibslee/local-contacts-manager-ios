import SwiftUI

struct CleanupResultView: View {
    let summary: CleanupSummary?
    let processedContacts: [ContactItem]
    let onWriteBack: () -> Void
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.sectionSpacing) {
                    if let summary = summary {
                        resultHeader(summary)

                        ForEach(summary.results, id: \.option) { result in
                            ResultCard(result: result)
                        }

                        actionButtons
                    }
                }
                .padding()
            }
            .background(AppTheme.pageBackground)
            .navigationTitle("整理结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.subheadline.bold())
                }
            }
        }
    }

    private func resultHeader(_ summary: CleanupSummary) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(summary.hasImprovements ? AppTheme.successGradient : AppTheme.warningGradient)
                    .frame(width: 64, height: 64)
                    .shadow(color: summary.hasImprovements ? Color.green.opacity(0.25) : Color.orange.opacity(0.25), radius: 8, y: 4)
                Image(systemName: summary.hasImprovements ? "checkmark" : "info")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(summary.hasImprovements ? "整理完成" : "无需修改")
                .font(.title3.bold())

            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("\(processedContacts.count)")
                        .font(.title2.bold())
                    Text("联系人")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 32)
                VStack(spacing: 4) {
                    Text(String(format: "%.1fs", summary.duration))
                        .font(.title2.bold())
                    Text("耗时")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 2)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button(action: onWriteBack) {
                HStack {
                    Spacer()
                    Image(systemName: "square.and.arrow.down")
                    Text("写入系统通讯录")
                    Spacer()
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .background(AppTheme.primaryGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color(hex: "4F7DF5").opacity(0.3), radius: 8, y: 4)
            }

            Button(action: onExport) {
                HStack {
                    Spacer()
                    Image(systemName: "doc.text")
                    Text("导出为文件")
                    Spacer()
                }
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .padding(.vertical, 13)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

struct ResultCard: View {
    let result: CleanupResult
    @State private var showAffected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "4F7DF5").opacity(0.1))
                        .frame(width: 34, height: 34)
                    Image(systemName: result.option.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: "4F7DF5"))
                }
                Text(result.option.rawValue)
                    .font(.subheadline.bold())
                Spacer()
                if result.improved {
                    Text("优化 \(result.improvedCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            ForEach(result.details, id: \.self) { detail in
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if result.beforeCount > 0 || result.afterCount > 0 {
                HStack(spacing: 6) {
                    Text("整理前: \(result.beforeCount)").font(.caption)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    Text("整理后: \(result.afterCount)").font(.caption).foregroundStyle(.green)
                }
                .foregroundStyle(.secondary)
            }

            if !result.affectedContacts.isEmpty {
                Button { withAnimation { showAffected.toggle() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill").font(.caption2)
                        Text("查看受影响联系人 (\(result.affectedContacts.count))").font(.caption)
                        Spacer()
                        Image(systemName: showAffected ? "chevron.up" : "chevron.down").font(.caption2)
                    }
                    .foregroundStyle(Color(hex: "4F7DF5"))
                }

                if showAffected {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(result.affectedContacts) { contact in
                            HStack(spacing: 8) {
                                Text(String(contact.initials))
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(Color(hex: "7C5CE0"))
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(contact.fullName.isEmpty ? "未命名" : contact.fullName)
                                        .font(.caption.bold())
                                    if let phone = contact.phoneNumbers.first {
                                        Text(phone.value).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}
