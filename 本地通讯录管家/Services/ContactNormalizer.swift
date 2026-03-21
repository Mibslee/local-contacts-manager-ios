import Foundation

class ContactNormalizer {

    // MARK: - 姓名标准化

    static func normalizeName(for contact: ContactItem) -> ContactItem {
        var result = contact

        if result.familyName.count > 1 && result.givenName.isEmpty {
            let split = splitChineseName(result.familyName)
            result.familyName = split.familyName
            result.givenName = split.givenName
        } else if result.givenName.count > 1 && result.familyName.isEmpty {
            let split = splitChineseName(result.givenName)
            result.familyName = split.familyName
            result.givenName = split.givenName
        }

        result.fullName = "\(result.familyName)\(result.givenName)"
        return result
    }

    private static let compoundSurnames = ["欧阳", "太史", "端木", "上官", "司马", "东方", "独孤", "南宫", "万俟", "闻人", "夏侯", "诸葛", "尉迟", "公羊", "赫连", "澹台", "皇甫", "宗政", "濮阳", "公冶", "太叔", "申屠", "公孙", "慕容", "仲孙", "钟离", "长孙", "宇文", "司徒", "鲜于", "司空", "令狐", "百里", "东郭", "南门", "呼延", "羊舌", "微生", "公户", "公玉", "公仪", "梁丘", "公仲", "公上", "公门", "公山", "公坚", "公伯", "左丘", "公祖", "亓官", "司寇", "颛孙", "子车", "壤驷", "公良", "夹谷", "宰父", "谷梁", "段干", "拓跋", "乐正", "漆雕", "公西", "巫马", "公乘", "公冶", "宗政"]

    private static func splitChineseName(_ fullName: String) -> (familyName: String, givenName: String) {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }

        if trimmed.count >= 2 {
            let prefix2 = String(trimmed.prefix(2))
            if compoundSurnames.contains(prefix2) {
                return (prefix2, String(trimmed.dropFirst(2)))
            }
        }

        if trimmed.count == 1 {
            return (trimmed, "")
        }

        return (String(trimmed.prefix(1)), String(trimmed.dropFirst(1)))
    }

    // MARK: - 手机号标准化

    static func normalizePhoneNumber(_ phone: String) -> String {
        let number = phone
        
        // 只处理前缀，不做格式化，避免字符数组问题
        let cleaned = number.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        
        if cleaned.hasPrefix("+86") {
            // 有+86前缀，移除+86，保持统一
            let result = String(cleaned.dropFirst(3))
            return result
        }
        
        if cleaned.hasPrefix("86") && cleaned.count > 11 {
            // 有86前缀但没有+，移除86
            let result = String(cleaned.dropFirst(2))
            return result
        }
        
        return number
    }

    static func unifyPhoneLabel(_ label: String) -> String {
        let lower = label.lowercased()
        if lower.contains("mobile") || lower.contains("手机") || lower == "mp" || lower == "tel" || lower.contains("phone") {
            return "手机"
        }
        return label
    }

    static func unifyEmailLabel(_ label: String) -> String {
        let lower = label.lowercased()
        if lower.contains("email") || lower.contains("邮箱") || lower.contains("邮件") || lower.contains("e-mail") || lower.contains("mail") {
            return "邮箱"
        }
        return label
    }

    // MARK: - 邮箱校验

    static func isValidEmail(_ email: String) -> Bool {
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", pattern)
        return predicate.evaluate(with: email)
    }

    // MARK: - 批量标准化

    static func normalizeAll(_ contacts: [ContactItem],
                              normalizeName: Bool = true,
                              normalizePhonePrefix: Bool = true,
                              unifyPhoneLabel: Bool = true,
                              unifyEmailLabel: Bool = true) -> [ContactItem] {
        return contacts.map { contact in
            var c = contact

            if normalizeName {
                c = Self.normalizeName(for: c)
            }

            if normalizePhonePrefix || unifyPhoneLabel {
                c.phoneNumbers = c.phoneNumbers.map { phone in
                    var p = phone
                    if normalizePhonePrefix {
                        p.value = Self.normalizePhoneNumber(p.value)
                    }
                    if unifyPhoneLabel {
                        p.label = Self.unifyPhoneLabel(p.label)
                    }
                    return p
                }
            }

            if unifyEmailLabel {
                c.emailAddresses = c.emailAddresses.map { email in
                    var e = email
                    e.label = Self.unifyEmailLabel(e.label)
                    return e
                }
            }

            return c
        }
    }
}
