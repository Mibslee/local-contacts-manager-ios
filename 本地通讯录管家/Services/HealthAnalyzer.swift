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
