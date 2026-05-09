import Foundation

/// 通讯录验证和格式化工具，消除 HealthAnalyzer / AppViewModel / CleanupViewModel 中的重复逻辑
enum ContactValidator {

    // MARK: - 姓名

    /// 判断联系人姓名是否需要标准化拆分
    static func needsNameFix(_ contact: ContactItem) -> Bool {
        if contact.familyName.count > 1 && contact.givenName.isEmpty { return true }
        if contact.givenName.count > 1 && contact.familyName.isEmpty { return true }
        if contact.familyName.isEmpty && contact.givenName.isEmpty && !contact.fullName.isEmpty { return true }
        return false
    }

    /// 仅检查姓名是否需要拆分（不包含"全名在姓氏中"的情况，用于清理管道的 before/after 统计）
    static func needsNameCheck(_ contact: ContactItem) -> Bool {
        if contact.familyName.count > 1 && contact.givenName.isEmpty { return true }
        if contact.givenName.count > 1 && contact.familyName.isEmpty { return true }
        return false
    }

    // MARK: - 电话号码

    /// 提取电话号码前缀类型（+86 / 86 / none）
    static func extractPhonePrefix(_ phone: String) -> String {
        let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        if cleaned.hasPrefix("+86") { return "+86" }
        if cleaned.hasPrefix("86") && cleaned.count > 11 { return "86" }
        return "none"
    }

    /// 判断是否为有效中国电话号码（手机号、固定电话、客服号码、国际号码）
    static func isValidChinesePhone(_ digits: String) -> Bool {
        if digits.isEmpty { return true }
        let clean = digits.hasPrefix("86") && digits.count > 11 ? String(digits.dropFirst(2)) : digits
        // 11位手机号（1开头）
        if clean.count == 11 && clean.hasPrefix("1") { return true }
        // 客服/服务电话（5-6位）
        if clean.count == 5 || clean.count == 6 { return true }
        // 固定电话（7-8位）
        if clean.count == 7 || clean.count == 8 { return true }
        // 带区号的固定电话（10-12位）
        if clean.count >= 10 && clean.count <= 12 { return true }
        // 国际号码或其他（5-15位都接受）
        if clean.count >= 5 && clean.count <= 15 { return true }
        return false
    }

    /// 判断是否为有效电话号码（用于清理管道，空字符串视为无效）
    static func isValidPhone(_ digits: String) -> Bool {
        if digits.isEmpty { return false }
        let clean = digits.hasPrefix("86") && digits.count > 11 ? String(digits.dropFirst(2)) : digits
        if clean.count == 11 && clean.hasPrefix("1") { return true }
        if clean.count >= 7 && clean.count <= 15 { return true }
        return false
    }

    // MARK: - 电话号码清理

    /// 清理并标准化电话号码（供 sanitizePhone 使用）
    static func cleanPhoneNumber(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // 移除特殊字符，保留数字和+
        let cleaned = trimmed.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        let digits = cleaned.replacingOccurrences(of: "+", with: "")

        // 固定电话（7-8位或带区号10-12位）不处理前缀
        if digits.count >= 7 && digits.count <= 8 { return cleaned }
        if digits.count >= 10 && digits.count <= 12 && !digits.hasPrefix("1") { return cleaned }

        // 手机号：移除 +86 / 86 前缀
        if cleaned.hasPrefix("+86") && cleaned.count > 3 {
            return String(cleaned.dropFirst(3))
        }
        if cleaned.hasPrefix("86") && cleaned.count > 11 {
            return String(cleaned.dropFirst(2))
        }

        return cleaned
    }
}
