import SwiftUI

struct OperationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var history = OperationHistoryManager.shared.history
    @State private var confirmRestore: OperationRecord?
    @State private var restoring = false
    @State private var restoreDone = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.pageBackground.ignoresSafeArea()

                if history.isEmpty {
                    emptyView
                } else {
                    List {
                        ForEach(history) { record in
                            historyRow(record)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("操作历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("确认回滚", isPresented: .init(
                get: { confirmRestore != nil },
                set: { if !$0 { confirmRestore = nil } }
            )) {
                Button("取消", role: .cancel) {}
                Button("确认回滚", role: .destructive) {
                    guard let record = confirmRestore else { return }
                    restoring = true
                    Task {
                        let ok = await OperationHistoryManager.shared.restore(to: record)
                        restoring = false
                        restoreDone = ok
                        confirmRestore = nil
                    }
                }
            } message: {
                if let r = confirmRestore {
                    Text("将清空当前通讯录，恢复到「\(r.description)」时的状态（共 \(r.contactCount) 位联系人）。此操作不可撤销。")
                }
            }
            .alert("回滚完成", isPresented: $restoreDone) {
                Button("确定") { dismiss() }
            } message: {
                Text("已成功恢复到所选版本，请返回首页刷新查看。")
            }
            .overlay {
                if restoring {
                    ZStack {
                        Color(.systemBackground).opacity(0.8).ignoresSafeArea()
                        ProgressView("正在恢复...")
                    }
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("暂无操作记录").font(.headline).foregroundStyle(.secondary)
            Text("执行写入操作后，历史记录将显示在此处")
                .font(.subheadline).foregroundStyle(.tertiary)
        }
    }

    private func historyRow(_ record: OperationRecord) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "4F7DF5").opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.down.to.line.circle")
                    .foregroundStyle(Color(hex: "4F7DF5"))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(record.description)
                    .font(.subheadline.bold())
                HStack(spacing: 4) {
                    Image(systemName: "person.2").font(.caption2)
                    Text("\(record.contactCount) 位").font(.caption)
                    Text("·").font(.caption).foregroundStyle(.tertiary)
                    Text(record.formattedDate).font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                confirmRestore = record
            } label: {
                Text("回滚")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
