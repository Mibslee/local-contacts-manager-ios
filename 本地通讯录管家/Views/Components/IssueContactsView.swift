import SwiftUI

struct IssueContactsView: View {
    let title: String
    let issueType: HealthReport.IssueType
    let contacts: [ContactItem]
    @State private var searchText = ""
    @State private var selectedContacts: Set<ContactItem.ID> = []

    var filteredContacts: [ContactItem] {
        if searchText.isEmpty { return contacts }
        return contacts.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText) ||
            $0.phoneNumbers.contains(where: { $0.value.contains(searchText) })
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack {
                    Text("\(contacts.count) 位联系人存在「\(title)」问题")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: toggleSelectAll) {
                        Text(selectedContacts.count == filteredContacts.count ? "取消全选" : "全选")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                ForEach(filteredContacts) { contact in
                    HStack(spacing: 12) {
                        Button(action: { toggleSelection(contact) }) {
                            Image(systemName: selectedContacts.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedContacts.contains(contact.id) ? .blue : .secondary)
                                .font(.system(size: 20))
                        }

                        ZStack {
                            Circle()
                                .fill(.blue.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Text(String(contact.initials))
                                .font(.headline.bold())
                                .foregroundStyle(.blue)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(contact.fullName.isEmpty ? "未命名" : contact.fullName)
                                .font(.body.bold())
                                .lineLimit(1)

                            issueDetail(for: contact)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                    Divider()
                        .padding(.leading, 88)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索联系人")
    }

    private func toggleSelectAll() {
        if selectedContacts.count == filteredContacts.count {
            selectedContacts.removeAll()
        } else {
            selectedContacts = Set(filteredContacts.map { $0.id })
        }
    }

    private func toggleSelection(_ contact: ContactItem) {
        if selectedContacts.contains(contact.id) {
            selectedContacts.remove(contact.id)
        } else {
            selectedContacts.insert(contact.id)
        }
    }

    @ViewBuilder
    private func issueDetail(for contact: ContactItem) -> some View {
        switch issueType {
        case .nameNeedsStandardize, .nameNotSplit:
            let display = contact.familyName.isEmpty ? contact.givenName : contact.familyName
            Text("姓名: \(display) → 需要拆分为姓/名")
        case .phoneGarbled:
            let phones = contact.phoneNumbers.map { $0.value }.joined(separator: ", ")
            Text("异常号码: \(phones)")
        case .phonePrefixInconsistent:
            let prefixes = Set(contact.phoneNumbers.map { extractPrefix($0.value) })
            Text("前缀混用: \(prefixes.joined(separator: ", "))")
        case .phoneLabelInconsistent:
            let labels = Set(contact.phoneNumbers.map { $0.label })
            Text("标签混用: \(labels.joined(separator: ", "))")
        case .phoneDuplicate:
            let dupes = ContactDeduplicator.findDuplicatePhonesInContact(contact)
            Text("重复号码: \(dupes.joined(separator: ", "))")
        case .emailLabelInconsistent:
            let labels = Set(contact.emailAddresses.map { $0.label })
            Text("标签混用: \(labels.joined(separator: ", "))")
        case .emailDuplicate:
            let dupes = ContactDeduplicator.findDuplicateEmailsInContact(contact)
            Text("重复邮箱: \(dupes.joined(separator: ", "))")
        case .emailInvalid:
            let invalids = contact.emailAddresses.filter { !ContactNormalizer.isValidEmail($0.value) }
            Text("无效邮箱: \(invalids.map(\.value).joined(separator: ", "))")
        case .contactDuplicate:
            Text("存在重复记录")
        case .emptyContact:
            Text("无任何联系方式")
        }
    }

    private func extractPrefix(_ phone: String) -> String {
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        if cleaned.hasPrefix("+86") { return "+86" }
        if cleaned.hasPrefix("86") && cleaned.count > 11 { return "86" }
        return "无前缀"
    }
}
