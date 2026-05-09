import Foundation
import Combine
import Contacts

class ContactsManager: ObservableObject {
    private let store = CNContactStore()
    @Published var authorizationStatus: CNAuthorizationStatus = .notDetermined

    init() {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            await MainActor.run {
                authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
            }
            return granted
        } catch {
            return false
        }
    }

    func fetchAllContacts() async -> [ContactItem] {
        // 性能优化：只取 ContactItem 真正使用到的 keys，
        // 不再加载缩略图/原图（之前会让大通讯录读取严重变慢）
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor
        ]

        return await Task.detached {
            let store = CNContactStore()
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            request.sortOrder = .userDefault
            request.unifyResults = true

            var contacts: [ContactItem] = []
            contacts.reserveCapacity(1024)
            do {
                try store.enumerateContacts(with: request) { cnContact, _ in
                    contacts.append(ContactItem(cnContact: cnContact))
                }
            } catch {
                print("获取通讯录失败: \(error)")
            }
            return contacts
        }.value
    }

    func saveContact(_ contact: ContactItem) -> Bool {
        let saveRequest = CNSaveRequest()
        let keys: [CNKeyDescriptor] = [
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor
        ]

        // 修复 Bug: 之前 update 用的是新建的 CNMutableContact（缺少 identifier），
        // 会导致更新失败甚至创建重复联系人。这里改为 mutableCopy 现有联系人。
        if let existing = try? store.unifiedContact(withIdentifier: contact.id, keysToFetch: keys),
           let mutable = existing.mutableCopy() as? CNMutableContact {
            mutable.familyName = contact.familyName
            mutable.givenName = contact.givenName
            mutable.organizationName = contact.organization
            mutable.departmentName = contact.department
            mutable.note = contact.note
            if let bd = contact.birthday { mutable.birthday = bd }
            mutable.phoneNumbers = contact.phoneNumbers.map {
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0.value))
            }
            mutable.emailAddresses = contact.emailAddresses.map {
                CNLabeledValue(label: CNLabelHome, value: $0.value as NSString)
            }
            saveRequest.update(mutable)
        } else {
            let cnContact = CNMutableContact()
            cnContact.familyName = contact.familyName
            cnContact.givenName = contact.givenName
            cnContact.organizationName = contact.organization
            cnContact.departmentName = contact.department
            cnContact.note = contact.note
            if let bd = contact.birthday { cnContact.birthday = bd }
            cnContact.phoneNumbers = contact.phoneNumbers.map {
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0.value))
            }
            cnContact.emailAddresses = contact.emailAddresses.map {
                CNLabeledValue(label: CNLabelHome, value: $0.value as NSString)
            }
            saveRequest.add(cnContact, toContainerWithIdentifier: nil)
        }

        do {
            try store.execute(saveRequest)
            return true
        } catch {
            print("保存联系人失败: \(error)")
            return false
        }
    }

    func deleteContact(withIdentifier identifier: String) -> Bool {
        guard let contact = try? store.unifiedContact(withIdentifier: identifier, keysToFetch: []) as? CNMutableContact else {
            return false
        }
        let saveRequest = CNSaveRequest()
        saveRequest.delete(contact)
        do {
            try store.execute(saveRequest)
            return true
        } catch {
            print("删除联系人失败: \(error)")
            return false
        }
    }

    func batchSaveContacts(_ contacts: [ContactItem]) -> (success: Int, failed: Int) {
        var successCount = 0
        var failedCount = 0

        let saveRequest = CNSaveRequest()

        for contact in contacts {
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

            if let existingContact = try? store.unifiedContact(withIdentifier: contact.id, keysToFetch: []) {
                if let mutable = existingContact.mutableCopy() as? CNMutableContact {
                    mutable.familyName = cnContact.familyName
                    mutable.givenName = cnContact.givenName
                    mutable.phoneNumbers = cnContact.phoneNumbers
                    mutable.emailAddresses = cnContact.emailAddresses
                    mutable.organizationName = cnContact.organizationName
                    mutable.departmentName = cnContact.departmentName
                    mutable.note = cnContact.note
                    saveRequest.update(mutable)
                }
            } else {
                saveRequest.add(cnContact, toContainerWithIdentifier: nil)
            }
        }

        do {
            try store.execute(saveRequest)
            successCount = contacts.count
        } catch {
            print("批量保存失败: \(error)")
            failedCount = contacts.count
        }

        return (successCount, failedCount)
    }
}
