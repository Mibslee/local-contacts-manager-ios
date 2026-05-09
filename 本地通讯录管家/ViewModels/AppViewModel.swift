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
        isAuthorized = status == .authorized
        if isAuthorized && contacts.isEmpty {
            Task { await loadContacts() }
        }
    }

    func requestAccess() async {
        let store = CNContactStore()
        do {
            let granted = try await store.requestAccess(for: .contacts)
            if granted {
                isAuthorized = true
                await loadContacts()
            } else {
                isAuthorized = false
                errorMessage = "通讯录访问被拒绝"
            }
        } catch {
            isAuthorized = false
            errorMessage = "通讯录访问失败: \(error.localizedDescription)"
        }
    }

    func loadContacts() async {
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

        let result: (contacts: [ContactItem], error: String?) = await Task.detached {
            let store = CNContactStore()
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            request.sortOrder = .userDefault
            var fetched: [ContactItem] = []
            var fetchError: String?
            var count = 0

            do {
                try store.enumerateContacts(with: request) { cnContact, _ in
                    fetched.append(ContactItem(cnContact: cnContact))
                    count += 1
                    // 每10个联系人更新一次进度（在主线程上）
                    if count % 10 == 0 {
                        let progress = count
                        Task { @MainActor in
                            self.loadedContactsCount = progress
                        }
                    }
                }
                // 枚举完成后，确保最终计数被更新
                let total = count
                Task { @MainActor in
                    self.loadedContactsCount = total
                }
            } catch {
                fetchError = "读取通讯录失败: \(error.localizedDescription)"
            }

            return (fetched, fetchError)
        }.value

        if let error = result.error {
            errorMessage = error
            contacts = []
            healthReport = .empty
            isLoading = false
        } else {
            contacts = result.contacts
            // 先设置 isLoading 为 false，让用户看到联系人列表
            isLoading = false
            // 后台线程执行健康分析 + 预计算重复联系人缓存，避免阻塞 UI
            Task.detached {
                let report = HealthAnalyzer.analyze(result.contacts)
                // 预计算重复联系人缓存，避免用户点击时才执行慢速 Union-Find
                let groups = ContactDeduplicator.findDuplicates(in: result.contacts)
                let cached = groups.flatMap { $0.contacts }
                await MainActor.run {
                    self.healthReport = report
                    self.cachedDuplicateContacts = cached
                }
            }
        }
    }

    func refresh() async {
        await loadContacts()
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
