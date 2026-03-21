import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @ObservedObject var appVM: AppViewModel
    @StateObject private var importVM = ImportViewModel()
    @State private var showFilePicker = false
    @State private var showMergeConfirm = false
    @State private var mergeResult: (success: Int, failed: Int)?

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)

                    Text("导入通讯录")
                        .font(.title3.bold())

                    Text("支持 vCard (.vcf) 和 CSV 文件导入\n导入前会自动进行字段映射预览")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    importVM.selectedFileType = .vcard
                    showFilePicker = true
                } label: {
                    Label("从 vCard 文件导入", systemImage: "doc.text")
                }

                Button {
                    importVM.selectedFileType = .csv
                    showFilePicker = true
                } label: {
                    Label("从 CSV 文件导入", systemImage: "tablecells")
                }
            }

            if let result = importVM.importResult {
                Section("导入结果") {
                    HStack {
                        Text("总计")
                        Spacer()
                        Text("\(result.total)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("成功")
                        Spacer()
                        Text("\(result.success)")
                            .foregroundStyle(.green)
                    }
                    HStack {
                        Text("失败")
                        Spacer()
                        Text("\(result.failed)")
                            .foregroundStyle(.red)
                    }
                }
            }

            if !importVM.importedContacts.isEmpty {
                Section("导入的联系人 (\(importVM.importedContacts.count))") {
                    ForEach(importVM.importedContacts.prefix(20)) { contact in
                        ContactRow(contact: contact)
                    }

                    if importVM.importedContacts.count > 20 {
                        Text("还有 \(importVM.importedContacts.count - 20) 位联系人...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        showMergeConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "person.badge.plus")
                            Text("合并到系统通讯录")
                            Spacer()
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("导入")
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: importVM.selectedFileType == .vcard
                ? [.vCard]
                : [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let data = try? Data(contentsOf: url) {
                            importVM.importFile(data: data, fileName: url.lastPathComponent)
                        }
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
            if let result = mergeResult {
                Text("成功: \(result.success), 失败: \(result.failed)")
            }
        }
    }
}


