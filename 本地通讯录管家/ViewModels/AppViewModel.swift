import Foundation
import SwiftUI
import Contacts
import Combine

@MainActor
class AppViewModel: ObservableObject {
    @Published var contacts: [ContactItem] = []
    @Published var healthReport: HealthReport = .empty
    @Published var isLoading = false
    @Published var isAuthorized = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var loadingProgress: Double = 0
    @Published var loadedContactsCount: Int = 0

    /// 重复联系人缓存，避免每次打开详情页重新计算
    var cachedDuplicateContacts: [ContactItem]?

    /// 当前选中的标签筛选
    @Published var selectedTag: String?

    /// 所有联系人中出现的唯一标签列表
    var allTags: [String] {
        let tagSet = Set(contacts.flatMap { $0.tags })
        let predefined = TagManager.shared.tags
        return Array(Set(predefined + tagSet)).sorted()
    }

    /// 按标签筛选后的联系人
    var taggedContacts: [ContactItem] {
        guard let tag = selectedTag else { return contacts }
        return contacts.filter { $0.tags.contains(tag) }
    }

    var filteredContacts: [ContactItem] {
        if searchText.isEmpty { return contacts }
        return contacts.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText) ||
            $0.phoneNumbers.contains(where: { $0.value.contains(searchText) }) ||
            $0.emailAddresses.contains(where: { $0.value.localizedCaseInsensitiveContains(searchText) })
        }
    }

    func checkAuthorization() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        let nowAuthorized = (status == .authorized)
        isAuthorized = isAuthorized || nowAuthorized
        if nowAuthorized && contacts.isEmpty {
            loadContactsInBackground()
        }
    }

    func requestAccess() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized {
            isAuthorized = true
            loadContactsInBackground()
            return
        }
        Task.detached(priority: .userInitiated) { @MainActor in
            let store = CNContactStore()
            do {
                let granted = try await store.requestAccess(for: .contacts)
                if granted {
                    self.isAuthorized = true
                    self.loadContactsInBackground()
                }
            } catch {
                self.isAuthorized = false
            }
        }
    }

    /// 在后台执行所有加载逻辑
    private func loadContactsInBackground() {
        isLoading = true
        errorMessage = nil
        loadingProgress = 0
        loadedContactsCount = 0
        cachedDuplicateContacts = nil

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor
        ]

        Task.detached(priority: .userInitiated) { [keys = keysToFetch] in
            let store = CNContactStore()
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .userDefault
            var fetched: [ContactItem] = []
            do {
                try store.enumerateContacts(with: request) { cnContact, _ in
                    fetched.append(ContactItem(cnContact: cnContact))
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "读取通讯录失败: \(error.localizedDescription)"
                    self.contacts = []
                    self.healthReport = .empty
                    self.isLoading = false
                }
                return
            }

            if fetched.isEmpty {
                // Auto-import from Documents/original_contacts.vcf
                do {
                    let fileManager = FileManager.default
                    guard let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                        await MainActor.run {
                            self.contacts = []
                            self.loadedContactsCount = 0
                            self.isLoading = false
                        }
                        return
                    }

                    let vcfURL = docsDir.appendingPathComponent("original_contacts.vcf")
                    guard fileManager.fileExists(atPath: vcfURL.path),
                          let vcfData = try? Data(contentsOf: vcfURL) else {
                        await MainActor.run {
                            self.contacts = []
                            self.loadedContactsCount = 0
                            self.isLoading = false
                        }
                        return
                    }

                    let cnParsed = try CNContactVCardSerialization.contacts(with: vcfData)
                    print("[AutoImport] 解析到 \(cnParsed.count) 个联系人，开始写入...")

                    let saveReq = CNSaveRequest()
                    for c in cnParsed {
                        saveReq.add(c.mutableCopy() as! CNMutableContact, toContainerWithIdentifier: nil)
                    }
                    try store.execute(saveReq)
                    print("[AutoImport] 写入成功")

                    // Reload
                    var reloaded: [ContactItem] = []
                    let req2 = CNContactFetchRequest(keysToFetch: keys)
                    req2.sortOrder = .userDefault
                    try store.enumerateContacts(with: req2) { cnContact, _ in
                        reloaded.append(ContactItem(cnContact: cnContact))
                    }
                    print("[AutoImport] 重新加载: \(reloaded.count)")

                    let report = HealthAnalyzer.analyze(reloaded)
                    let groups = ContactDeduplicator.findDuplicates(in: reloaded)
                    let cached = groups.flatMap { $0.contacts }

                    await MainActor.run {
                        self.contacts = reloaded
                        self.loadedContactsCount = reloaded.count
                        self.healthReport = report
                        self.cachedDuplicateContacts = cached
                        self.isLoading = false
                    }
                } catch {
                    print("[AutoImport] 失败: \(error)")
                    await MainActor.run {
                        self.contacts = []
                        self.loadedContactsCount = 0
                        self.isLoading = false
                    }
                }
            } else {
                await MainActor.run {
                    self.contacts = fetched
                    self.loadedContactsCount = fetched.count
                    self.isLoading = false
                }

                let report = HealthAnalyzer.analyze(fetched)
                let groups = ContactDeduplicator.findDuplicates(in: fetched)
                let cached = groups.flatMap { $0.contacts }
                await MainActor.run {
                    self.healthReport = report
                    self.cachedDuplicateContacts = cached
                }
            }
        }
    }

    func refresh() async {
        loadContactsInBackground()
    }

    func contactsForIssue(_ type: HealthReport.IssueType) -> [ContactItem] {
        switch type {
        case .nameNeedsStandardize, .nameNotSplit:
            return contacts.filter { ContactValidator.needsNameFix($0) }
        case .phonePrefixInconsistent:
            return contacts.filter { c in
                let prefixes = Set(c.phoneNumbers.map { ContactValidator.extractPhonePrefix($0.value) })
                return prefixes.count > 1
            }
        case .phoneLabelInconsistent:
            return contacts.filter { Set($0.phoneNumbers.map { $0.label }).count > 1 }
        case .phoneDuplicate:
            return contacts.filter { !ContactDeduplicator.findDuplicatePhonesInContact($0).isEmpty }
        case .phoneGarbled:
            return contacts.filter { c in
                c.phoneNumbers.contains { phone in
                    let digits = phone.value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    return !ContactValidator.isValidChinesePhone(digits)
                }
            }
        case .emailLabelInconsistent:
            return contacts.filter { Set($0.emailAddresses.map { $0.label }).count > 1 }
        case .emailDuplicate:
            return contacts.filter { !ContactDeduplicator.findDuplicateEmailsInContact($0).isEmpty }
        case .emailInvalid:
            return contacts.filter { c in
                c.emailAddresses.contains { !ContactNormalizer.isValidEmail($0.value) }
            }
        case .contactDuplicate:
            if let cached = cachedDuplicateContacts { return cached }
            let groups = ContactDeduplicator.findDuplicates(in: contacts)
            let result = groups.flatMap { $0.contacts }
            cachedDuplicateContacts = result
            return result
        case .emptyContact:
            return contacts.filter { $0.isEmpty }
        }
    }

    func issueTitle(for type: HealthReport.IssueType) -> String {
        return type.rawValue
    }
}
