import Foundation

class ContactDeduplicator {

    struct DuplicateGroup: Identifiable {
        let id = UUID()
        let contacts: [ContactItem]
        let reason: String
        var isSelected: Bool = true
    }

    nonisolated static func findDuplicates(in contacts: [ContactItem]) -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []
        var processed = Set<String>()
        
        // 使用字典按姓名分组，提高性能
        var nameGroups: [String: [ContactItem]] = [:]
        
        for contact in contacts {
            let normalizedName = contact.fullName.replacingOccurrences(of: " ", with: "").lowercased()
            if !normalizedName.isEmpty {
                nameGroups[normalizedName, default: []].append(contact)
            }
        }
        
        // 处理按姓名分组的联系人
        for (_, nameGroup) in nameGroups {
            if nameGroup.count > 1 {
                // 进一步检查是否有相同的联系方式
                var similarGroups: [DuplicateGroup] = []
                var groupProcessed = Set<String>()
                
                for (i, contact) in nameGroup.enumerated() {
                    guard !groupProcessed.contains(contact.id) && !processed.contains(contact.id) else { continue }
                    
                    var duplicates: [ContactItem] = [contact]
                    
                    for (j, other) in nameGroup.enumerated() where j != i && !groupProcessed.contains(other.id) && !processed.contains(other.id) {
                        if areSimilar(contact, other) {
                            duplicates.append(other)
                            groupProcessed.insert(other.id)
                            processed.insert(other.id)
                        }
                    }
                    
                    if duplicates.count > 1 {
                        similarGroups.append(DuplicateGroup(contacts: duplicates, reason: detectReason(duplicates)))
                    }
                    
                    processed.insert(contact.id)
                }
                
                groups.append(contentsOf: similarGroups)
            }
        }

        return groups
    }

    nonisolated static func findDuplicatePhones(in contacts: [ContactItem]) -> [(phone: String, contacts: [ContactItem])] {
        var phoneMap: [String: [ContactItem]] = [:]

        for contact in contacts {
            for phone in contact.phoneNumbers {
                let normalized = normalizeForComparison(phone.value)
                phoneMap[normalized, default: []].append(contact)
            }
        }

        return phoneMap.filter { $0.value.count > 1 }
            .map { (phone: $0.key, contacts: $0.value) }
    }

    nonisolated static func findDuplicateEmails(in contacts: [ContactItem]) -> [(email: String, contacts: [ContactItem])] {
        var emailMap: [String: [ContactItem]] = [:]

        for contact in contacts {
            for email in contact.emailAddresses {
                let normalized = email.value.lowercased().trimmingCharacters(in: .whitespaces)
                emailMap[normalized, default: []].append(contact)
            }
        }

        return emailMap.filter { $0.value.count > 1 }
            .map { (email: $0.key, contacts: $0.value) }
    }

    nonisolated static func findDuplicatePhonesInContact(_ contact: ContactItem) -> [String] {
        var seen: [String: Int] = [:]
        var duplicates: [String] = []

        for phone in contact.phoneNumbers {
            let normalized = normalizeForComparison(phone.value)
            if seen[normalized] != nil {
                duplicates.append(phone.value)
            } else {
                seen[normalized] = 1
            }
        }

        return duplicates
    }

    nonisolated static func findDuplicateEmailsInContact(_ contact: ContactItem) -> [String] {
        var seen: Set<String> = []
        var duplicates: [String] = []

        for email in contact.emailAddresses {
            let normalized = email.value.lowercased().trimmingCharacters(in: .whitespaces)
            if seen.contains(normalized) {
                duplicates.append(email.value)
            } else {
                seen.insert(normalized)
            }
        }

        return duplicates
    }

    nonisolated static func mergeContacts(_ contacts: [ContactItem], strategy: MergeStrategy = .keepMoreInfo) -> ContactItem {
        guard let primary = contacts.first else {
            fatalError("Cannot merge empty contacts")
        }

        var merged = primary

        var allPhones = Set<String>()
        var allEmails = Set<String>()

        for contact in contacts {
            for phone in contact.phoneNumbers {
                let normalized = normalizeForComparison(phone.value)
                if !allPhones.contains(normalized) {
                    allPhones.insert(normalized)
                    merged.phoneNumbers.append(phone)
                }
            }
            for email in contact.emailAddresses {
                let normalized = email.value.lowercased()
                if !allEmails.contains(normalized) {
                    allEmails.insert(normalized)
                    merged.emailAddresses.append(email)
                }
            }

            if merged.organization.isEmpty && !contact.organization.isEmpty {
                merged.organization = contact.organization
            }
            if merged.department.isEmpty && !contact.department.isEmpty {
                merged.department = contact.department
            }
            if merged.note.isEmpty && !contact.note.isEmpty {
                merged.note = contact.note
            }
            if merged.imageData == nil {
                merged.imageData = contact.imageData
            }
        }

        return merged
    }

    // MARK: - Private Helpers

    private nonisolated static func areSimilar(_ a: ContactItem, _ b: ContactItem) -> Bool {
        let nameMatch = namesAreSimilar(a.fullName, b.fullName)
        guard nameMatch else { return false }

        let phonesA = Set(a.phoneNumbers.map { normalizeForComparison($0.value) })
        let phonesB = Set(b.phoneNumbers.map { normalizeForComparison($0.value) })
        if !phonesA.isEmpty && !phonesB.isEmpty && !phonesA.isDisjoint(with: phonesB) {
            return true
        }

        let emailsA = Set(a.emailAddresses.map { $0.value.lowercased() })
        let emailsB = Set(b.emailAddresses.map { $0.value.lowercased() })
        if !emailsA.isEmpty && !emailsB.isEmpty && !emailsA.isDisjoint(with: emailsB) {
            return true
        }

        return false
    }

    private nonisolated static func namesAreSimilar(_ a: String, _ b: String) -> Bool {
        let cleanA = a.replacingOccurrences(of: " ", with: "").lowercased()
        let cleanB = b.replacingOccurrences(of: " ", with: "").lowercased()
        return cleanA == cleanB
    }

    private nonisolated static func normalizeForComparison(_ phone: String) -> String {
        var number = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if number.hasPrefix("86") && number.count > 11 {
            number = String(number.dropFirst(2))
        }
        return number
    }

    private nonisolated static func detectReason(_ contacts: [ContactItem]) -> String {
        let names = Set(contacts.map { $0.fullName.replacingOccurrences(of: " ", with: "") })
        let hasSameName = names.count == 1

        var sharedPhone = false
        var sharedEmail = false

        for i in 0..<contacts.count {
            for j in (i+1)..<contacts.count {
                let phonesI = Set(contacts[i].phoneNumbers.map { normalizeForComparison($0.value) })
                let phonesJ = Set(contacts[j].phoneNumbers.map { normalizeForComparison($0.value) })
                if !phonesI.isDisjoint(with: phonesJ) { sharedPhone = true }

                let emailsI = Set(contacts[i].emailAddresses.map { $0.value.lowercased() })
                let emailsJ = Set(contacts[j].emailAddresses.map { $0.value.lowercased() })
                if !emailsI.isDisjoint(with: emailsJ) { sharedEmail = true }
            }
        }

        if hasSameName && sharedPhone { return "相同姓名 + 相同手机号" }
        if hasSameName && sharedEmail { return "相同姓名 + 相同邮箱" }
        if hasSameName { return "相同姓名" }
        if sharedPhone { return "相同手机号" }
        if sharedEmail { return "相同邮箱" }
        return "疑似重复"
    }
}
