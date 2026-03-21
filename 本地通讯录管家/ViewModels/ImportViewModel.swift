import Foundation
import SwiftUI
import Combine
import Contacts
import UniformTypeIdentifiers

@MainActor
class ImportViewModel: ObservableObject {
    @Published var importedContacts: [ContactItem] = []
    @Published var importResult: ContactImporter.ImportResult?
    @Published var isImporting = false
    @Published var showFilePicker = false
    @Published var selectedFileType: FileType = .vcard
    @Published var fieldMapping: [String: Int] = [:]
    @Published var showMappingPreview = false

    enum FileType: String, CaseIterable {
        case vcard = "vCard (.vcf)"
        case csv = "CSV (.csv)"
    }

    func importFile(data: Data, fileName: String) {
        isImporting = true

        if fileName.lowercased().hasSuffix(".vcf") || fileName.lowercased().hasSuffix(".vcard") {
            importResult = ContactImporter.importFromVCard(data: data)
            importedContacts = importResult?.contacts ?? []
        } else if fileName.lowercased().hasSuffix(".csv") {
            importResult = ContactImporter.importFromCSV(data: data)
            importedContacts = importResult?.contacts ?? []
        }

        isImporting = false
    }

    func mergeToSystem(using manager: ContactsManager) -> (success: Int, failed: Int) {
        return manager.batchSaveContacts(importedContacts)
    }

    func mergeToSystemDirect() -> (success: Int, failed: Int) {
        let store = CNContactStore()
        let saveRequest = CNSaveRequest()
        var successCount = 0

        for contact in importedContacts {
            let cnContact = CNMutableContact()
            cnContact.familyName = contact.familyName
            cnContact.givenName = contact.givenName
            cnContact.organizationName = contact.organization
            cnContact.departmentName = contact.department
            cnContact.note = contact.note
            cnContact.phoneNumbers = contact.phoneNumbers.map {
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0.value))
            }
            cnContact.emailAddresses = contact.emailAddresses.map {
                CNLabeledValue(label: CNLabelHome, value: $0.value as NSString)
            }
            saveRequest.add(cnContact, toContainerWithIdentifier: nil)
            successCount += 1
        }

        do {
            try store.execute(saveRequest)
            return (successCount, 0)
        } catch {
            return (0, successCount)
        }
    }
}
