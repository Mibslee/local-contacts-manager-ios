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
                VStack(spacing: 20) {
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
            .navigationTitle("整理结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func resultHeader(_ summary: CleanupSummary) -> some View {
        VStack(spacing: 12) {
            Image(systemName: summary.hasImprovements ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(summary.hasImprovements ? .green : .orange)

            Text(summary.hasImprovements ? "整理完成" : "无需修改")
                .font(.title2.bold())

            HStack(spacing: 20) {
                VStack {
                    Text("\(processedContacts.count)")
                        .font(.title.bold())
                    Text("联系人")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 30)

                VStack {
                    Text(String(format: "%.1fs", summary.duration))
                        .font(.title.bold())
                    Text("耗时")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: onWriteBack) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("写入系统通讯录")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button(action: onExport) {
                HStack {
                    Image(systemName: "doc.text")
                    Text("导出为文件")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.gray.opacity(0.15))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct ResultCard: View {
    let result: CleanupResult
    @State private var showAffected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: result.option.icon)
                    .foregroundStyle(.blue)
                Text(result.option.rawValue)
                    .font(.subheadline.bold())
                Spacer()
                if result.improved {
                    Text("优化 \(result.improvedCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            ForEach(result.details, id: \.self) { detail in
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if result.beforeCount > 0 || result.afterCount > 0 {
                HStack {
                    Text("整理前: \(result.beforeCount)")
                        .font(.caption)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Text("整理后: \(result.afterCount)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            if !result.affectedContacts.isEmpty {
                Button {
                    withAnimation { showAffected.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                        Text("查看受影响联系人 (\(result.affectedContacts.count))")
                            .font(.caption)
                        Spacer()
                        Image(systemName: showAffected ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.blue)
                }

                if showAffected {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(result.affectedContacts) { contact in
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(.blue.opacity(0.15))
                                        .frame(width: 28, height: 28)
                                    Text(String(contact.initials))
                                        .font(.caption2.bold())
                                        .foregroundStyle(.blue)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(contact.fullName.isEmpty ? "未命名" : contact.fullName)
                                        .font(.caption.bold())
                                    if let phone = contact.phoneNumbers.first {
                                        Text(phone.value)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
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
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
