import SwiftUI

struct MergePreviewView: View {
    let duplicateGroups: [ContactDeduplicator.DuplicateGroup]
    let onConfirm: (Set<UUID>) -> Void
    let onSkip: () -> Void

    @State private var selectedGroupIds: Set<UUID>
    @State private var expandedGroupId: UUID?

    init(duplicateGroups: [ContactDeduplicator.DuplicateGroup],
         onConfirm: @escaping (Set<UUID>) -> Void,
         onSkip: @escaping () -> Void) {
        self.duplicateGroups = duplicateGroups
        self.onConfirm = onConfirm
        self.onSkip = onSkip
        self._selectedGroupIds = State(initialValue: Set(duplicateGroups.map { $0.id }))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.pageBackground.ignoresSafeArea()

                if duplicateGroups.isEmpty {
                    emptyView
                } else {
                    contentView
                }
            }
            .navigationTitle("合并预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("跳过合并") { onSkip() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("确认合并 (\(selectedGroupIds.count) 组)") {
                        onConfirm(selectedGroupIds)
                    }
                    .font(.subheadline.bold())
                    .disabled(selectedGroupIds.isEmpty)
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("没有发现可合并的重复联系人")
                .font(.headline)
        }
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    // 摘要
                    HStack {
                        Image(systemName: "info.circle.fill").foregroundStyle(.blue).font(.subheadline)
                        Text("发现 \(duplicateGroups.count) 组重复联系人，可选择性地合并")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    ForEach(duplicateGroups) { group in
                        groupCard(group)
                    }
                }
            }

            // 底部操作（固定在底部，不随滚动）
            VStack(spacing: 10) {
                Button {
                    onConfirm(selectedGroupIds)
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("合并所选 \(selectedGroupIds.count) 组")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(selectedGroupIds.isEmpty ? Color.gray : Color(hex: "4F7DF5"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(selectedGroupIds.isEmpty)

                Button(role: .cancel) { onSkip() } label: {
                    Text("暂不合并，仅应用其他优化")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(AppTheme.pageBackground)
        }
    }

    private func groupCard(_ group: ContactDeduplicator.DuplicateGroup) -> some View {
        let isSelected = selectedGroupIds.contains(group.id)
        let isExpanded = expandedGroupId == group.id

        return VStack(spacing: 0) {
            // 头部：选择开关 + 摘要
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isSelected {
                        selectedGroupIds.remove(group.id)
                    } else {
                        selectedGroupIds.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color(hex: "4F7DF5") : .secondary)
                        .font(.system(size: 22))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.reason)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text("\(group.contacts.count) 位联系人 → 合并为 1 位")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedGroupId = isExpanded ? nil : group.id
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 展开详情：合并前后对比
            if isExpanded {
                VStack(spacing: 8) {
                    // 合并前（多条记录）
                    Text("合并前 (\(group.contacts.count) 位)")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)

                    ForEach(Array(group.contacts.enumerated()), id: \.element.id) { _, contact in
                        HStack(spacing: 8) {
                            Text(String(contact.initials))
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.orange.opacity(0.7))
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(contact.fullName.isEmpty ? "未命名" : contact.fullName)
                                    .font(.caption.bold())
                                Text(contact.phoneNumbers.map { $0.value }.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                    }

                    // 箭头
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.vertical, 4)

                    // 合并后（一条记录）
                    let merged = ContactDeduplicator.mergeContacts(group.contacts, strategy: .keepMoreInfo)
                    Text("合并后 (1 位)")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)

                    HStack(spacing: 8) {
                        Text(String(merged.initials))
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.green.opacity(0.7))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(merged.fullName.isEmpty ? "未命名" : merged.fullName)
                                .font(.caption.bold())
                            Text(merged.phoneNumbers.map { $0.value }.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                .background(Color.secondary.opacity(0.04))
            }
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.smallRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.smallRadius)
                .stroke(isSelected ? Color(hex: "4F7DF5").opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
        .padding(.horizontal)
    }
}
