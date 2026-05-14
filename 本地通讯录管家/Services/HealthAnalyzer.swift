import Foundation

class HealthAnalyzer {

    static func analyze(_ contacts: [ContactItem]) -> HealthReport {
        let totalContacts = contacts.count
        var totalPhoneNumbers = 0
        var totalEmails = 0
        var contactsMissingName = 0
        var contactsNameNeedsStandardize = 0
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
            } else if ContactValidator.needsNameFix(contact) {
                contactsNameNeedsStandardize += 1
            }

            let phonePrefixes = contact.phoneNumbers.map { $0.value }.map { ContactValidator.extractPhonePrefix($0) }
            let uniquePrefixes = Set(phonePrefixes)
            if uniquePrefixes.count > 1 {
                contactsInconsistentPhonePrefix += 1
            }

            // 正确的检测：先按类型分组，同类型有多种写法才是不统一
            // 例如 "手机" + "mobile" + "iPhone" 都是移动电话的不同写法 → 标签不统一
            // 但 "手机" + "家庭" 是不同类型的电话 → 正确，不需要统一
            let groupedByNormalizedType = Dictionary(grouping: contact.phoneNumbers) {
                ContactNormalizer.unifyPhoneLabel($0.label)
            }
            let hasInconsistentLabels = groupedByNormalizedType.values.contains { phones in
                let uniqueLabels = Set(phones.map { $0.label })
                return uniqueLabels.count > 1
            }
            if hasInconsistentLabels {
                contactsInconsistentPhoneLabel += 1
            }

            // 邮箱标签检测同样修正：先按类型分组，同类型有多种写法才是不统一
            let emailGroupedByNormalizedType = Dictionary(grouping: contact.emailAddresses) {
                ContactNormalizer.unifyEmailLabel($0.label)
            }
            let hasInconsistentEmailLabels = emailGroupedByNormalizedType.values.contains { emails in
                let uniqueLabels = Set(emails.map { $0.label })
                return uniqueLabels.count > 1
            }
            if hasInconsistentEmailLabels {
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
                if !ContactValidator.isValidChinesePhone(digits) {
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
            contactsNameNotSplit: 0,
            contactsNameNeedsStandardize: contactsNameNeedsStandardize,
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

}
