import SwiftUI

struct IssueContactsView: View {
    let title: String
    let issueType: HealthReport.IssueType
    let contacts: [ContactItem]
    @State private var searchText = ""
    @State private var selectedContacts: Set<ContactItem.ID> = []

    private static let avatarColors: [Color] = [
        Color(hex: "4F7DF5"), Color(hex: "7C5CE0"), Color(hex: "00B4D8"),
        Color(hex: "E17055"), Color(hex: "00B894"), Color(hex: "6C5CE7")
    ]

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
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("\(contacts.count) 位联系人存在「\(title)」问题")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: toggleSelectAll) {
                        Text(selectedContacts.count == filteredContacts.count ? "取消全选" : "全选")
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                ForEach(filteredContacts) { contact in
                    contactRow(contact)
                }
            }
        }
        .background(AppTheme.pageBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索联系人")
    }

    private func contactRow(_ contact: ContactItem) -> some View {
        HStack(spacing: 12) {
            Button(action: { toggleSelection(contact) }) {
                Image(systemName: selectedContacts.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedContacts.contains(contact.id) ? .blue : .secondary)
                    .font(.system(size: 22))
            }

            let hash = abs(contact.id.hashValue)
            Text(String(contact.initials))
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Self.avatarColors[hash % Self.avatarColors.count])
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.fullName.isEmpty ? "未命名" : contact.fullName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                issueDetail(for: contact)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 2)
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
            let prefixes = Set(contact.phoneNumbers.map { ContactValidator.extractPhonePrefix($0.value) })
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
}
