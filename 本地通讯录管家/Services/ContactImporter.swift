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

        // 先尝试系统解析器（支持 VCF 3.0/4.0）
        do {
            let cnContacts = try CNContactVCardSerialization.contacts(with: data)
            for cnContact in cnContacts {
                contacts.append(ContactItem(cnContact: cnContact))
            }
            return ImportResult(total: cnContacts.count, success: cnContacts.count, failed: 0, skipped: 0, contacts: contacts, errors: [])
        } catch {
            // 系统解析失败，尝试手动解析 VCF 2.1（含 QUOTED-PRINTABLE）
            print("[VCF] 系统解析失败，尝试手动解析 VCF 2.1: \(error.localizedDescription)")
            let manualResult = parseVCard21(data: data)
            if !manualResult.contacts.isEmpty {
                return manualResult
            }
            errors.append("vCard解析失败: \(error.localizedDescription)")
            return ImportResult(total: 0, success: 0, failed: 0, skipped: 0, contacts: [], errors: errors)
        }
    }

    // MARK: - VCF 2.1 手工解析（支持 QUOTED-PRINTABLE）

    /// 解析 VCF 2.1 格式（含 QUOTED-PRINTABLE 编码），回退方案
    static func parseVCard21(data: Data) -> ImportResult {
        guard let raw = String(data: data, encoding: .utf8) else {
            return ImportResult(total: 0, success: 0, failed: 0, skipped: 0, contacts: [], errors: ["VCF 数据无法以 UTF-8 解码"])
        }

        // 1) 按 BEGIN:VCARD / END:VCARD 切分为独立卡片
        let blocks = raw.components(separatedBy: "END:VCARD").filter { $0.contains("BEGIN:VCARD") }
        var contacts: [ContactItem] = []
        var errors: [String] = []

        for (i, block) in blocks.enumerated() {
            let fullBlock = block + "END:VCARD"
            guard let contact = parseVCard21Block(fullBlock) else {
                errors.append("第 \(i + 1) 张 vCard 解析失败")
                continue
            }
            contacts.append(contact)
        }

        return ImportResult(
            total: contacts.count,
            success: contacts.count,
            failed: errors.count,
            skipped: 0,
            contacts: contacts,
            errors: errors
        )
    }

    /// 解析单张 VCF 2.1 卡片
    private static func parseVCard21Block(_ block: String) -> ContactItem? {
        // 1) 展开折叠行（以空格或 tab 开头的行是上一行的延续）
        let unfolded = unfoldVCardLines(block)
        let lines = unfolded.components(separatedBy: "\n")

        guard lines.contains(where: { $0.hasPrefix("BEGIN:VCARD") }) else { return nil }

        var contact = ContactItem(id: UUID().uuidString)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            // 跳过 PHOTO 行及其后续的 BASE64 编码数据行
            if line.hasPrefix("PHOTO;") { continue }
            if line.hasPrefix("/9j/") || line.hasPrefix("iVBOR") || line.hasPrefix("Qk") { continue }

            guard let (key, params, value) = parseVCardLine(line) else { continue }

            switch key {
            case "VERSION":
                break

            case "N":
                // N:familyName;givenName;;;
                let parts = splitVCardValue(value, separator: ";")
                if parts.count >= 2 {
                    contact.familyName = parts[0]
                    contact.givenName = parts[1]
                } else if parts.count == 1 {
                    contact.familyName = parts[0]
                }

            case "FN":
                if contact.fullName.isEmpty || !value.isEmpty {
                    contact.fullName = value
                }

            case "TEL":
                let label = vCardParamToLabel(params)
                let cleanedPhone = ContactItem.sanitizePhone(value)
                if !cleanedPhone.isEmpty {
                    contact.phoneNumbers.append(ContactItem.LabeledValue(label: label, value: cleanedPhone))
                }

            case "EMAIL":
                let label = params.contains("WORK") || params.contains("work") ? "工作" : "邮箱"
                if !value.isEmpty {
                    contact.emailAddresses.append(ContactItem.LabeledValue(label: label, value: value))
                }

            case "ORG":
                contact.organization = value
                // ORG 可能包含部门：ORG:公司名;部门
                let orgParts = splitVCardValue(value, separator: ";")
                if orgParts.count >= 1 { contact.organization = orgParts[0] }
                if orgParts.count >= 2 { contact.department = orgParts[1] }

            case "URL", "NOTE", "ADR", "BDAY", "TITLE", "ROLE":
                // 暂不处理这些字段
                break

            default:
                break
            }
        }

        // 填充 fullName
        if contact.fullName.isEmpty {
            contact.fullName = "\(contact.familyName)\(contact.givenName)"
        }

        // 至少需要一个手机号或邮箱
        if contact.phoneNumbers.isEmpty && contact.emailAddresses.isEmpty {
            return nil
        }

        return contact
    }

    /// 展开 VCF 折叠行（RFC 2425: 以空格或 tab 开头的行是续行）
    private static func unfoldVCardLines(_ text: String) -> String {
        var result = ""
        var carry = ""
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                // 续行：去掉前导空白，追加到上一行
                carry += String(line.drop(while: { $0 == " " || $0 == "\t" }))
            } else {
                if !carry.isEmpty {
                    result += carry + "\n"
                }
                carry = line
            }
        }
        if !carry.isEmpty {
            result += carry
        }
        return result
    }

    /// 解析 VCF 行: key;params:value
    /// 支持 QUOTED-PRINTABLE 解码
    private static func parseVCardLine(_ line: String) -> (key: String, params: [String], value: String)? {
        guard let colonIdx = line.firstIndex(of: ":") else { return nil }
        let header = line[line.startIndex..<colonIdx]
        var rawValue = String(line[line.index(after: colonIdx)...])

        // 头部解析: KEY;PARAM1;PARAM2
        let headerParts = header.components(separatedBy: ";")
        guard let key = headerParts.first?.uppercased(), !key.isEmpty else { return nil }
        let params = Array(headerParts.dropFirst())

        // 检查是否 QUOTED-PRINTABLE 编码
        let isQP = params.contains(where: { $0.uppercased().contains("QUOTED-PRINTABLE") })
        if isQP {
            rawValue = decodeQuotedPrintable(rawValue)
        }

        // 检查 CHARSET 参数（非 QP 也可能有）
        let hasCharset = params.contains(where: { $0.uppercased().contains("CHARSET") })
        if hasCharset && !isQP {
            // 仅处理 UTF-8 声明（非 QP 的 CHARSET 通常意味着值已经是 UTF-8）
            // 不做特殊处理
        }

        // 提取 TYPE 参数（VCF 2.1 的 TEL;CELL → CELL 是类型）
        var cleanedParams: [String] = []
        for p in params {
            let upper = p.uppercased()
            if upper.hasPrefix("TYPE=") {
                cleanedParams.append(String(upper.dropFirst(5)))
            } else if !upper.contains("CHARSET") && !upper.contains("ENCODING") {
                // VCF 2.1 的裸类型参数
                cleanedParams.append(p)
            }
        }

        return (key, cleanedParams, rawValue)
    }

    /// 解码 QUOTED-PRINTABLE: =XX 转成对应字符，=\n 续行标记已由 unfold 处理
    private static func decodeQuotedPrintable(_ text: String) -> String {
        var result = Data()
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "=" && text.index(after: i) < text.endIndex {
                let nextIdx = text.index(after: i)
                let next = text[nextIdx]
                if next == "\n" || next == "\r" {
                    // 软换行: = 后跟换行，忽略（已在 unfold 中处理）
                    i = text.index(after: nextIdx)
                    if i < text.endIndex && text[i] == "\n" { i = text.index(after: i) }
                    continue
                }
                if text.distance(from: i, to: text.endIndex) >= 3 {
                    let hexStr = String(text[text.index(after: i)...text.index(i, offsetBy: 2)])
                    if let byte = UInt8(hexStr, radix: 16) {
                        result.append(byte)
                        i = text.index(i, offsetBy: 3)
                        continue
                    }
                }
            }
            if let byte = text[i].asciiValue {
                result.append(byte)
            } else {
                // 非 ASCII 字符（如中文），按 UTF-8 序列追加
                let char = text[i]
                if let data = String(char).data(using: .utf8) {
                    result.append(data)
                }
            }
            i = text.index(after: i)
        }
        // 尝试 UTF-8 解码
        if let decoded = String(data: result, encoding: .utf8) {
            return decoded
        }
        // 回退到 latin1
        if let decoded = String(data: result, encoding: .isoLatin1) {
            return decoded
        }
        return text
    }

    /// VCF 2.1 TEL 类型参数 → 标签
    private static func vCardParamToLabel(_ params: [String]) -> String {
        for p in params {
            let upper = p.uppercased()
            if upper == "CELL" || upper == "MP" { return "手机" }
            if upper == "WORK" { return "工作" }
            if upper == "HOME" { return "住宅" }
            if upper == "FAX" || upper == "WORKFAX" || upper == "HOMEFAX" { return "传真" }
            if upper == "VOICE" { return "手机" }
            if upper == "PAGER" { return "寻呼" }
            if upper == "MAIN" { return "主要" }
        }
        return "手机"
    }

    /// 分割 VCF 值（保留空段）
    private static func splitVCardValue(_ value: String, separator: Character) -> [String] {
        return value.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
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
