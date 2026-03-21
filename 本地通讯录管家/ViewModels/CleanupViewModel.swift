import Foundation
import SwiftUI
import Combine
import Contacts

@MainActor
class CleanupViewModel: ObservableObject {
    @Published var selectedOptions: Set<CleanupOption> = []
    @Published var mergeStrategy: MergeStrategy = .keepMoreInfo
    @Published var isProcessing = false
    @Published var processedContacts: [ContactItem] = []
    @Published var cleanupSummary: CleanupSummary?
    @Published var showResult = false
    @Published var duplicateGroups: [ContactDeduplicator.DuplicateGroup] = []
    @Published var hasBackup = false
    @Published var isWritingBack = false
    @Published var backupURL: URL?

    func runCleanup(on contacts: [ContactItem]) -> [ContactItem] {
        isProcessing = true
        let startTime = Date()
        var results: [CleanupResult] = []
        var currentContacts = contacts

        if selectedOptions.contains(.nameNormalization) {
            let affected = currentContacts.filter { needsNameCheck($0) }
            let before = affected.count
            currentContacts = ContactNormalizer.normalizeAll(currentContacts, normalizeName: true, normalizePhonePrefix: false, unifyPhoneLabel: false, unifyEmailLabel: false)
            let after = currentContacts.filter { needsNameCheck($0) }.count
            results.append(CleanupResult(option: .nameNormalization, beforeCount: before, afterCount: after, details: ["已标准化\(before - after)条姓名"], affectedContacts: affected))
        }

        if selectedOptions.contains(.phoneClean) {
            let affected = currentContacts.filter { c in
                c.phoneNumbers.contains { phone in
                    let digits = phone.value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    return !isValidPhone(digits) || digits != phone.value.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
                }
            }
            var cleaned = currentContacts
            for i in 0..<cleaned.count {
                cleaned[i].phoneNumbers = cleaned[i].phoneNumbers.compactMap { phone in
                    var p = phone
                    p.value = cleanPhoneNumber(phone.value)
                    if p.value.isEmpty { return nil }
                    return p
                }
            }
            results.append(CleanupResult(option: .phoneClean, beforeCount: affected.count, afterCount: 0, details: ["已清理\(affected.count)条异常手机号"], affectedContacts: affected))
            currentContacts = cleaned
        }

        if selectedOptions.contains(.phonePrefixUnify) {
            let affected = currentContacts.filter { c in
                let prefixes = Set(c.phoneNumbers.map { extractPhonePrefix($0.value) })
                return prefixes.count > 1
            }
            let before = affected.count
            currentContacts = ContactNormalizer.normalizeAll(currentContacts, normalizeName: false, normalizePhonePrefix: true, unifyPhoneLabel: false, unifyEmailLabel: false)
            let after = currentContacts.filter { c in
                let prefixes = Set(c.phoneNumbers.map { extractPhonePrefix($0.value) })
                return prefixes.count > 1
            }.count
            results.append(CleanupResult(option: .phonePrefixUnify, beforeCount: before, afterCount: after, details: ["已统一\(before - after)条手机号前缀"], affectedContacts: affected))
        }

        if selectedOptions.contains(.phoneLabelUnify) {
            let affected = currentContacts.filter { Set($0.phoneNumbers.map { $0.label }).count > 1 }
            let before = affected.count
            currentContacts = ContactNormalizer.normalizeAll(currentContacts, normalizeName: false, normalizePhonePrefix: false, unifyPhoneLabel: true, unifyEmailLabel: false)
            let after = currentContacts.filter { Set($0.phoneNumbers.map { $0.label }).count > 1 }.count
            results.append(CleanupResult(option: .phoneLabelUnify, beforeCount: before, afterCount: after, details: ["已统一\(before - after)条手机标签"], affectedContacts: affected))
        }

        if selectedOptions.contains(.emailLabelUnify) {
            let affected = currentContacts.filter { Set($0.emailAddresses.map { $0.label }).count > 1 }
            currentContacts = ContactNormalizer.normalizeAll(currentContacts, normalizeName: false, normalizePhonePrefix: false, unifyPhoneLabel: false, unifyEmailLabel: true)
            results.append(CleanupResult(option: .emailLabelUnify, beforeCount: affected.count, afterCount: 0, details: ["已统一\(affected.count)条邮箱标签"], affectedContacts: affected))
        }

        if selectedOptions.contains(.phoneDeduplicate) {
            let affected = currentContacts.filter { !ContactDeduplicator.findDuplicatePhonesInContact($0).isEmpty }
            var deduped = currentContacts
            for i in 0..<deduped.count {
                var seen: Set<String> = []
                var uniquePhones: [ContactItem.LabeledValue] = []
                for phone in deduped[i].phoneNumbers {
                    var normalized = phone.value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    if normalized.hasPrefix("86") && normalized.count > 11 {
                        normalized = String(normalized.dropFirst(2))
                    }
                    if !seen.contains(normalized) {
                        seen.insert(normalized)
                        uniquePhones.append(phone)
                    }
                }
                deduped[i].phoneNumbers = uniquePhones
            }
            let before = affected.flatMap { $0.phoneNumbers }.count
            let after = deduped.filter { affected.map(\.id).contains($0.id) }.flatMap { $0.phoneNumbers }.count
            results.append(CleanupResult(option: .phoneDeduplicate, beforeCount: before, afterCount: after, details: ["已去重\(before - after)个重复手机号"], affectedContacts: affected))
            currentContacts = deduped
        }

        if selectedOptions.contains(.emailDeduplicate) {
            let affected = currentContacts.filter { !ContactDeduplicator.findDuplicateEmailsInContact($0).isEmpty }
            var deduped = currentContacts
            for i in 0..<deduped.count {
                var seen: Set<String> = []
                var uniqueEmails: [ContactItem.LabeledValue] = []
                for email in deduped[i].emailAddresses {
                    let normalized = email.value.lowercased()
                    if !seen.contains(normalized) {
                        seen.insert(normalized)
                        uniqueEmails.append(email)
                    }
                }
                deduped[i].emailAddresses = uniqueEmails
            }
            results.append(CleanupResult(option: .emailDeduplicate, beforeCount: affected.count, afterCount: 0, details: ["已去重邮箱"], affectedContacts: affected))
            currentContacts = deduped
        }

        if selectedOptions.contains(.emailValidation) {
            let affected = currentContacts.filter { c in
                c.emailAddresses.contains { !ContactNormalizer.isValidEmail($0.value) }
            }
            results.append(CleanupResult(option: .emailValidation, beforeCount: affected.count, afterCount: affected.count, details: ["发现\(affected.count)个无效邮箱"], affectedContacts: affected))
        }

        if selectedOptions.contains(.contactDeduplicate) {
            let groups = ContactDeduplicator.findDuplicates(in: currentContacts)
            duplicateGroups = groups
            let affected = groups.flatMap { $0.contacts }
            let before = currentContacts.count
            var mergedIds: Set<String> = []
            var mergedContacts: [ContactItem] = []

            for group in groups {
                let merged = ContactDeduplicator.mergeContacts(group.contacts, strategy: mergeStrategy)
                mergedContacts.append(merged)
                for contact in group.contacts {
                    mergedIds.insert(contact.id)
                }
            }

            currentContacts = currentContacts.filter { !mergedIds.contains($0.id) } + mergedContacts
            let after = currentContacts.count
            results.append(CleanupResult(option: .contactDeduplicate, beforeCount: before, afterCount: after, details: ["已合并\(before - after)条重复记录"], affectedContacts: affected))
        }

        if selectedOptions.contains(.removeEmptyContacts) {
            let affected = currentContacts.filter { $0.isEmpty }
            let before = currentContacts.count
            currentContacts = currentContacts.filter { !$0.isEmpty }
            let after = currentContacts.count
            results.append(CleanupResult(option: .removeEmptyContacts, beforeCount: before, afterCount: after, details: ["已删除\(before - after)个空联系人"], affectedContacts: affected))
        }

        let endTime = Date()
        cleanupSummary = CleanupSummary(results: results, startTime: startTime, endTime: endTime)
        processedContacts = currentContacts
        isProcessing = false
        showResult = true

        return currentContacts
    }

