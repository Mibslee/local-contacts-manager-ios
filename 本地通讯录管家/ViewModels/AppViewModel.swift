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
            // 在主线程中执行健康分析
            Task {
                let report = HealthAnalyzer.analyze(result.contacts)
                healthReport = report
            }
        }
    }

    func refresh() async {
        await loadContacts()
    }

    func contactsForIssue(_ type: HealthReport.IssueType) -> [ContactItem] {
        switch type {
        case .nameNeedsStandardize, .nameNotSplit:
            return contacts.filter { needsNameFix($0) }
        case .phonePrefixInconsistent:
            return contacts.filter { c in
                let prefixes = Set(c.phoneNumbers.map { extractPhonePrefix($0.value) })
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
                    return !isValidChinesePhone(digits)
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
            // 延迟计算重复联系人，避免首次进入时卡顿
            let groups = ContactDeduplicator.findDuplicates(in: contacts)
            return groups.flatMap { $0.contacts }
        case .emptyContact:
            return contacts.filter { $0.isEmpty }
        }
    }

    private func extractPhonePrefix(_ phone: String) -> String {
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        if cleaned.hasPrefix("+86") { return "+86" }
        if cleaned.hasPrefix("86") && cleaned.count > 11 { return "86" }
        return "none"
    }

    private func needsNameFix(_ contact: ContactItem) -> Bool {
        if contact.familyName.count > 1 && contact.givenName.isEmpty { return true }
        if contact.givenName.count > 1 && contact.familyName.isEmpty { return true }
        if contact.familyName.isEmpty && contact.givenName.isEmpty && !contact.fullName.isEmpty { return true }
        return false
    }

    private func isValidChinesePhone(_ digits: String) -> Bool {
        if digits.isEmpty { return true }
        let clean = digits.hasPrefix("86") && digits.count > 11 ? String(digits.dropFirst(2)) : digits
        if clean.count == 11 && clean.hasPrefix("1") { return true }
        if clean.count >= 7 && clean.count <= 15 { return true }
        return false
    }
    
    func issueTitle(for type: HealthReport.IssueType) -> String {
        return type.rawValue
    }
}
