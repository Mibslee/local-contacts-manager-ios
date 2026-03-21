import Foundation

class HealthAnalyzer {

    static func analyze(_ contacts: [ContactItem]) -> HealthReport {
        let totalContacts = contacts.count
        var totalPhoneNumbers = 0
        var totalEmails = 0
        var contactsMissingName = 0
        var contactsNameNotSplit = 0
        var contactsInconsistentPhonePrefix = 0
        var contactsInconsistentPhoneLabel = 0
        var contactsInconsistentEmailLabel = 0
        var contactsDuplicatePhone = 0
        var contactsDuplicateEmail = 0
        var invalidEmailCount = 0
        var emptyContactsCount = 0
        var garbledPhoneCount = 0

        let duplicateGroups = ContactDeduplicator.findDuplicates(in: contacts)
        let duplicateContactsCount = duplicateGroups.reduce(0) { $0 + $1.contacts.count - 1 }

        for contact in contacts {
            totalPhoneNumbers += contact.phoneNumbers.count
            totalEmails += contact.emailAddresses.count

            if contact.familyName.isEmpty && contact.givenName.isEmpty {
                contactsMissingName += 1
            } else if needsNameFix(contact) {
                contactsNameNotSplit += 1
            }

            let phonePrefixes = contact.phoneNumbers.map { $0.value }.map { extractPhonePrefix($0) }
            let uniquePrefixes = Set(phonePrefixes)
            if uniquePrefixes.count > 1 {
                contactsInconsistentPhonePrefix += 1
            }

            let phoneLabels = Set(contact.phoneNumbers.map { $0.label.lowercased() })
            if phoneLabels.count > 1 {
                contactsInconsistentPhoneLabel += 1
            }

            let emailLabels = Set(contact.emailAddresses.map { $0.label.lowercased() })
            if emailLabels.count > 1 {
                contactsInconsistentEmailLabel += 1
            }

            let duplicatePhones = ContactDeduplicator.findDuplicatePhonesInContact(contact)
            if !duplicatePhones.isEmpty {
                contactsDuplicatePhone += 1
            }

            let duplicateEmails = ContactDeduplicator.findDuplicateEmailsInContact(contact)
            if !duplicateEmails.isEmpty {
                contactsDuplicateEmail += 1
            }

            for email in contact.emailAddresses {
                if !ContactNormalizer.isValidEmail(email.value) {
                    invalidEmailCount += 1
                }
            }

            if contact.phoneNumbers.isEmpty && contact.emailAddresses.isEmpty {
                emptyContactsCount += 1
            }

            for phone in contact.phoneNumbers {
                let digits = phone.value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                if !isValidChinesePhone(digits) {
                    garbledPhoneCount += 1
                    break
                }
            }
        }

        return HealthReport(
            totalContacts: totalContacts,
            totalPhoneNumbers: totalPhoneNumbers,
            totalEmails: totalEmails,
            contactsMissingName: contactsMissingName,
            contactsNameNotSplit: contactsNameNotSplit,
            contactsNameNeedsStandardize: contactsNameNotSplit,
            contactsInconsistentPhonePrefix: contactsInconsistentPhonePrefix,
            contactsInconsistentPhoneLabel: contactsInconsistentPhoneLabel,
            contactsInconsistentEmailLabel: contactsInconsistentEmailLabel,
            contactsDuplicatePhone: contactsDuplicatePhone,
            contactsDuplicateEmail: contactsDuplicateEmail,
            duplicateContactsCount: duplicateContactsCount,
            emptyContactsCount: emptyContactsCount,
            invalidEmailCount: invalidEmailCount,
            contactsGarbledPhone: garbledPhoneCount
        )
    }

    private static func needsNameFix(_ contact: ContactItem) -> Bool {
        if contact.familyName.count > 1 && contact.givenName.isEmpty { return true }
        if contact.givenName.count > 1 && contact.familyName.isEmpty { return true }
        if contact.familyName.isEmpty && contact.givenName.isEmpty && !contact.fullName.isEmpty { return true }
        return false
    }

    private static func isValidChinesePhone(_ digits: String) -> Bool {
        if digits.isEmpty { return true }
        let clean = digits.hasPrefix("86") && digits.count > 11 ? String(digits.dropFirst(2)) : digits
        
        // 11位手机号（1开头）
        if clean.count == 11 && clean.hasPrefix("1") { return true }
        
        // 客服/服务电话（5-6位）
        if clean.count == 5 || clean.count == 6 { return true }
        
        // 固定电话（7-8位）
        if clean.count == 7 || clean.count == 8 { return true }
        
        // 带区号的固定电话（10-12位）
        if clean.count >= 10 && clean.count <= 12 { return true }
        
        // 国际号码或其他（只要不是太短都接受）
        if clean.count >= 5 && clean.count <= 15 { return true }
        
        return false
    }

    private static func extractPhonePrefix(_ phone: String) -> String {
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        if cleaned.hasPrefix("+86") { return "+86" }
        if cleaned.hasPrefix("86") && cleaned.count > 11 { return "86" }
        return "none"
    }
}
