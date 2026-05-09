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
        // 动态确定最大手机号和邮箱数量，避免数据截断
        let maxPhones = contacts.map(\.phoneNumbers.count).max() ?? 0
        let maxEmails = contacts.map(\.emailAddresses.count).max() ?? 0
        let phoneCols = max(1, maxPhones)
        let emailCols = max(1, maxEmails)

        // 生成表头
        var headers = ["姓名", "姓", "名"]
        for i in 1...phoneCols {
            headers.append("手机\(i)")
            headers.append("手机\(i)标签")
        }
        for i in 1...emailCols {
            headers.append("邮箱\(i)")
            headers.append("邮箱\(i)标签")
        }
        headers.append(contentsOf: ["公司", "部门", "备注"])

        var csv = headers.joined(separator: ",") + "\n"

        // 生成数据行
        for contact in contacts {
            var fields: [String] = []
            fields.append(escapeCSV(contact.fullName))
            fields.append(escapeCSV(contact.familyName))
            fields.append(escapeCSV(contact.givenName))

            for i in 0..<phoneCols {
                if i < contact.phoneNumbers.count {
                    fields.append(escapeCSV(contact.phoneNumbers[i].value))
                    fields.append(escapeCSV(contact.phoneNumbers[i].label))
                } else {
                    fields.append("")
                    fields.append("")
                }
            }

            for i in 0..<emailCols {
                if i < contact.emailAddresses.count {
                    fields.append(escapeCSV(contact.emailAddresses[i].value))
                    fields.append(escapeCSV(contact.emailAddresses[i].label))
                } else {
                    fields.append("")
                    fields.append("")
                }
            }

            fields.append(escapeCSV(contact.organization))
            fields.append(escapeCSV(contact.department))
            fields.append(escapeCSV(contact.note))

            csv += fields.joined(separator: ",") + "\n"
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