    // MARK: - 备份

    func backupContacts(_ contacts: [ContactItem]) async -> Bool {
        let vcard = ContactExporter.exportToVCard(contacts)
        let fileName = "通讯录备份_\(Date().formatted(date: .abbreviated, time: .shortened)).vcf"
        let url = ContactExporter.saveToFile(content: vcard, fileName: fileName)

        if let url = url {
            backupURL = url
            hasBackup = true
            return true
        }
        return false
    }

    // MARK: - 写入（优化的删除+重建方案）

    func writeBackToSystemDirect() async -> (success: Int, failed: Int) {
        isWritingBack = true
        let contactsToWrite = processedContacts

        let store = CNContactStore()
        var successCount = 0
        var failedCount = 0

        // 先确保权限
        let authStatus = CNContactStore.authorizationStatus(for: .contacts)
        guard authStatus == .authorized else {
            isWritingBack = false
            return (0, contactsToWrite.count)
        }

        do {
            // 1. 读取所有现有联系人并删除（使用单个请求，在后台执行）
            var existingContacts: [CNContact] = []
            let fetchRequest = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
            
            try await Task.detached {
                try store.enumerateContacts(with: fetchRequest) { contact, _ in
                    existingContacts.append(contact)
                }
            }.value
            
            if !existingContacts.isEmpty {
                let deleteRequest = CNSaveRequest()
                for contact in existingContacts {
                    if let mutableContact = contact.mutableCopy() as? CNMutableContact {
                        deleteRequest.delete(mutableContact)
                    }
                }
                try store.execute(deleteRequest)
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            
            // 2. 创建新联系人（分批，每批20个）
            for batchStart in stride(from: 0, to: contactsToWrite.count, by: 20) {
                let batchEnd = min(batchStart + 20, contactsToWrite.count)
                let batch = Array(contactsToWrite[batchStart..<batchEnd])
                
                let createRequest = CNSaveRequest()
                for contact in batch {
                    let cnContact = CNMutableContact()
                    cnContact.familyName = contact.familyName
                    cnContact.givenName = contact.givenName
                    cnContact.organizationName = contact.organization
                    cnContact.departmentName = contact.department
                    
                    cnContact.phoneNumbers = contact.phoneNumbers.map { labeledValue in
                        CNLabeledValue(
                            label: CNLabelPhoneNumberMobile,
                            value: CNPhoneNumber(stringValue: labeledValue.value)
                        )
                    }
                    
                    cnContact.emailAddresses = contact.emailAddresses.map { labeledValue in
                        CNLabeledValue(
                            label: CNLabelHome,
                            value: labeledValue.value as NSString
                        )
                    }
                    
                    createRequest.add(cnContact, toContainerWithIdentifier: nil)
                }
                
                do {
                    try store.execute(createRequest)
                    successCount += batch.count
                } catch {
                    failedCount += batch.count
                }
                
                if batchEnd < contactsToWrite.count {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            
        } catch {
            failedCount = contactsToWrite.count - successCount
        }
        
        isWritingBack = false
        return (successCount, failedCount)
    }

    // MARK: - 恢复

    func restoreFromBackup() async -> Bool {
        guard let url = backupURL else { return false }
        guard let data = try? Data(contentsOf: url) else { return false }

        let importResult = ContactImporter.importFromVCard(data: data)
        guard !importResult.contacts.isEmpty else { return false }

        let result = await writeBackContacts(importResult.contacts)
        return result.success > 0
    }

    private func writeBackContacts(_ contacts: [ContactItem]) async -> (success: Int, failed: Int) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let store = CNContactStore()

                var existingIds: [String] = []
                try? store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])) { cnContact, _ in
                    existingIds.append(cnContact.identifier)
                }

