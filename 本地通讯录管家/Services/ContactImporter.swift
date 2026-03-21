import Foundation
import Contacts

class ContactImporter {

    struct ImportResult {
        let total: Int
        let success: Int
        let failed: Int
        let skipped: Int
        let contacts: [ContactItem]
        let errors: [String]
    }

    static func importFromVCard(data: Data) -> ImportResult {
        var contacts: [ContactItem] = []
        var errors: [String] = []

        do {
            let cnContacts = try CNContactVCardSerialization.contacts(with: data)
            for cnContact in cnContacts {
                contacts.append(ContactItem(cnContact: cnContact))
            }
            return ImportResult(total: cnContacts.count, success: cnContacts.count, failed: 0, skipped: 0, contacts: contacts, errors: [])
        } catch {
            errors.append("vCard解析失败: \(error.localizedDescription)")
            return ImportResult(total: 0, success: 0, failed: 0, skipped: 0, contacts: [], errors: errors)
        }
    }

    static func importFromCSV(data: Data, encoding: String.Encoding = .utf8) -> ImportResult {
        guard let content = String(data: data, encoding: encoding) else {
            return ImportResult(total: 0, success: 0, failed: 1, skipped: 0, contacts: [], errors: ["无法读取CSV文件"])
        }

        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let headerLine = lines.first else {
            return ImportResult(total: 0, success: 0, failed: 1, skipped: 0, contacts: [], errors: ["CSV文件为空"])
        }

        let headers = parseCSVLine(headerLine)
        let fieldMapping = mapCSVHeaders(headers)

        var contacts: [ContactItem] = []
        var errors: [String] = []
        var success = 0
        var failed = 0

        for (index, line) in lines.dropFirst().enumerated() {
            let values = parseCSVLine(line)
            guard values.count >= headers.count else {
                errors.append("第\(index + 2)行: 字段数量不足")
                failed += 1
                continue
            }

            var contact = ContactItem()

            if let nameIdx = fieldMapping["name"] {
                let name = values[nameIdx].trimmingCharacters(in: .whitespaces)
                let split = splitName(name)
                contact.familyName = split.familyName
                contact.givenName = split.givenName
                contact.fullName = name
            }

            if let familyIdx = fieldMapping["familyName"] {
                contact.familyName = values[familyIdx].trimmingCharacters(in: .whitespaces)
            }
            if let givenIdx = fieldMapping["givenName"] {
                contact.givenName = values[givenIdx].trimmingCharacters(in: .whitespaces)
            }

            if let phoneIdx = fieldMapping["phone"] {
                let phone = ContactItem.sanitizePhone(values[phoneIdx])
                if !phone.isEmpty {
                    contact.phoneNumbers.append(ContactItem.LabeledValue(label: "手机", value: phone))
                }
            }

            if let phone2Idx = fieldMapping["phone2"] {
                let phone2 = ContactItem.sanitizePhone(values[phone2Idx])
                if !phone2.isEmpty {
                    contact.phoneNumbers.append(ContactItem.LabeledValue(label: "手机", value: phone2))
                }
            }

            if let emailIdx = fieldMapping["email"] {
                let email = values[emailIdx].trimmingCharacters(in: .whitespaces)
                if !email.isEmpty {
                    contact.emailAddresses.append(ContactItem.LabeledValue(label: "邮箱", value: email))
                }
            }

            if let orgIdx = fieldMapping["company"] {
                contact.organization = values[orgIdx].trimmingCharacters(in: .whitespaces)
            }

            if contact.fullName.isEmpty {
                contact.fullName = "\(contact.familyName)\(contact.givenName)"
            }

            if contact.phoneNumbers.isEmpty && contact.emailAddresses.isEmpty {
                continue
            }

            contacts.append(contact)
            success += 1
        }

        return ImportResult(total: lines.count - 1, success: success, failed: failed, skipped: 0, contacts: contacts, errors: errors)
    }

    // MARK: - Helpers

    private static func mapCSVHeaders(_ headers: [String]) -> [String: Int] {
        var mapping: [String: Int] = [:]

        for (index, header) in headers.enumerated() {
            let h = header.lowercased().trimmingCharacters(in: .whitespaces)

            if h.contains("姓名") || h == "name" || h == "联系人" {
                mapping["name"] = index
            } else if h.contains("姓") && !h.contains("名") || h == "family" || h == "lastname" || h == "last name" {
                mapping["familyName"] = index
            } else if h.contains("名") && !h.contains("姓") || h == "given" || h == "firstname" || h == "first name" {
                mapping["givenName"] = index
            } else if h.contains("手机") || h.contains("电话") || h.contains("mobile") || h == "phone" || h == "tel" || h == "手机1" {
                mapping["phone"] = index
            } else if h == "手机2" || h == "电话2" || h == "phone2" || h == "mobile2" {
                mapping["phone2"] = index
            } else if h.contains("邮箱") || h.contains("email") || h.contains("邮件") || h.contains("e-mail") {
                mapping["email"] = index
            } else if h.contains("公司") || h.contains("组织") || h == "company" || h == "organization" || h == "org" {
                mapping["company"] = index
            }
        }

        return mapping
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)

        var i = 0
        while i < chars.count {
            let char = chars[i]
            if char == "\"" {
                if inQuotes && i + 1 < chars.count && chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
            i += 1
        }
        result.append(current)

        return result
    }

    private static func splitName(_ name: String) -> (familyName: String, givenName: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return ("", "") }

        let compoundSurnames = ["欧阳", "太史", "端木", "上官", "司马", "东方", "独孤", "南宫", "万俟", "闻人", "夏侯", "诸葛", "尉迟", "公羊", "赫连"]

        if trimmed.count >= 2 {
            let prefix2 = String(trimmed.prefix(2))
            if compoundSurnames.contains(prefix2) {
                return (prefix2, String(trimmed.dropFirst(2)))
            }
        }

        if trimmed.count <= 2 {
            return (String(trimmed.prefix(1)), String(trimmed.dropFirst(1)))
        }

        return (String(trimmed.prefix(1)), String(trimmed.dropFirst(1)))
    }
}
