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

        // 使用字典按姓名分组
        var nameGroups: [String: [ContactItem]] = [:]
        for contact in contacts {
            let normalizedName = contact.fullName.replacingOccurrences(of: " ", with: "").lowercased()
            if !normalizedName.isEmpty {
                nameGroups[normalizedName, default: []].append(contact)
            }
        }

        // 处理按姓名分组的联系人 — 使用 hash map 替代 O(n²) 嵌套循环
        for (_, nameGroup) in nameGroups where nameGroup.count > 1 {
            // 构建 phone/email → contacts 的倒排索引
            var phoneToContacts: [String: [ContactItem]] = [:]
            var emailToContacts: [String: [ContactItem]] = [:]

            for contact in nameGroup {
                for phone in contact.phoneNumbers {
                    phoneToContacts[normalizeForComparison(phone.value), default: []].append(contact)
                }
                for email in contact.emailAddresses {
                    emailToContacts[email.value.lowercased(), default: []].append(contact)
                }
            }

            // Union-Find: 共享 phone/email 的联系人归为一组
            var parent: [String: String] = [:]
            for c in nameGroup { parent[c.id] = c.id }

            func find(_ x: String) -> String {
                var root = x
                while parent[root] != root { root = parent[root]! }
                var cur = x
                while cur != root { let next = parent[cur]!; parent[cur] = root; cur = next }
                return root
            }
            func union(_ a: String, _ b: String) {
                let ra = find(a), rb = find(b)
                if ra != rb { parent[ra] = rb }
            }

            for (_, sharedContacts) in phoneToContacts where sharedContacts.count > 1 {
                for i in 1..<sharedContacts.count {
                    union(sharedContacts[0].id, sharedContacts[i].id)
                }
            }
            for (_, sharedContacts) in emailToContacts where sharedContacts.count > 1 {
                for i in 1..<sharedContacts.count {
                    union(sharedContacts[0].id, sharedContacts[i].id)
                }
            }

            // 按 root 分组
            var clusterMap: [String: [ContactItem]] = [:]
            for c in nameGroup {
                clusterMap[find(c.id), default: []].append(c)
            }
            for (_, cluster) in clusterMap where cluster.count > 1 {
                groups.append(DuplicateGroup(contacts: cluster, reason: detectReason(cluster)))
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
