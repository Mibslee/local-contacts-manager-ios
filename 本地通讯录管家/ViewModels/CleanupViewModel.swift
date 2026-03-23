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
    @Published var writeBackProgress: Double = 0.0

    // 存储用户选择的联系人ID（用于排除特定联系人）
    var excludedContactIDs: Set<ContactItem.ID> = []
    
    private nonisolated func performCleanupInBackground(
        contacts: [ContactItem],
        options: Set<CleanupOption>,
        excludedIDs: Set<String>,
        strategy: MergeStrategy
    ) async -> ([ContactItem], [CleanupResult], [ContactDeduplicator.DuplicateGroup]) {
        await Task.detached {
            var currentContacts = contacts
            var results: [CleanupResult] = []
            var duplicateGroups: [ContactDeduplicator.DuplicateGroup] = []
            
            if options.contains(.nameNormalization) {
                let affected = currentContacts.filter { !excludedIDs.contains($0.id) && Self.needsNameCheck($0) }
                let before = affected.count
                
                for i in 0..<currentContacts.count {
                    if !excludedIDs.contains(currentContacts[i].id) {
                        currentContacts[i] = ContactNormalizer.normalizeName(for: currentContacts[i])
                    }
                    if i % 100 == 0 { await Task.yield() }
                }
                
                let after = currentContacts.filter { !excludedIDs.contains($0.id) && Self.needsNameCheck($0) }.count
                results.append(CleanupResult(option: .nameNormalization, beforeCount: before, afterCount: after, details: ["已标准化\(before - after)条姓名"], affectedContacts: affected))
            }

            if options.contains(.phoneClean) {
                let affected = currentContacts.filter { !excludedIDs.contains($0.id) && $0.phoneNumbers.contains { phone in
                    let digits = phone.value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    return !Self.isValidPhone(digits) || digits != phone.value.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
                }}

                var cleaned = currentContacts
                for i in 0..<cleaned.count {
                    if !excludedIDs.contains(cleaned[i].id) {
                        cleaned[i].phoneNumbers = cleaned[i].phoneNumbers.compactMap { phone in
                            var p = phone
                            p.value = Self.cleanPhoneNumber(phone.value)
                            if p.value.isEmpty { return nil }
                            return p
                        }
                    }
                    if i % 100 == 0 { await Task.yield() }
                }
                results.append(CleanupResult(option: .phoneClean, beforeCount: affected.count, afterCount: 0, details: ["已清理\(affected.count)条异常手机号"], affectedContacts: affected))
                currentContacts = cleaned
            }

            if options.contains(.phonePrefixUnify) {
                let affected = currentContacts.filter { contact in
                    !excludedIDs.contains(contact.id) && {
                        let prefixes = Set(contact.phoneNumbers.map { Self.extractPhonePrefix($0.value) })
                        return prefixes.count > 1
                    }()
                }

                let before = affected.count
                
                for i in 0..<currentContacts.count {
                    if !excludedIDs.contains(currentContacts[i].id) {
                        var contact = currentContacts[i]
                        contact.phoneNumbers = contact.phoneNumbers.map { phone in
                            var p = phone
                            p.value = ContactNormalizer.normalizePhoneNumber(p.value)
                            return p
                        }
                        currentContacts[i] = contact
                    }
                    if i % 100 == 0 { await Task.yield() }
                }
                
                let after = currentContacts.filter { contact in
                    !excludedIDs.contains(contact.id) && {
                        let prefixes = Set(contact.phoneNumbers.map { Self.extractPhonePrefix($0.value) })
                        return prefixes.count > 1
                    }()
                }.count
                results.append(CleanupResult(option: .phonePrefixUnify, beforeCount: before, afterCount: after, details: ["已统一\(before - after)条手机号前缀"], affectedContacts: affected))
            }

            if options.contains(.phoneLabelUnify) {
                let affected = currentContacts.filter { !excludedIDs.contains($0.id) && Set($0.phoneNumbers.map { $0.label }).count > 1 }
                let before = affected.count
                
                for i in 0..<currentContacts.count {
                    if !excludedIDs.contains(currentContacts[i].id) {
                        var contact = currentContacts[i]
                        contact.phoneNumbers = contact.phoneNumbers.map { phone in
                            var p = phone
                            p.label = ContactNormalizer.unifyPhoneLabel(p.label)
                            return p
                        }
                        currentContacts[i] = contact
                    }
                    if i % 100 == 0 { await Task.yield() }
                }
                
                let after = currentContacts.filter { !excludedIDs.contains($0.id) && Set($0.phoneNumbers.map { $0.label }).count > 1 }.count
                results.append(CleanupResult(option: .phoneLabelUnify, beforeCount: before, afterCount: after, details: ["已统一\(before - after)条手机标签"], affectedContacts: affected))
            }

            if options.contains(.emailLabelUnify) {
                let affected = currentContacts.filter { !excludedIDs.contains($0.id) && Set($0.emailAddresses.map { $0.label }).count > 1 }
                
                for i in 0..<currentContacts.count {
                    if !excludedIDs.contains(currentContacts[i].id) {
                        var contact = currentContacts[i]
                        contact.emailAddresses = contact.emailAddresses.map { email in
                            var e = email
                            e.label = ContactNormalizer.unifyEmailLabel(e.label)
                            return e
                        }
                        currentContacts[i] = contact
                    }
                    if i % 100 == 0 { await Task.yield() }
                }
                
                results.append(CleanupResult(option: .emailLabelUnify, beforeCount: affected.count, afterCount: 0, details: ["已统一\(affected.count)条邮箱标签"], affectedContacts: affected))
            }

            if options.contains(.phoneDeduplicate) {
                let affected = currentContacts.filter { !excludedIDs.contains($0.id) && !ContactDeduplicator.findDuplicatePhonesInContact($0).isEmpty }
                var deduped = currentContacts
                for i in 0..<deduped.count {
                    if !excludedIDs.contains(deduped[i].id) {
                        var seen: Set<String> = []
                        var uniquePhones: [ContactItem.LabeledValue] = []
                        for phone in deduped[i].phoneNumbers {
                            var normalized = phone.value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                            if normalized.hasPrefix("86") && normalized.count > 11 {
                                normalized = String(normalized.dropFirst(2))
                            }
                            if !seen.contains(normalized) {
                                seen.insert(normalized)
                                var processedPhone = phone
                                processedPhone.value = ContactNormalizer.normalizePhoneNumber(phone.value)
                                uniquePhones.append(processedPhone)
                            }
                        }
                        deduped[i].phoneNumbers = uniquePhones
                    }
                    if i % 100 == 0 { await Task.yield() }
                }
                let affectedIds = Set(affected.map(\.id))
                let before = affected.flatMap { $0.phoneNumbers }.count
                let after = deduped.filter { !excludedIDs.contains($0.id) && affectedIds.contains($0.id) }.flatMap { $0.phoneNumbers }.count
                results.append(CleanupResult(option: .phoneDeduplicate, beforeCount: before, afterCount: after, details: ["已去重\(before - after)个重复手机号"], affectedContacts: affected))
                currentContacts = deduped
            }

            if options.contains(.emailDeduplicate) {
                let affected = currentContacts.filter { !excludedIDs.contains($0.id) && !ContactDeduplicator.findDuplicateEmailsInContact($0).isEmpty }
                var deduped = currentContacts
                for i in 0..<deduped.count {
                    if !excludedIDs.contains(deduped[i].id) {
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
                    if i % 100 == 0 { await Task.yield() }
                }
                results.append(CleanupResult(option: .emailDeduplicate, beforeCount: affected.count, afterCount: 0, details: ["已去重邮箱"], affectedContacts: affected))
                currentContacts = deduped
            }

            if options.contains(.emailValidation) {
                let affected = currentContacts.filter { !excludedIDs.contains($0.id) && $0.emailAddresses.contains { !ContactNormalizer.isValidEmail($0.value) } }
                results.append(CleanupResult(option: .emailValidation, beforeCount: affected.count, afterCount: affected.count, details: ["发现\(affected.count)个无效邮箱"], affectedContacts: affected))
            }

            if options.contains(.contactDeduplicate) {
                let eligibleContacts = currentContacts.filter { !excludedIDs.contains($0.id) }
                let groups = ContactDeduplicator.findDuplicates(in: eligibleContacts)
                duplicateGroups = groups
                let affected = groups.flatMap { $0.contacts }
                let before = currentContacts.count
                var mergedIds: Set<String> = []
                var mergedContacts: [ContactItem] = []

                for group in groups {
                    let merged = ContactDeduplicator.mergeContacts(group.contacts, strategy: strategy)
                    mergedContacts.append(merged)
                    for contact in group.contacts {
                        mergedIds.insert(contact.id)
                    }
                }

                currentContacts = currentContacts.filter { !mergedIds.contains($0.id) } + mergedContacts
                let after = currentContacts.count
                results.append(CleanupResult(option: .contactDeduplicate, beforeCount: before, afterCount: after, details: ["已合并\(before - after)条重复记录"], affectedContacts: affected))
            }

            if options.contains(.removeEmptyContacts) {
                let affected = currentContacts.filter { !excludedIDs.contains($0.id) && $0.isEmpty }
                let before = currentContacts.count
                currentContacts = currentContacts.filter { excludedIDs.contains($0.id) || !$0.isEmpty }
                let after = currentContacts.count
                results.append(CleanupResult(option: .removeEmptyContacts, beforeCount: before, afterCount: after, details: ["已删除\(before - after)个空联系人"], affectedContacts: affected))
            }

            return (currentContacts, results, duplicateGroups)
        }.value
    }

    func runCleanup(on contacts: [ContactItem]) async -> [ContactItem] {
        isProcessing = true
        let startTime = Date()
        
        // 在后台线程执行清理操作
        let (processedContacts, results, duplicateGroups) = await performCleanupInBackground(
            contacts: contacts,
            options: selectedOptions,
            excludedIDs: excludedContactIDs,
            strategy: mergeStrategy
        )
        
        let endTime = Date()
        
        // 更新UI状态
        self.cleanupSummary = CleanupSummary(results: results, startTime: startTime, endTime: endTime)
        self.processedContacts = processedContacts
        self.duplicateGroups = duplicateGroups
        self.isProcessing = false
        self.showResult = true

        return processedContacts
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
        guard !processedContacts.isEmpty else {
            isWritingBack = false
            writeBackProgress = 0.0
            return (0, 0)
        }
        
        isWritingBack = true
        writeBackProgress = 0.0
        let contactsToWrite = processedContacts

        var successCount = 0
        var failedCount = 0

        let authStatus = CNContactStore.authorizationStatus(for: .contacts)
        guard authStatus == .authorized else {
            isWritingBack = false
            writeBackProgress = 0.0
            return (0, contactsToWrite.count)
        }

        do {
            let backupSuccess = await backupContacts(processedContacts)
            print("备份结果: \(backupSuccess)")
            
            let store = CNContactStore()
            let maxDeleteAttempts = 3
            
            for attempt in 1...maxDeleteAttempts {
                var existingContactIDs: [String] = []
                let fetchRequest = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
                
                try await Task.detached {
                    try store.enumerateContacts(with: fetchRequest) { contact, _ in
                        existingContactIDs.append(contact.identifier)
                    }
                }.value
                
                if existingContactIDs.isEmpty {
                    print("删除尝试 \(attempt): 没有剩余联系人")
                    break
                }
                
                print("删除尝试 \(attempt): 开始删除 \(existingContactIDs.count) 个联系人")
                
                for batchStart in stride(from: 0, to: existingContactIDs.count, by: 50) {
                    let batchEnd = min(batchStart + 50, existingContactIDs.count)
                    let batchIDs = Array(existingContactIDs[batchStart..<batchEnd])
                    
                    try await Task.detached {
                        let deleteStore = CNContactStore()
                        let deleteRequest = CNSaveRequest()
                        
                        let predicate = CNContact.predicateForContacts(withIdentifiers: batchIDs)
                        let keysToFetch = [CNContactIdentifierKey as CNKeyDescriptor]
                        do {
                            let contacts = try deleteStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
                            for contact in contacts {
                                if let mutableContact = contact.mutableCopy() as? CNMutableContact {
                                    deleteRequest.delete(mutableContact)
                                }
                            }
                        } catch {
                            print("获取联系人失败: \(error)")
                        }
                        
                        try deleteStore.execute(deleteRequest)
                    }.value
                    
                    let deleteProgress = Double(batchEnd) / Double(existingContactIDs.count) * 0.5
                    await MainActor.run {
                        self.writeBackProgress = deleteProgress
                    }
                    
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                
                var remainingCount = 0
                try await Task.detached {
                    try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])) { _, _ in
                        remainingCount += 1
                    }
                }.value
                
                if remainingCount == 0 {
                    print("删除尝试 \(attempt): 成功删除所有联系人")
                    break
                } else {
                    print("删除尝试 \(attempt): 仍有 \(remainingCount) 个联系人未删除")
                    if attempt == maxDeleteAttempts {
                        print("警告: 经过 \(maxDeleteAttempts) 次尝试，仍有联系人未删除")
                    }
                }
            }
            
            print("删除完成，开始添加新联系人，共 \(contactsToWrite.count) 个")
            
            let totalContacts = contactsToWrite.count
            var processedCount = 0
            let batchSize = 50
            
            for batchStart in stride(from: 0, to: contactsToWrite.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, contactsToWrite.count)
                let batch = Array(contactsToWrite[batchStart..<batchEnd])
                
                try await Task.detached {
                    let addStore = CNContactStore()
                    let saveRequest = CNSaveRequest()
                    
                    for contact in batch {
                        let cnContact = CNMutableContact()
                        
                        cnContact.familyName = contact.familyName
                        cnContact.givenName = contact.givenName
                        cnContact.organizationName = contact.organization
                        cnContact.departmentName = contact.department
                        
                        cnContact.phoneNumbers = contact.phoneNumbers.map { labeledValue in
                            let systemLabel = Self.convertToSystemPhoneLabel(labeledValue.label)
                            return CNLabeledValue(
                                label: systemLabel,
                                value: CNPhoneNumber(stringValue: labeledValue.value)
                            )
                        }
                        
                        cnContact.emailAddresses = contact.emailAddresses.map { labeledValue in
                            let systemLabel = Self.convertToSystemEmailLabel(labeledValue.label)
                            return CNLabeledValue(
                                label: systemLabel,
                                value: labeledValue.value as NSString
                            )
                        }
                        
                        saveRequest.add(cnContact, toContainerWithIdentifier: nil)
                    }
                    
                    try addStore.execute(saveRequest)
                }.value
                
                processedCount += batch.count
                let addProgress = Double(processedCount) / Double(totalContacts) * 0.5 + 0.5
                await MainActor.run {
                    self.writeBackProgress = addProgress
                }
                
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            
            successCount = contactsToWrite.count
            print("写入完成，成功写入 \(successCount) 个联系人")
            
        } catch {
            print("写入失败: \(error)")
            failedCount = contactsToWrite.count - successCount
        }
        
        await MainActor.run {
            self.writeBackProgress = 1.0
            self.isWritingBack = false
        }
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
                    cnContact.phoneNumbers = contact.phoneNumbers.map { labeledValue in
                        let systemLabel = Self.convertToSystemPhoneLabel(labeledValue.label)
                        return CNLabeledValue(label: systemLabel, value: CNPhoneNumber(stringValue: labeledValue.value))
                    }
                    cnContact.emailAddresses = contact.emailAddresses.map { labeledValue in
                        let systemLabel = Self.convertToSystemEmailLabel(labeledValue.label)
                        return CNLabeledValue(label: systemLabel, value: labeledValue.value as NSString)
                    }
                    createRequest.add(cnContact, toContainerWithIdentifier: nil)
                    success += 1
                }
                _ = try? store.execute(createRequest)
                continuation.resume(returning: (success, 0))
            }
        }
    }
    
    // MARK: - 静态辅助方法
    
    private nonisolated static func needsNameCheck(_ contact: ContactItem) -> Bool {
        if contact.familyName.count > 1 && contact.givenName.isEmpty { return true }
        if contact.givenName.count > 1 && contact.familyName.isEmpty { return true }
        return false
    }

    private nonisolated static func isValidPhone(_ digits: String) -> Bool {
        if digits.isEmpty { return false }
        let clean = digits.hasPrefix("86") && digits.count > 11 ? String(digits.dropFirst(2)) : digits
        if clean.count == 11 && clean.hasPrefix("1") { return true }
        if clean.count >= 7 && clean.count <= 15 { return true }
        return false
    }

    private nonisolated static func cleanPhoneNumber(_ phone: String) -> String {
        let cleaned = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
    
    private nonisolated static func convertToSystemPhoneLabel(_ label: String) -> String {
        let lower = label.lowercased()
        if lower.contains("手机") || lower.contains("mobile") || lower == "mp" || lower == "tel" || lower.contains("phone") || lower.isEmpty {
            return CNLabelPhoneNumberMobile
        }
        if lower.contains("iPhone") || lower.contains("苹果") {
            return CNLabelWork
        }
        if lower.contains("工作") || lower.contains("work") {
            return CNLabelWork
        }
        if lower.contains("home") || lower.contains("家庭") {
            return CNLabelHome
        }
        if lower.contains("main") || lower.contains("主要") {
            return CNLabelPhoneNumberMain
        }
        return CNLabelOther
    }
    
    private nonisolated static func convertToSystemEmailLabel(_ label: String) -> String {
        let lower = label.lowercased()
        if lower.contains("邮箱") || lower.contains("email") || lower.contains("邮件") || lower.isEmpty {
            return CNLabelHome
        }
        if lower.contains("工作") || lower.contains("work") {
            return CNLabelWork
        }
        return CNLabelOther
    }
    
    private nonisolated static func extractPhonePrefix(_ phone: String) -> String {
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        if cleaned.hasPrefix("+86") { return "+86" }
        if cleaned.hasPrefix("86") && cleaned.count > 11 { return "86" }
        return "none"
    }
}
