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

    /// 是否有待写入的修改（用于统一写入模式）
    @Published var hasPendingChanges: Bool = false
    /// 待写入的修改计数
    @Published var pendingChangesCount: Int = 0
    /// preExecute 时用户选中的联系人 ID（用于限制写入范围）
    var selectedContactIDsAtPreExecute: Set<ContactItem.ID> = []
    /// 已写入完成的 processedContacts 标识，避免重复写入造成翻倍
    private var lastWrittenSignature: Int?

    // 存储用户选择的联系人ID（用于排除特定联系人）
    var excludedContactIDs: Set<ContactItem.ID> = []

    /// 去重时合并的原始联系人ID集合（用于写入时删除重复的系统联系人）
    var mergedOriginalIds: Set<String> = []
    /// 实际被清理操作修改过的联系人（用于精确写入）
    var affectedContacts: [ContactItem] = []
    
    private nonisolated func performCleanupInBackground(
        contacts: [ContactItem],
        options: Set<CleanupOption>,
        excludedIDs: Set<String>,
        strategy: MergeStrategy
    ) async -> ([ContactItem], [CleanupResult], [ContactDeduplicator.DuplicateGroup], Set<String>) {
        await Task.detached {
            var results: [CleanupResult] = []
            var duplicateGroups: [ContactDeduplicator.DuplicateGroup] = []
            var mergedOriginalIds: Set<String> = []

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

            var processedCount = 0
            for i in 0..<currentContacts.count {
                guard !excludedIDs.contains(currentContacts[i].id) else {
                    if i % 100 == 0 { await Task.yield() }
                    continue
                }
                processedCount += 1
                var contact = currentContacts[i]

                // 姓名标准化
                if options.contains(.nameNormalization) {
                    let needsFix = ContactValidator.needsNameCheck(contact)
                    if needsFix {
                        nameNormBefore += 1
                        nameNormAffected.append(contact)  // 追加原始副本（会在下面更新为转换后的版本）
                        contact = ContactNormalizer.normalizeName(for: contact)
                        // 更新 affected 记录中的联系人（因为上面追加的是转换前的副本）
                        nameNormAffected[nameNormAffected.count - 1] = contact
                    }
                }

                // 电话清理
                if options.contains(.phoneClean) {
                    let hasInvalid = contact.phoneNumbers.contains { phone in
                        let digits = phone.value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                        return !ContactValidator.isValidPhone(digits)
                    }
                    if hasInvalid {
                        phoneCleanAffected.append(contact)  // 追加原始副本（会在下面更新为转换后的版本）
                        contact.phoneNumbers = contact.phoneNumbers.compactMap { phone in
                            var p = phone
                            p.value = ContactValidator.cleanPhoneNumber(phone.value)
                            if p.value.isEmpty { return nil }
                            return p
                        }
                        // 更新 affected 记录中的联系人（因为上面追加的是转换前的副本）
                        phoneCleanAffected[phoneCleanAffected.count - 1] = contact
                    }
                }

                // 手机号前缀统一
                if options.contains(.phonePrefixUnify) {
                    let prefixes = Set(contact.phoneNumbers.map { ContactValidator.extractPhonePrefix($0.value) })
                    if prefixes.count > 1 {
                        phonePrefixBefore += 1
                        phonePrefixAffected.append(contact)  // 追加原始副本（会在下面更新为转换后的版本）
                        contact.phoneNumbers = contact.phoneNumbers.map { phone in
                            var p = phone
                            p.value = ContactNormalizer.normalizePhoneNumber(p.value)
                            return p
                        }
                        // 更新 affected 记录中的联系人（因为上面追加的是转换前的副本）
                        phonePrefixAffected[phonePrefixAffected.count - 1] = contact
                        let afterPrefixes = Set(contact.phoneNumbers.map { ContactValidator.extractPhonePrefix($0.value) })
                        if afterPrefixes.count <= 1 { phonePrefixAfter += 1 }
                    }
                }

                // 手机号标签统一
                if options.contains(.phoneLabelUnify) {
                    let labels = Set(contact.phoneNumbers.map { $0.label })
                    print("[Cleanup] 标签统一: \(contact.fullName), 原始标签=\(labels)")
                    if labels.count > 1 {
                        phoneLabelBefore += 1
                        phoneLabelAffected.append(contact)  // 追加原始副本（会在下面更新为转换后的版本）
                        contact.phoneNumbers = contact.phoneNumbers.map { phone in
                            var p = phone
                            let oldLabel = p.label
                            p.label = ContactNormalizer.unifyPhoneLabel(p.label)
                            print("[Cleanup] 标签转换: \(oldLabel) → \(p.label)")
                            return p
                        }
                        // 更新 affected 记录中的联系人（因为上面追加的是转换前的副本）
                        phoneLabelAffected[phoneLabelAffected.count - 1] = contact
                        let afterLabels = Set(contact.phoneNumbers.map { $0.label })
                        print("[Cleanup] 标签统一后: \(contact.fullName), 新标签=\(afterLabels)")
                        if afterLabels.count <= 1 { phoneLabelAfter += 1 }
                    }
                }

                // 邮箱标签统一
                if options.contains(.emailLabelUnify) {
                    let labels = Set(contact.emailAddresses.map { $0.label })
                    if labels.count > 1 {
                        emailLabelAffected.append(contact)  // 追加原始副本（会在下面更新为转换后的版本）
                        contact.emailAddresses = contact.emailAddresses.map { email in
                            var e = email
                            e.label = ContactNormalizer.unifyEmailLabel(e.label)
                            return e
                        }
                        // 更新 affected 记录中的联系人（因为上面追加的是转换前的副本）
                        emailLabelAffected[emailLabelAffected.count - 1] = contact
                    }
                }

                // 手机号去重
                if options.contains(.phoneDeduplicate) {
                    let dups = ContactDeduplicator.findDuplicatePhonesInContact(contact)
                    if !dups.isEmpty {
                        phoneDedupAffected.append(contact)  // 追加原始副本（会在下面更新为转换后的版本）
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
                        let beforeCount = contact.phoneNumbers.count
                        contact.phoneNumbers = uniquePhones
                        // 更新 affected 记录中的联系人（因为上面追加的是转换前的副本）
                        phoneDedupAffected[phoneDedupAffected.count - 1] = contact
                        phoneDedupPhonesAfter += uniquePhones.count
                        print("[Cleanup] 手机号去重 \(contact.fullName): 前\(beforeCount)个 → 后\(uniquePhones.count)个, 重复:\(dups)")
                    }
                }

                // 邮箱去重
                if options.contains(.emailDeduplicate) {
                    let dups = ContactDeduplicator.findDuplicateEmailsInContact(contact)
                    if !dups.isEmpty {
                        emailDedupAffected.append(contact)  // 追加原始副本（会在下面更新为转换后的版本）
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
                        // 更新 affected 记录中的联系人（因为上面追加的是转换前的副本）
                        emailDedupAffected[emailDedupAffected.count - 1] = contact
                    }
                }

                // 邮箱校验（实际删除无效邮箱）
                if options.contains(.emailValidation) {
                    let beforeCount = contact.emailAddresses.count
                    contact.emailAddresses = contact.emailAddresses.filter {
                        ContactNormalizer.isValidEmail($0.value)
                    }
                    if contact.emailAddresses.count < beforeCount {
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

            print("[Cleanup] 遍历完成: 总计 \(currentContacts.count), 实际处理 \(processedCount), 排除 \(excludedIDs.count)")

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
                // 记录合并的原始ID（第一个保留，其余需要删除）
                for group in groups {
                    if group.contacts.count > 1 {
                        for contact in group.contacts.dropFirst() {
                            mergedOriginalIds.insert(contact.id)
                        }
                    }
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

            return (currentContacts, results, duplicateGroups, mergedOriginalIds)
        }.value
    }

    func runCleanup(on contacts: [ContactItem]) async -> [ContactItem] {
        isProcessing = true
        let startTime = Date()
        print("[Cleanup] 开始清理: \(contacts.count) 位联系人, 选项: \(selectedOptions.map { $0.rawValue }), 排除: \(excludedContactIDs.count) 位")

        // 在后台线程执行清理操作
        let (processedContacts, results, duplicateGroups, _) = await performCleanupInBackground(
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
        print("[Cleanup] 清理完成: 输入 \(contacts.count) 位 → 输出 \(processedContacts.count) 位")
        for r in results {
            print("[Cleanup]   \(r.option.rawValue): 前\(r.beforeCount) → 后\(r.afterCount), 改进: \(r.improved)")
        }

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

    /// 执行清理并记录修改（不写入），用于统一写入模式
    func performCleanupAndRecord(on contacts: [ContactItem]) async {
        isProcessing = true
        let startTime = Date()
        print("[Cleanup] 开始清理: \(contacts.count) 位联系人, 选项: \(selectedOptions.map { $0.rawValue }), 排除: \(excludedContactIDs.count) 位")

        let (processed, results, duplicateGroups, mergedIds) = await performCleanupInBackground(
            contacts: contacts,
            options: selectedOptions,
            excludedIDs: excludedContactIDs,
            strategy: mergeStrategy
        )

        let endTime = Date()

        self.cleanupSummary = CleanupSummary(results: results, startTime: startTime, endTime: endTime)
        self.processedContacts = processed
        self.duplicateGroups = duplicateGroups
        // 仅当本次去重有需要删除的ID时才覆盖（避免非去重操作清空之前的记录）
        if !mergedIds.isEmpty {
            self.mergedOriginalIds = mergedIds
        }
        self.isProcessing = false
        self.showResult = true

        // 记录修改，标记为待写入
        self.hasPendingChanges = true
        let affectedCount = results.reduce(0) { $0 + $1.affectedContacts.count }
        self.pendingChangesCount = affectedCount
        // 收集所有被修改的联系人，用于精确写入
        var seen = Set<String>()
        self.affectedContacts = results.flatMap { $0.affectedContacts }.filter { seen.insert($0.id).inserted }

        print("[Cleanup] 清理完成: 输入 \(contacts.count) 位 → 输出 \(processed.count) 位")
        print("[Cleanup] 记录修改: \(affectedCount) 位联系人待写入")
        if !mergedIds.isEmpty {
            print("[Cleanup] 记录删除: \(mergedIds.count) 位重复联系人待删除")
        }
    }

    // MARK: - 写入（使用 UPDATE 操作保留容器信息）

    func writeBackToSystemDirect() async -> (success: Int, failed: Int) {
        // 重入保护
        if isWritingBack { return (0, 0) }
        let signature = Self.signature(for: processedContacts)
        if let last = lastWrittenSignature, last == signature {
            print("[WriteBack] 跳过重复写入：当前结果已写入过，共 \(processedContacts.count) 位")
            return (processedContacts.count, 0)
        }

        guard !processedContacts.isEmpty else {
            print("[WriteBack] processedContacts 为空，跳过写入")
            isWritingBack = false
            writeBackProgress = 0.0
            return (0, 0)
        }

        isWritingBack = true
        writeBackProgress = 0.0
        let contactsToWrite = processedContacts
        print("[WriteBack] 开始写入 \(contactsToWrite.count) 位联系人到系统通讯录")

        let authStatus = CNContactStore.authorizationStatus(for: .contacts)
        guard authStatus == .authorized else {
            isWritingBack = false
            writeBackProgress = 0.0
            return (0, contactsToWrite.count)
        }

        let backupSuccess = await backupContacts(processedContacts)
        print("备份结果: \(backupSuccess)")

        let idsToDelete = mergedOriginalIds
        print("[WriteBack] 待删除的重复联系人ID数量: \(idsToDelete.count)")

        let preWriteCount = await Self.readContactCount()

        let result: (Int, Int) = await Task.detached { [weak self] in
            let store = CNContactStore()
            var successCount = 0
            var failedCount = 0
            var deletedCount = 0

            // 1) 读取所有现有系统联系人
            print("[WriteBack] 步骤1: 读取现有联系人")
            var existingContacts: [(original: CNMutableContact, identifier: String)] = []
            do {
                let keysToFetch: [CNKeyDescriptor] = [
                    CNContactIdentifierKey as CNKeyDescriptor,
                    CNContactFamilyNameKey as CNKeyDescriptor,
                    CNContactGivenNameKey as CNKeyDescriptor,
                    CNContactPhoneNumbersKey as CNKeyDescriptor,
                    CNContactEmailAddressesKey as CNKeyDescriptor,
                    CNContactOrganizationNameKey as CNKeyDescriptor,
                    CNContactDepartmentNameKey as CNKeyDescriptor
                ]
                let req = CNContactFetchRequest(keysToFetch: keysToFetch)
                req.unifyResults = true
                try store.enumerateContacts(with: req) { c, _ in
                    if let m = c.mutableCopy() as? CNMutableContact {
                        existingContacts.append((m, c.identifier))
                    }
                }
            } catch {
                print("[WriteBack] 读取联系人失败: \(error)")
            }
            print("[WriteBack] 读取到 \(existingContacts.count) 位联系人")

            // 构建匹配索引
            var idToContact: [String: (original: CNMutableContact, identifier: String)] = [:]
            var nameToContacts: [String: [(original: CNMutableContact, identifier: String)]] = [:]
            var phoneToContacts: [String: (original: CNMutableContact, identifier: String)] = [:]
            for item in existingContacts {
                let fullName = "\(item.original.familyName)\(item.original.givenName)"
                if !fullName.isEmpty {
                    idToContact[item.identifier] = item
                    nameToContacts[fullName, default: []].append(item)
                }
                // 建立手机号→联系人索引（用于 VCF 导入的 UUID 联系人匹配）
                for phone in item.original.phoneNumbers {
                    let digits = phone.value.stringValue.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    if !digits.isEmpty {
                        let norm = digits.hasPrefix("86") && digits.count > 11 ? String(digits.dropFirst(2)) : digits
                        phoneToContacts[norm] = item
                    }
                }
            }
            print("[WriteBack] 创建匹配表: id=\(idToContact.count), name(含同名)=\(nameToContacts.reduce(0) { $0 + $1.value.count }), phone=\(phoneToContacts.count)")

            // 2) 批量更新/新增联系人使用一个 CNSaveRequest（而非逐个 execute）
            let saveReq = CNSaveRequest()
            let total = contactsToWrite.count
            var updatedCount = 0
            var addedCount = 0
            var matchedIds: Set<String> = []

            for (index, contact) in contactsToWrite.enumerated() {
                let fullName = "\(contact.familyName)\(contact.givenName)"
                var matched = false

                // 策略1: identifier 精确匹配（优先，保留容器信息）
                if let existing = idToContact[contact.id] {
                    print("[WriteBack] 匹配成功 [ID] \(fullName)")
                    existing.original.givenName = contact.givenName
                    existing.original.familyName = contact.familyName
                    existing.original.organizationName = contact.organization
                    existing.original.departmentName = contact.department
                    existing.original.phoneNumbers = contact.phoneNumbers.map { lv in
                        CNLabeledValue(label: Self.convertToSystemPhoneLabel(lv.label),
                                       value: CNPhoneNumber(stringValue: lv.value))
                    }
                    existing.original.emailAddresses = contact.emailAddresses.map { lv in
                        CNLabeledValue(label: Self.convertToSystemEmailLabel(lv.label),
                                       value: lv.value as NSString)
                    }
                    saveReq.update(existing.original)
                    successCount += 1
                    updatedCount += 1
                    matchedIds.insert(existing.identifier)
                    matched = true
                }

                // 策略2: 手机号匹配（处理 VCF 导入联系人的 UUID ID）
                if !matched {
                    for phone in contact.phoneNumbers {
                        let digits = phone.value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                        let norm = digits.hasPrefix("86") && digits.count > 11 ? String(digits.dropFirst(2)) : digits
                        if let existing = phoneToContacts[norm], !matchedIds.contains(existing.identifier) {
                            print("[WriteBack] 匹配成功 [Phone] \(fullName) (\(norm))")
                            existing.original.givenName = contact.givenName
                            existing.original.familyName = contact.familyName
                            existing.original.organizationName = contact.organization
                            existing.original.departmentName = contact.department
                            existing.original.phoneNumbers = contact.phoneNumbers.map { lv in
                                CNLabeledValue(label: Self.convertToSystemPhoneLabel(lv.label),
                                               value: CNPhoneNumber(stringValue: lv.value))
                            }
                            existing.original.emailAddresses = contact.emailAddresses.map { lv in
                                CNLabeledValue(label: Self.convertToSystemEmailLabel(lv.label),
                                               value: lv.value as NSString)
                            }
                            saveReq.update(existing.original)
                            successCount += 1
                            updatedCount += 1
                            matchedIds.insert(existing.identifier)
                            matched = true
                            break
                        }
                    }
                }

                // 策略3: 姓名匹配
                if !matched, let nameMatches = nameToContacts[fullName], !nameMatches.isEmpty {
                    let bestMatch = nameMatches.first { !matchedIds.contains($0.identifier) }
                        ?? nameMatches.first
                    if let existing = bestMatch {
                        print("[WriteBack] 匹配成功 [Name] \(fullName)")
                        existing.original.givenName = contact.givenName
                        existing.original.familyName = contact.familyName
                        existing.original.organizationName = contact.organization
                        existing.original.departmentName = contact.department
                        existing.original.phoneNumbers = contact.phoneNumbers.map { lv in
                            CNLabeledValue(label: Self.convertToSystemPhoneLabel(lv.label),
                                           value: CNPhoneNumber(stringValue: lv.value))
                        }
                        existing.original.emailAddresses = contact.emailAddresses.map { lv in
                            CNLabeledValue(label: Self.convertToSystemEmailLabel(lv.label),
                                           value: lv.value as NSString)
                        }
                        saveReq.update(existing.original)
                        successCount += 1
                        updatedCount += 1
                        matchedIds.insert(existing.identifier)
                        matched = true
                    }
                }

                if !matched {
                    let hasSameName = nameToContacts[fullName]?.isEmpty == false
                    if hasSameName {
                        print("[WriteBack] ⚠️ 跳过创建 \(fullName)：系统中有同名联系人但均已被匹配")
                        failedCount += 1
                    } else {
                        print("[WriteBack] 未匹配 [New] \(fullName)")
                        let newContact = CNMutableContact()
                        newContact.givenName = contact.givenName
                        newContact.familyName = contact.familyName
                        newContact.organizationName = contact.organization
                        newContact.departmentName = contact.department
                        newContact.note = contact.note
                        newContact.birthday = contact.birthday
                        newContact.phoneNumbers = contact.phoneNumbers.map { lv in
                            CNLabeledValue(label: Self.convertToSystemPhoneLabel(lv.label),
                                           value: CNPhoneNumber(stringValue: lv.value))
                        }
                        newContact.emailAddresses = contact.emailAddresses.map { lv in
                            CNLabeledValue(label: Self.convertToSystemEmailLabel(lv.label),
                                           value: lv.value as NSString)
                        }
                        saveReq.add(newContact, toContainerWithIdentifier: nil)
                        successCount += 1
                        addedCount += 1
                    }
                }

                // 更新进度
                let p = Double(index + 1) / Double(total)
                await MainActor.run { self?.writeBackProgress = p }
            }

            // 3) 删除已被合并的重复联系人（同一批请求中）
            let processedIds = Set(contactsToWrite.map { $0.id })
            let idsToActuallyDelete = idsToDelete.filter { !processedIds.contains($0) && !matchedIds.contains($0) }
            print("[WriteBack] 过滤后待删除的ID数量: \(idsToActuallyDelete.count)")
            if !idsToActuallyDelete.isEmpty {
                print("[WriteBack] 开始删除 \(idsToActuallyDelete.count) 位重复联系人")
                for id in idsToActuallyDelete {
                    if let contact = try? store.unifiedContact(withIdentifier: id, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]),
                       let mutable = contact.mutableCopy() as? CNMutableContact {
                        saveReq.delete(mutable)
                        deletedCount += 1
                        print("[WriteBack] 已删除重复联系人: \(contact.givenName)\(contact.familyName)")
                    } else {
                        print("[WriteBack] 删除失败: 无法获取联系人 \(id)")
                    }
                }
            } else {
                print("[WriteBack] 无需删除重复联系人")
            }

            // 4) 统一执行批量操作（原子提交）
            //    如批量失败则逐个回退写入，避免单个异常数据导致全部丢失
            do {
                try store.execute(saveReq)
                print("[WriteBack] 批量操作成功: 更新\(updatedCount)位, 新增\(addedCount)位, 删除\(deletedCount)位")
            } catch {
                print("[WriteBack] 批量操作失败: \(error)，尝试逐个写入")
                // 回退到逐个写入
                successCount = 0
                failedCount = 0
                // 使用新请求逐个写入（原 saveReq 已执行失败，需重建）
                for contact in contactsToWrite {
                    let fullName = "\(contact.familyName)\(contact.givenName)"
                    var saved = false
                    // 手机号匹配（优先于姓名）
                    for phone in contact.phoneNumbers {
                        let digits = phone.value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                        let norm = digits.hasPrefix("86") && digits.count > 11 ? String(digits.dropFirst(2)) : digits
                        if let existing = phoneToContacts[norm], !matchedIds.contains(existing.identifier) {
                            existing.original.givenName = contact.givenName
                            existing.original.familyName = contact.familyName
                            existing.original.organizationName = contact.organization
                            existing.original.departmentName = contact.department
                            existing.original.phoneNumbers = contact.phoneNumbers.map { lv in
                                CNLabeledValue(label: Self.convertToSystemPhoneLabel(lv.label),
                                               value: CNPhoneNumber(stringValue: lv.value))
                            }
                            existing.original.emailAddresses = contact.emailAddresses.map { lv in
                                CNLabeledValue(label: Self.convertToSystemEmailLabel(lv.label),
                                               value: lv.value as NSString)
                            }
                            let singleReq = CNSaveRequest()
                            singleReq.update(existing.original)
                            if (try? store.execute(singleReq)) != nil {
                                saved = true
                                matchedIds.insert(existing.identifier)
                                print("[WriteBack] 逐个写入成功 [Phone] \(fullName)")
                            }
                            break
                        }
                    }
                    // 姓名匹配（手机号未匹配到）
                    if !saved, let nameMatches = nameToContacts[fullName], !nameMatches.isEmpty {
                        let match = nameMatches.first { !matchedIds.contains($0.identifier) }
                            ?? nameMatches.first
                        if let existing = match {
                            existing.original.givenName = contact.givenName
                            existing.original.familyName = contact.familyName
                            existing.original.organizationName = contact.organization
                            existing.original.departmentName = contact.department
                            existing.original.phoneNumbers = contact.phoneNumbers.map { lv in
                                CNLabeledValue(label: Self.convertToSystemPhoneLabel(lv.label),
                                               value: CNPhoneNumber(stringValue: lv.value))
                            }
                            existing.original.emailAddresses = contact.emailAddresses.map { lv in
                                CNLabeledValue(label: Self.convertToSystemEmailLabel(lv.label),
                                               value: lv.value as NSString)
                            }
                            let singleReq = CNSaveRequest()
                            singleReq.update(existing.original)
                            if (try? store.execute(singleReq)) != nil {
                                saved = true
                            } else {
                                print("[WriteBack] 单个写入失败: \(fullName)")
                            }
                            matchedIds.insert(existing.identifier)
                        }
                    }
                    if saved { successCount += 1 }
                    else { failedCount += 1 }
                }
                print("[WriteBack] 逐个写入完毕: 成功\(successCount), 失败\(failedCount)")
            }

            print("[WriteBack] 成功\(successCount)位, 失败\(failedCount)位")
            return (successCount, failedCount)
        }.value

        // 5) 写入后验证：联系人计数不应异常增长
        let postWriteCount = await Self.readContactCount()
        let netChange = postWriteCount - preWriteCount
        print("[WriteBack] ===== 写入后验证 =====")
        print("[WriteBack] 写入前: \(preWriteCount) 位, 写入后: \(postWriteCount) 位")
        print("[WriteBack] 净变化: \(netChange >= 0 ? "+" : "")\(netChange) 位")
        if netChange > 0 {
            print("[WriteBack] ⚠️ 警告: 写入后联系人数量增加了 \(netChange) 位，可能存在重复创建")
        }
        print("[WriteBack] =========================")

        // 写入成功时记录操作历史
        if result.1 == 0 {
            let desc = "写入 \(processedContacts.count) 位联系人"
            OperationHistoryManager.shared.recordOperation(description: desc, contacts: processedContacts)
        }

        await MainActor.run {
            self.writeBackProgress = 1.0
            self.isWritingBack = false
            if result.1 == 0 {
                self.lastWrittenSignature = signature
            }
        }
        return result
    }

    /// 读取系统通讯录的联系人总数（用于写入前后校验）
    private nonisolated static func readContactCount() async -> Int {
        await Task.detached {
            let store = CNContactStore()
            var count = 0
            do {
                let req = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
                try store.enumerateContacts(with: req) { _, _ in count += 1 }
            } catch {}
            return count
        }.value
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

    /// 清除写入签名，允许重新写入
    func clearWriteSignature() {
        lastWrittenSignature = nil
        print("[WriteBack] 写入签名已清除")
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
        // 手机标签优先匹配
        if lower.contains("手机") || lower.contains("mobile") || lower == "mp" || lower == "tel" ||
           lower.contains("phone") || lower.contains("iPhone") || lower.contains("苹果") || lower.isEmpty {
            return CNLabelPhoneNumberMobile
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

    // MARK: - 统一写入模式

    /// 写入全部 processedContacts（经历次优化后的完整通讯录）
    func writeSelectedContacts(currentSelectedIDs: Set<ContactItem.ID>) async -> (success: Int, failed: Int) {
        let toWrite = affectedContacts
        print("[WriteBack] 待写入联系人: \(toWrite.count) 位 (仅 affectedContacts)")
        let originalContacts = processedContacts
        processedContacts = toWrite
        let result = await writeBackToSystemDirect()
        processedContacts = originalContacts
        return result
    }

    /// 写入成功后清除待写入状态
    func clearPendingChanges() {
        hasPendingChanges = false
        pendingChangesCount = 0
        print("[Cleanup] 已清除待写入状态")
    }

    /// 根据用户选择的合并分组，调整 processedContacts 和 mergedOriginalIds
    func applyMergeSelection(_ selectedGroupIds: Set<UUID>) {
        guard !duplicateGroups.isEmpty else { return }

        var newMergedIds: Set<String> = []
        var mergedContactIdsToRemove: Set<String> = []
        var contactsToRestore: [ContactItem] = []

        for group in duplicateGroups {
            guard let primary = group.contacts.first else { continue }
            let keepMerged = selectedGroupIds.contains(group.id)

            if keepMerged {
                // 保留合并结果，标记需要删除的重复联系人
                for contact in group.contacts.dropFirst() {
                    newMergedIds.insert(contact.id)
                }
            } else {
                // 还原成独立联系人
                mergedContactIdsToRemove.insert(primary.id)
                contactsToRestore.append(contentsOf: group.contacts)
            }
        }

        // 重建 processedContacts
        var kept: [ContactItem] = []
        for c in processedContacts {
            if !mergedContactIdsToRemove.contains(c.id) {
                kept.append(c)
            }
        }
        processedContacts = kept + contactsToRestore
        mergedOriginalIds = newMergedIds
        print("[MergePreview] 应用选择: 保留 \(selectedGroupIds.count) 组合并, 还原 \(duplicateGroups.count - selectedGroupIds.count) 组")
    }

    /// 重置所有状态
    func resetAll() {
        selectedOptions = []
        processedContacts = []
        cleanupSummary = nil
        showResult = false
        duplicateGroups = []
        excludedContactIDs = []
        mergedOriginalIds = []
        hasPendingChanges = false
        pendingChangesCount = 0
        lastWrittenSignature = nil
        selectedContactIDsAtPreExecute = []
        print("[Cleanup] 已重置所有状态")
    }
}
