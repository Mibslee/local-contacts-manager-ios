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
    /// 已写入完成的 processedContacts 标识，避免重复写入造成翻倍
    private var lastWrittenSignature: Int?

    // 存储用户选择的联系人ID（用于排除特定联系人）
    var excludedContactIDs: Set<ContactItem.ID> = []
    
    private nonisolated func performCleanupInBackground(
        contacts: [ContactItem],
        options: Set<CleanupOption>,
        excludedIDs: Set<String>,
        strategy: MergeStrategy
    ) async -> ([ContactItem], [CleanupResult], [ContactDeduplicator.DuplicateGroup]) {
        await Task.detached {
            var results: [CleanupResult] = []
            var duplicateGroups: [ContactDeduplicator.DuplicateGroup] = []

            // 需要全局操作的选项（无法在单次遍历中完成）
            let needsContactDedup = options.contains(.contactDeduplicate)
            let needsRemoveEmpty = options.contains(.removeEmptyContacts)

            // 单次遍历：处理所有逐联系人操作
            var currentContacts = contacts
            var nameNormAffected: [ContactItem] = []
            var nameNormBefore = 0
            var phoneCleanAffected: [ContactItem] = []
            var phonePrefixAffected: [ContactItem] = []
            var phonePrefixBefore = 0
            var phonePrefixAfter = 0
            var phoneLabelAffected: [ContactItem] = []
            var phoneLabelBefore = 0
            var phoneLabelAfter = 0
            var emailLabelAffected: [ContactItem] = []
            var phoneDedupAffected: [ContactItem] = []
            var phoneDedupPhonesBefore = 0
            var phoneDedupPhonesAfter = 0
            var emailDedupAffected: [ContactItem] = []
            var emailInvalidAffected: [ContactItem] = []
            var emptyAffected: [ContactItem] = []

            for i in 0..<currentContacts.count {
                guard !excludedIDs.contains(currentContacts[i].id) else {
                    if i % 100 == 0 { await Task.yield() }
                    continue
                }
                var contact = currentContacts[i]

                // 姓名标准化
                if options.contains(.nameNormalization) {
                    let needsFix = ContactValidator.needsNameCheck(contact)
                    if needsFix {
                        nameNormBefore += 1
                        nameNormAffected.append(contact)
                        contact = ContactNormalizer.normalizeName(for: contact)
                    }
                }

                // 电话清理
                if options.contains(.phoneClean) {
                    let hasInvalid = contact.phoneNumbers.contains { phone in
                        let digits = phone.value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                        return !ContactValidator.isValidPhone(digits)
                    }
                    if hasInvalid {
                        phoneCleanAffected.append(contact)
                        contact.phoneNumbers = contact.phoneNumbers.compactMap { phone in
                            var p = phone
                            p.value = ContactValidator.cleanPhoneNumber(phone.value)
                            if p.value.isEmpty { return nil }
                            return p
                        }
                    }
                }

                // 手机号前缀统一
                if options.contains(.phonePrefixUnify) {
                    let prefixes = Set(contact.phoneNumbers.map { ContactValidator.extractPhonePrefix($0.value) })
                    if prefixes.count > 1 {
                        phonePrefixBefore += 1
                        phonePrefixAffected.append(contact)
                        contact.phoneNumbers = contact.phoneNumbers.map { phone in
                            var p = phone
                            p.value = ContactNormalizer.normalizePhoneNumber(p.value)
                            return p
                        }
                        let afterPrefixes = Set(contact.phoneNumbers.map { ContactValidator.extractPhonePrefix($0.value) })
                        if afterPrefixes.count <= 1 { phonePrefixAfter += 1 }
                    }
                }

                // 手机号标签统一
                if options.contains(.phoneLabelUnify) {
                    let labels = Set(contact.phoneNumbers.map { $0.label })
                    if labels.count > 1 {
                        phoneLabelBefore += 1
                        phoneLabelAffected.append(contact)
                        contact.phoneNumbers = contact.phoneNumbers.map { phone in
                            var p = phone
                            p.label = ContactNormalizer.unifyPhoneLabel(p.label)
                            return p
                        }
                        let afterLabels = Set(contact.phoneNumbers.map { $0.label })
                        if afterLabels.count <= 1 { phoneLabelAfter += 1 }
                    }
                }

                // 邮箱标签统一
                if options.contains(.emailLabelUnify) {
                    let labels = Set(contact.emailAddresses.map { $0.label })
                    if labels.count > 1 {
                        emailLabelAffected.append(contact)
                        contact.emailAddresses = contact.emailAddresses.map { email in
                            var e = email
                            e.label = ContactNormalizer.unifyEmailLabel(e.label)
                            return e
                        }
                    }
                }

                // 手机号去重
                if options.contains(.phoneDeduplicate) {
                    let dups = ContactDeduplicator.findDuplicatePhonesInContact(contact)
                    if !dups.isEmpty {
                        phoneDedupAffected.append(contact)
                        phoneDedupPhonesBefore += contact.phoneNumbers.count
                        var seen: Set<String> = []
                        var uniquePhones: [ContactItem.LabeledValue] = []
                        for phone in contact.phoneNumbers {
                            let normalized = phone.value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                            let finalNorm = normalized.hasPrefix("86") && normalized.count > 11 ? String(normalized.dropFirst(2)) : normalized
                            if !seen.contains(finalNorm) {
                                seen.insert(finalNorm)
                                var processedPhone = phone
                                processedPhone.value = ContactNormalizer.normalizePhoneNumber(phone.value)
                                uniquePhones.append(processedPhone)
                            }
                        }
                        contact.phoneNumbers = uniquePhones
                        phoneDedupPhonesAfter += uniquePhones.count
                    }
                }

                // 邮箱去重
                if options.contains(.emailDeduplicate) {
                    let dups = ContactDeduplicator.findDuplicateEmailsInContact(contact)
                    if !dups.isEmpty {
                        emailDedupAffected.append(contact)
                        var seen: Set<String> = []
                        var uniqueEmails: [ContactItem.LabeledValue] = []
                        for email in contact.emailAddresses {
                            let normalized = email.value.lowercased()
                            if !seen.contains(normalized) {
                                seen.insert(normalized)
                                uniqueEmails.append(email)
                            }
                        }
                        contact.emailAddresses = uniqueEmails
                    }
                }

                // 邮箱校验（只读）
                if options.contains(.emailValidation) {
                    if contact.emailAddresses.contains(where: { !ContactNormalizer.isValidEmail($0.value) }) {
                        emailInvalidAffected.append(contact)
                    }
                }

                // 空联系人
                if needsRemoveEmpty && contact.isEmpty {
                    emptyAffected.append(contact)
                }

                currentContacts[i] = contact
                if i % 100 == 0 { await Task.yield() }
            }

            // 生成单次遍历的结果
            if options.contains(.nameNormalization) {
                let after = currentContacts.filter { !excludedIDs.contains($0.id) && ContactValidator.needsNameCheck($0) }.count
                results.append(CleanupResult(option: .nameNormalization, beforeCount: nameNormBefore, afterCount: after, details: ["已标准化\(nameNormBefore - after)条姓名"], affectedContacts: nameNormAffected))
            }
            if options.contains(.phoneClean) {
                results.append(CleanupResult(option: .phoneClean, beforeCount: phoneCleanAffected.count, afterCount: 0, details: ["已清理\(phoneCleanAffected.count)条异常手机号"], affectedContacts: phoneCleanAffected))
            }
            if options.contains(.phonePrefixUnify) {
                results.append(CleanupResult(option: .phonePrefixUnify, beforeCount: phonePrefixBefore, afterCount: phonePrefixAfter, details: ["已统一\(phonePrefixBefore - phonePrefixAfter)条手机号前缀"], affectedContacts: phonePrefixAffected))
            }
            if options.contains(.phoneLabelUnify) {
                results.append(CleanupResult(option: .phoneLabelUnify, beforeCount: phoneLabelBefore, afterCount: phoneLabelAfter, details: ["已统一\(phoneLabelBefore - phoneLabelAfter)条手机标签"], affectedContacts: phoneLabelAffected))
            }
            if options.contains(.emailLabelUnify) {
                results.append(CleanupResult(option: .emailLabelUnify, beforeCount: emailLabelAffected.count, afterCount: 0, details: ["已统一\(emailLabelAffected.count)条邮箱标签"], affectedContacts: emailLabelAffected))
            }
            if options.contains(.phoneDeduplicate) {
                results.append(CleanupResult(option: .phoneDeduplicate, beforeCount: phoneDedupPhonesBefore, afterCount: phoneDedupPhonesAfter, details: ["已去重\(phoneDedupPhonesBefore - phoneDedupPhonesAfter)个重复手机号"], affectedContacts: phoneDedupAffected))
            }
            if options.contains(.emailDeduplicate) {
                results.append(CleanupResult(option: .emailDeduplicate, beforeCount: emailDedupAffected.count, afterCount: 0, details: ["已去重邮箱"], affectedContacts: emailDedupAffected))
            }
            if options.contains(.emailValidation) {
                results.append(CleanupResult(option: .emailValidation, beforeCount: emailInvalidAffected.count, afterCount: emailInvalidAffected.count, details: ["发现\(emailInvalidAffected.count)个无效邮箱"], affectedContacts: emailInvalidAffected))
            }

            // 联系人去重（全局操作，无法单次遍历）
            if needsContactDedup {
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
                    for contact in group.contacts { mergedIds.insert(contact.id) }
                }
                currentContacts = currentContacts.filter { !mergedIds.contains($0.id) } + mergedContacts
                let after = currentContacts.count
                results.append(CleanupResult(option: .contactDeduplicate, beforeCount: before, afterCount: after, details: ["已合并\(before - after)条重复记录"], affectedContacts: affected))
            }

            // 删除空联系人
            if needsRemoveEmpty {
                let before = currentContacts.count
                currentContacts = currentContacts.filter { excludedIDs.contains($0.id) || !$0.isEmpty }
                let after = currentContacts.count
                results.append(CleanupResult(option: .removeEmptyContacts, beforeCount: before, afterCount: after, details: ["已删除\(before - after)个空联系人"], affectedContacts: emptyAffected))
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
        // 新一轮整理结果，重置写入幂等标记
        self.lastWrittenSignature = nil

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
        // 重入保护：已经在写入或同一批已写入过，直接返回，避免翻倍
        if isWritingBack { return (0, 0) }
        let signature = Self.signature(for: processedContacts)
        if let last = lastWrittenSignature, last == signature {
            print("跳过重复写入：当前结果已写入过")
            return (processedContacts.count, 0)
        }

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

        let backupSuccess = await backupContacts(processedContacts)
        print("备份结果: \(backupSuccess)")

        // 在后台线程一次性完成 删除 + 添加，避免主线程卡顿
        let result: (Int, Int) = await Task.detached { [weak self] in
            let store = CNContactStore()
            var added = 0
            var failed = 0

            // 1) 单次枚举所有现有联系人 ID
            var existingIDs: [String] = []
            do {
                let req = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
                req.unifyResults = true
                try store.enumerateContacts(with: req) { c, _ in
                    existingIDs.append(c.identifier)
                }
            } catch {
                print("枚举联系人失败: \(error)")
            }

            // 2) 批量删除（每批 200，单事务，无 sleep）
            let deleteBatch = 200
            let totalDelete = existingIDs.count
            var deletedSoFar = 0
            if totalDelete > 0 {
                for start in stride(from: 0, to: totalDelete, by: deleteBatch) {
                    let end = min(start + deleteBatch, totalDelete)
                    let ids = Array(existingIDs[start..<end])
                    let predicate = CNContact.predicateForContacts(withIdentifiers: ids)
                    let saveReq = CNSaveRequest()
                    do {
                        let cs = try store.unifiedContacts(matching: predicate, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
                        for c in cs {
                            if let m = c.mutableCopy() as? CNMutableContact {
                                saveReq.delete(m)
                            }
                        }
                        try store.execute(saveReq)
                    } catch {
                        print("删除批次失败: \(error)")
                    }
                    deletedSoFar = end
                    let p = Double(deletedSoFar) / Double(totalDelete) * 0.5
                    await MainActor.run { self?.writeBackProgress = p }
                }
            } else {
                await MainActor.run { self?.writeBackProgress = 0.5 }
            }

            // 3) 批量添加（每批 200，单事务，无 sleep）
            let addBatch = 200
            let total = contactsToWrite.count
            for start in stride(from: 0, to: total, by: addBatch) {
                let end = min(start + addBatch, total)
                let batch = contactsToWrite[start..<end]
                let saveReq = CNSaveRequest()
                for contact in batch {
                    let cn = CNMutableContact()
                    cn.familyName = contact.familyName
                    cn.givenName = contact.givenName
                    cn.organizationName = contact.organization
                    cn.departmentName = contact.department
                    cn.note = contact.note
                    if let bd = contact.birthday { cn.birthday = bd }
                    cn.phoneNumbers = contact.phoneNumbers.map { lv in
                        CNLabeledValue(label: Self.convertToSystemPhoneLabel(lv.label),
                                       value: CNPhoneNumber(stringValue: lv.value))
                    }
                    cn.emailAddresses = contact.emailAddresses.map { lv in
                        CNLabeledValue(label: Self.convertToSystemEmailLabel(lv.label),
                                       value: lv.value as NSString)
                    }
                    saveReq.add(cn, toContainerWithIdentifier: nil)
                }
                do {
                    try store.execute(saveReq)
                    added += (end - start)
                } catch {
                    print("添加批次失败: \(error)")
                    failed += (end - start)
                }
                let p = 0.5 + Double(end) / Double(total) * 0.5
                await MainActor.run { self?.writeBackProgress = p }
            }
            return (added, failed)
        }.value

        successCount = result.0
        failedCount = result.1

        await MainActor.run {
            self.writeBackProgress = 1.0
            self.isWritingBack = false
            if failedCount == 0 {
                self.lastWrittenSignature = signature
            }
        }
        print("写入完成: 成功 \(successCount), 失败 \(failedCount)")
        return (successCount, failedCount)
    }

    /// 计算 processedContacts 的稳定签名，用于幂等检查
    private static func signature(for contacts: [ContactItem]) -> Int {
        var hasher = Hasher()
        hasher.combine(contacts.count)
        for c in contacts {
            hasher.combine(c.familyName)
            hasher.combine(c.givenName)
            hasher.combine(c.phoneNumbers.map { $0.value }.joined(separator: ","))
            hasher.combine(c.emailAddresses.map { $0.value }.joined(separator: ","))
        }
        return hasher.finalize()
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
        ContactValidator.needsNameCheck(contact)
    }

    private nonisolated static func isValidPhone(_ digits: String) -> Bool {
        ContactValidator.isValidPhone(digits)
    }

    private nonisolated static func cleanPhoneNumber(_ phone: String) -> String {
        ContactValidator.cleanPhoneNumber(phone)
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
    
}
