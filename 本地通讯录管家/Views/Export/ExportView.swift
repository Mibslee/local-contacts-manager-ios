import SwiftUI

struct ExportView: View {
    @ObservedObject var appVM: AppViewModel
    @State private var selectedFormat: ExportFormat = .vcard
    @State private var exportAll = true
    @State private var showShareSheet = false
    @State private var exportFileURL: URL?
    @State private var showExportSuccess = false

    var contactsToExport: [ContactItem] { appVM.contacts }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.sectionSpacing) {
                // 顶部图标
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.warningGradient)
                            .frame(width: 72, height: 72)
                            .shadow(color: Color(hex: "FF9500").opacity(0.25), radius: 10, y: 5)
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                    }
                    Text("导出通讯录")
                        .font(.title3.bold())
                    Text("将联系人导出为文件并分享")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                // 格式选择
                VStack(alignment: .leading, spacing: 10) {
                    Text("导出格式").font(.subheadline.bold()).foregroundStyle(.secondary)

                    ForEach(ExportFormat.allCases) { format in
                        Button { selectedFormat = format } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selectedFormat == format ? Color(hex: "4F7DF5").opacity(0.12) : Color.secondary.opacity(0.06))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: format.icon)
                                        .font(.title3)
                                        .foregroundStyle(selectedFormat == format ? Color(hex: "4F7DF5") : .secondary)
                                }
                                Text(format.rawValue)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedFormat == format {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color(hex: "4F7DF5"))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(AppTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.smallRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.smallRadius)
                                    .stroke(selectedFormat == format ? Color(hex: "4F7DF5").opacity(0.3) : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 导出信息
                VStack(spacing: 0) {
                    infoRow(label: "联系人数量", value: "\(contactsToExport.count) 位")
                    Divider().padding(.leading, 16)
                    infoRow(label: "导出格式", value: selectedFormat.rawValue)
                }
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))

                // 导出按钮
                Button { performExport() } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                        Text("导出并分享")
                        Spacer()
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.vertical, 16)
                    .background(contactsToExport.isEmpty ? Color.gray.opacity(0.4) : AppTheme.warningGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: contactsToExport.isEmpty ? .clear : Color(hex: "FF9500").opacity(0.3), radius: 8, y: 4)
                }
                .disabled(contactsToExport.isEmpty)
            }
            .padding()
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("导出")
        .sheet(isPresented: $showShareSheet) {
            if let url = exportFileURL { ShareSheet(items: [url]) }
        }
        .alert("导出成功", isPresented: $showExportSuccess) {
            Button("确定") {}
        } message: {
            Text("已导出 \(contactsToExport.count) 位联系人为 \(selectedFormat.rawValue) 文件")
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func performExport() {
        let contacts = contactsToExport
        var fileURL: URL?
        switch selectedFormat {
        case .vcard:
            fileURL = ContactExporter.saveToFile(content: ContactExporter.exportToVCard(contacts), fileName: "通讯录导出.vcf")
        case .csv, .excel:
            fileURL = ContactExporter.saveToFile(content: ContactExporter.exportToCSV(contacts), fileName: "通讯录导出.csv")
        }
        if let url = fileURL {
            exportFileURL = url
            showShareSheet = true
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