                if !existingIds.isEmpty {
                    let deleteRequest = CNSaveRequest()
                    for id in existingIds {
                        if let contact = try? store.unifiedContact(withIdentifier: id, keysToFetch: []),
                           let mutable = contact.mutableCopy() as? CNMutableContact {
                            deleteRequest.delete(mutable)
                        }
                    }
                    _ = try? store.execute(deleteRequest)
                }

                var success = 0
                let createRequest = CNSaveRequest()
                for contact in contacts {
                    let cnContact = CNMutableContact()
                    cnContact.familyName = contact.familyName
                    cnContact.givenName = contact.givenName
                    cnContact.organizationName = contact.organization
                    cnContact.departmentName = contact.department
                    cnContact.phoneNumbers = contact.phoneNumbers.map {
                        CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0.value))
                    }
                    cnContact.emailAddresses = contact.emailAddresses.map {
                        CNLabeledValue(label: CNLabelHome, value: $0.value as NSString)
                    }
                    createRequest.add(cnContact, toContainerWithIdentifier: nil)
                    success += 1
                }
                _ = try? store.execute(createRequest)
                continuation.resume(returning: (success, 0))
            }
        }
    }

    private func extractPhonePrefix(_ phone: String) -> String {
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        if cleaned.hasPrefix("+86") { return "+86" }
        if cleaned.hasPrefix("86") && cleaned.count > 11 { return "86" }
        return "none"
    }

    private func needsNameCheck(_ contact: ContactItem) -> Bool {
        if contact.familyName.count > 1 && contact.givenName.isEmpty { return true }
        if contact.givenName.count > 1 && contact.familyName.isEmpty { return true }
        return false
    }

    private func isValidPhone(_ digits: String) -> Bool {
        if digits.isEmpty { return false }
        let clean = digits.hasPrefix("86") && digits.count > 11 ? String(digits.dropFirst(2)) : digits
        if clean.count == 11 && clean.hasPrefix("1") { return true }
        if clean.count >= 7 && clean.count <= 15 { return true }
        return false
    }

    private func cleanPhoneNumber(_ phone: String) -> String {
        // 只清理多余的空白字符，不做其他处理，避免字符数组问题
        let cleaned = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
}
