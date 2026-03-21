import Foundation
import SwiftUI

struct HealthReport {
    let totalContacts: Int
    let totalPhoneNumbers: Int
    let totalEmails: Int
    let contactsMissingName: Int
    let contactsNameNotSplit: Int
    let contactsNameNeedsStandardize: Int
    let contactsInconsistentPhonePrefix: Int
    let contactsInconsistentPhoneLabel: Int
    let contactsInconsistentEmailLabel: Int
    let contactsDuplicatePhone: Int
    let contactsDuplicateEmail: Int
    let duplicateContactsCount: Int
    let emptyContactsCount: Int
    let invalidEmailCount: Int
    let contactsGarbledPhone: Int

    var score: Int {
        guard totalContacts > 0 else { return 100 }
        var penalties = 0
        let duplicateRate = Double(duplicateContactsCount) / Double(totalContacts)
        penalties += Int(duplicateRate * 30)
        let nameNotSplitRate = Double(contactsNameNotSplit) / Double(totalContacts)
        penalties += Int(nameNotSplitRate * 20)
        let phoneInconsistentRate = Double(contactsInconsistentPhonePrefix + contactsInconsistentPhoneLabel) / Double(max(totalContacts, 1))
        penalties += Int(phoneInconsistentRate * 20)
        let emailInconsistentRate = Double(contactsInconsistentEmailLabel + invalidEmailCount) / Double(max(totalContacts, 1))
        penalties += Int(emailInconsistentRate * 15)
        let emptyRate = Double(emptyContactsCount) / Double(totalContacts)
        penalties += Int(emptyRate * 15)
        return max(0, 100 - penalties)
    }

    var scoreColor: String {
        switch score {
        case 80...100: return "green"
        case 50..<80: return "orange"
        default: return "red"
        }
    }

    enum IssueType: String {
        case nameNeedsStandardize = "姓名需标准化"
        case nameNotSplit = "姓名未拆分"
        case phonePrefixInconsistent = "手机号前缀不统一"
        case phoneLabelInconsistent = "手机标签不统一"
        case phoneDuplicate = "同人号码重复"
        case phoneGarbled = "手机号异常"
        case emailLabelInconsistent = "邮箱标签不统一"
        case emailDuplicate = "同人邮箱重复"
        case emailInvalid = "无效邮箱"
        case contactDuplicate = "重复联系人"
        case emptyContact = "空联系人"
    }

    struct IssueItem: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let count: Int
        let color: Color
        let issueType: IssueType
    }

    var issueItems: [IssueItem] {
        var items: [IssueItem] = []
        if contactsNameNeedsStandardize > 0 {
            items.append(IssueItem(icon: "person.text.rectangle", title: "姓名需标准化", count: contactsNameNeedsStandardize, color: .orange, issueType: .nameNeedsStandardize))
        }
        if contactsNameNotSplit > 0 {
            items.append(IssueItem(icon: "person.text.rectangle", title: "姓名未拆分", count: contactsNameNotSplit, color: .orange, issueType: .nameNotSplit))
        }
        if contactsGarbledPhone > 0 {
            items.append(IssueItem(icon: "phone.badge.exclamationmark", title: "手机号异常", count: contactsGarbledPhone, color: .red, issueType: .phoneGarbled))
        }
        if contactsInconsistentPhonePrefix > 0 {
            items.append(IssueItem(icon: "phone.badge.waveform", title: "手机号前缀不统一", count: contactsInconsistentPhonePrefix, color: .orange, issueType: .phonePrefixInconsistent))
        }
        if contactsInconsistentPhoneLabel > 0 {
            items.append(IssueItem(icon: "tag", title: "手机标签不统一", count: contactsInconsistentPhoneLabel, color: .orange, issueType: .phoneLabelInconsistent))
        }
        if contactsDuplicatePhone > 0 {
            items.append(IssueItem(icon: "phone.down", title: "同人号码重复", count: contactsDuplicatePhone, color: .red, issueType: .phoneDuplicate))
        }
        if contactsInconsistentEmailLabel > 0 {
            items.append(IssueItem(icon: "envelope", title: "邮箱标签不统一", count: contactsInconsistentEmailLabel, color: .orange, issueType: .emailLabelInconsistent))
        }
        if contactsDuplicateEmail > 0 {
            items.append(IssueItem(icon: "envelope.badge", title: "同人邮箱重复", count: contactsDuplicateEmail, color: .red, issueType: .emailDuplicate))
        }
        if invalidEmailCount > 0 {
            items.append(IssueItem(icon: "exclamationmark.triangle", title: "无效邮箱", count: invalidEmailCount, color: .red, issueType: .emailInvalid))
        }
        if duplicateContactsCount > 0 {
            items.append(IssueItem(icon: "person.2", title: "重复联系人", count: duplicateContactsCount, color: .red, issueType: .contactDuplicate))
        }
        if emptyContactsCount > 0 {
            items.append(IssueItem(icon: "person.crop.circle.badge.xmark", title: "空联系人", count: emptyContactsCount, color: .gray, issueType: .emptyContact))
        }
        return items
    }

    static let empty = HealthReport(
        totalContacts: 0, totalPhoneNumbers: 0, totalEmails: 0,
        contactsMissingName: 0, contactsNameNotSplit: 0, contactsNameNeedsStandardize: 0,
        contactsInconsistentPhonePrefix: 0, contactsInconsistentPhoneLabel: 0,
        contactsInconsistentEmailLabel: 0, contactsDuplicatePhone: 0,
        contactsDuplicateEmail: 0, duplicateContactsCount: 0,
        emptyContactsCount: 0, invalidEmailCount: 0, contactsGarbledPhone: 0
    )
}
