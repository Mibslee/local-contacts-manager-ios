import Foundation
import Contacts

struct ContactItem: Identifiable, Hashable {
    let id: String
    var familyName: String
    var givenName: String
    var fullName: String
    var phoneNumbers: [LabeledValue]
    var emailAddresses: [LabeledValue]
    var organization: String
    var department: String
    var birthday: DateComponents?
    var note: String
    var imageData: Data?
    var tags: [String]

    var initials: String {
        let f = familyName.prefix(1)
        let g = givenName.prefix(1)
        if f.isEmpty && g.isEmpty { return "?" }
        return "\(f)\(g)"
    }

    nonisolated var hasPhone: Bool { !phoneNumbers.isEmpty }
    nonisolated var hasEmail: Bool { !emailAddresses.isEmpty }
    nonisolated var isEmpty: Bool { !hasPhone && !hasEmail }

    struct LabeledValue: Identifiable, Hashable {
        let id = UUID()
        var label: String
        var value: String
    }

    init(cnContact: CNContact) {
        self.id = cnContact.identifier
        self.familyName = cnContact.familyName
        self.givenName = cnContact.givenName
        self.fullName = "\(cnContact.familyName)\(cnContact.givenName)"
        self.phoneNumbers = cnContact.phoneNumbers.map {
            LabeledValue(label: CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0.label ?? ""), value: Self.sanitizePhone($0.value.stringValue))
        }
        self.emailAddresses = cnContact.emailAddresses.map {
            LabeledValue(label: CNLabeledValue<NSString>.localizedString(forLabel: $0.label ?? ""), value: $0.value as String)
        }
        self.organization = cnContact.organizationName
        self.department = cnContact.departmentName
        self.birthday = nil
        self.note = ""
        self.imageData = nil
        self.tags = []
    }

    init(id: String = UUID().uuidString,
         familyName: String = "",
         givenName: String = "",
         phoneNumbers: [LabeledValue] = [],
         emailAddresses: [LabeledValue] = [],
         organization: String = "",
         department: String = "",
         note: String = "",
         tags: [String] = []) {
        self.id = id
        self.familyName = familyName
        self.givenName = givenName
        self.fullName = "\(familyName)\(givenName)"
        self.phoneNumbers = phoneNumbers
        self.emailAddresses = emailAddresses
        self.organization = organization
        self.department = department
        self.note = note
        self.tags = tags
    }

    static func sanitizePhone(_ raw: String) -> String {
        return raw
    }
}
