import Foundation

class ContactExporter {

    static func exportToVCard(_ contacts: [ContactItem]) -> String {
        var vcard = ""
        for contact in contacts {
            vcard += generateVCard(for: contact)
        }
        return vcard
    }

    static func generateVCard(for contact: ContactItem) -> String {
        var lines: [String] = []
        lines.append("BEGIN:VCARD")
        lines.append("VERSION:3.0")

        let familyName = contact.familyName
        let givenName = contact.givenName
        let fullName = contact.fullName.isEmpty ? "\(familyName)\(givenName)" : contact.fullName

        lines.append("N:\(familyName);\(givenName);;;")
        lines.append("FN:\(fullName)")

        for phone in contact.phoneNumbers {
            let label = phoneLabelToVCard(phone.label)
            lines.append("TEL;TYPE=\(label):\(phone.value)")
        }

        for email in contact.emailAddresses {
            lines.append("EMAIL;TYPE=INTERNET:\(email.value)")
        }

        if !contact.organization.isEmpty {
            lines.append("ORG:\(contact.organization);\(contact.department)")
        }

        if !contact.note.isEmpty {
            lines.append("NOTE:\(contact.note)")
        }

        if let birthday = contact.birthday, let date = Calendar.current.date(from: birthday) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            lines.append("BDAY:\(formatter.string(from: date))")
        }

        if let imageData = contact.imageData {
            let base64 = imageData.base64EncodedString()
            lines.append("PHOTO;ENCODING=b;TYPE=JPEG:\(base64)")
        }

        lines.append("END:VCARD")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func exportToCSV(_ contacts: [ContactItem]) -> String {
        var csv = ""
        csv += "姓名,姓,名,手机1,手机1标签,手机2,手机2标签,邮箱1,邮箱1标签,邮箱2,邮箱2标签,公司,部门,备注\n"

        for contact in contacts {
            let name = escapeCSV(contact.fullName)
            let family = escapeCSV(contact.familyName)
            let given = escapeCSV(contact.givenName)

            let phone1 = contact.phoneNumbers.count > 0 ? escapeCSV(contact.phoneNumbers[0].value) : ""
            let phone1Label = contact.phoneNumbers.count > 0 ? escapeCSV(contact.phoneNumbers[0].label) : ""
            let phone2 = contact.phoneNumbers.count > 1 ? escapeCSV(contact.phoneNumbers[1].value) : ""
            let phone2Label = contact.phoneNumbers.count > 1 ? escapeCSV(contact.phoneNumbers[1].label) : ""

            let email1 = contact.emailAddresses.count > 0 ? escapeCSV(contact.emailAddresses[0].value) : ""
            let email1Label = contact.emailAddresses.count > 0 ? escapeCSV(contact.emailAddresses[0].label) : ""
            let email2 = contact.emailAddresses.count > 1 ? escapeCSV(contact.emailAddresses[1].value) : ""
            let email2Label = contact.emailAddresses.count > 1 ? escapeCSV(contact.emailAddresses[1].label) : ""

            let org = escapeCSV(contact.organization)
            let dept = escapeCSV(contact.department)
            let note = escapeCSV(contact.note)

            csv += "\(name),\(family),\(given),\(phone1),\(phone1Label),\(phone2),\(phone2Label),\(email1),\(email1Label),\(email2),\(email2Label),\(org),\(dept),\(note)\n"
        }

        return csv
    }

    static func saveToFile(content: String, fileName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("保存文件失败: \(error)")
            return nil
        }
    }

    static func saveDataToFile(data: Data, fileName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("保存文件失败: \(error)")
            return nil
        }
    }

    // MARK: - Helpers

    private static func phoneLabelToVCard(_ label: String) -> String {
        switch label {
        case "手机", "mobile", "Mobile": return "CELL"
        case "工作", "work", "Work": return "WORK"
        case "住宅", "home", "Home": return "HOME"
        case "传真", "fax", "Fax": return "FAX"
        default: return "CELL"
        }
    }

    private static func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}
