import SwiftUI
import UniformTypeIdentifiers
import Contacts

struct ImportView: View {
    @ObservedObject var appVM: AppViewModel
    @StateObject private var importVM = ImportViewModel()
    @State private var showFilePicker = false
    @State private var showMergeConfirm = false
    @State private var mergeResult: (success: Int, failed: Int)?

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.sectionSpacing) {
                // 顶部图标区
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.primaryGradient)
                            .frame(width: 72, height: 72)
                            .shadow(color: Color(hex: "4F7DF5").opacity(0.25), radius: 10, y: 5)
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                    }
                    Text("导入通讯录")
                        .font(.title3.bold())
                    Text("支持 vCard (.vcf) 和 CSV 文件导入\n导入前会自动进行字段映射预览")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                // 导入按钮
                VStack(spacing: 10) {
                    importButton(icon: "doc.text", title: "从 vCard 文件导入", subtitle: ".vcf 格式") {
                        importVM.selectedFileType = .vcard
                        showFilePicker = true
                    }
                    importButton(icon: "tablecells", title: "从 CSV 文件导入", subtitle: ".csv 格式") {
                        importVM.selectedFileType = .csv
                        showFilePicker = true
                    }
                }

                // 导入结果
                if let result = importVM.importResult {
                    importResultCard(result)
                }

                // 已导入联系人
                if !importVM.importedContacts.isEmpty {
                    importedContactsSection
                }
            }
            .padding()
        }
        .background(AppTheme.pageBackground)
        .accessibilityIdentifier("tab.import.root")
        .navigationTitle("导入")
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: importVM.selectedFileType == .vcard ? [.vCard] : [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first, url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        importVM.importFile(data: data, fileName: url.lastPathComponent)
                    }
                }
            case .failure(let error):
                print("文件选择失败: \(error)")
            }
        }
        .alert("合并到通讯录", isPresented: $showMergeConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认合并", role: .destructive) {
                mergeResult = importVM.mergeToSystemDirect()
            }
        } message: {
            Text("将 \(importVM.importedContacts.count) 位联系人合并到系统通讯录")
        }
        .alert("合并完成", isPresented: .init(
            get: { mergeResult != nil },
            set: { if !$0 { mergeResult = nil } }
        )) {
            Button("确定") {
                mergeResult = nil
                Task { await appVM.refresh() }
            }
        } message: {
            if let r = mergeResult {
                Text("成功: \(r.success), 失败: \(r.failed)")
            }
        }
    }

    private func importButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: "4F7DF5").opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(Color(hex: "4F7DF5"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private func importResultCard(_ result: ContactImporter.ImportResult) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("导入结果").font(.headline)
                Spacer()
            }
            HStack(spacing: 0) {
                resultMiniStat(label: "总计", value: "\(result.total)", color: .blue)
                Divider().frame(height: 32)
                resultMiniStat(label: "成功", value: "\(result.success)", color: .green)
                Divider().frame(height: 32)
                resultMiniStat(label: "失败", value: "\(result.failed)", color: result.failed > 0 ? .red : .secondary)
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private func resultMiniStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var importedContactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导入的联系人 (\(importVM.importedContacts.count))")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(importVM.importedContacts.prefix(20)) { contact in
                    ContactRow(contact: contact)
                    if contact.id != importVM.importedContacts.prefix(20).last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))

            if importVM.importedContacts.count > 20 {
                Text("还有 \(importVM.importedContacts.count - 20) 位联系人...")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Button { showMergeConfirm = true } label: {
                HStack {
                    Spacer()
                    Image(systemName: "person.badge.plus")
                    Text("合并到系统通讯录")
                    Spacer()
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .background(AppTheme.primaryGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color(hex: "4F7DF5").opacity(0.3), radius: 8, y: 4)
            }
        }
    }
}
