import SwiftUI

struct ExportView: View {
    @ObservedObject var appVM: AppViewModel
    @State private var selectedFormat: ExportFormat = .vcard
    @State private var exportAll = true
    @State private var showShareSheet = false
    @State private var exportFileURL: URL?
    @State private var showExportSuccess = false

    var contactsToExport: [ContactItem] {
        appVM.contacts
    }

    var body: some View {
        List {
            Section("导出格式") {
                ForEach(ExportFormat.allCases) { format in
                    Button {
                        selectedFormat = format
                    } label: {
                        HStack {
                            Image(systemName: format.icon)
                                .foregroundStyle(.blue)
                                .frame(width: 28)
                            Text(format.rawValue)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedFormat == format {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            Section("导出信息") {
                HStack {
                    Text("联系人数量")
                    Spacer()
                    Text("\(contactsToExport.count) 位")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("导出格式")
                    Spacer()
                    Text(selectedFormat.rawValue)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    performExport()
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                        Text("导出并分享")
                        Spacer()
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(contactsToExport.isEmpty ? .gray : .blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(contactsToExport.isEmpty)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("导出")
        .sheet(isPresented: $showShareSheet) {
            if let url = exportFileURL {
                ShareSheet(items: [url])
            }
        }
        .alert("导出成功", isPresented: $showExportSuccess) {
            Button("确定") {}
        } message: {
            Text("已导出 \(contactsToExport.count) 位联系人为 \(selectedFormat.rawValue) 文件")
        }
        .onAppear {
            print("ExportView appeared, contacts count: \(appVM.contacts.count)")
        }
    }

    private func performExport() {
        let contacts = contactsToExport
        var fileURL: URL?

        switch selectedFormat {
        case .vcard:
            let content = ContactExporter.exportToVCard(contacts)
            fileURL = ContactExporter.saveToFile(content: content, fileName: "通讯录导出.vcf")
        case .csv:
            let content = ContactExporter.exportToCSV(contacts)
            fileURL = ContactExporter.saveToFile(content: content, fileName: "通讯录导出.csv")
        case .excel:
            let content = ContactExporter.exportToCSV(contacts)
            fileURL = ContactExporter.saveToFile(content: content, fileName: "通讯录导出.csv")
        }

        if let url = fileURL {
            exportFileURL = url
            showShareSheet = true
            print("导出成功: \(url.path)")
        } else {
            print("导出失败: 无法生成文件")
            showExportSuccess = true
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
