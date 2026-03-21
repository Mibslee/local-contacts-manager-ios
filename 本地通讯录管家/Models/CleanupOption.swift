import Foundation

enum CleanupOption: String, CaseIterable, Identifiable {
    case nameNormalization = "姓名标准化"
    case phoneClean = "手机号清理"
    case phonePrefixUnify = "手机号前缀统一"
    case phoneLabelUnify = "手机标签统一"
    case phoneDeduplicate = "手机号去重"
    case emailLabelUnify = "邮箱标签统一"
    case emailDeduplicate = "邮箱去重"
    case emailValidation = "邮箱格式校验"
    case contactDeduplicate = "重复联系人合并"
    case removeEmptyContacts = "删除空联系人"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .nameNormalization: return "person.text.rectangle"
        case .phoneClean: return "phone.badge.waveform"
        case .phonePrefixUnify: return "phone.badge.plus"
        case .phoneLabelUnify: return "tag"
        case .phoneDeduplicate: return "phone.down"
        case .emailLabelUnify: return "envelope"
        case .emailDeduplicate: return "envelope.badge"
        case .emailValidation: return "checkmark.shield"
        case .contactDeduplicate: return "person.2"
        case .removeEmptyContacts: return "person.crop.circle.badge.xmark"
        }
    }

    var description: String {
        switch self {
        case .nameNormalization: return "自动拆分姓/名字段，处理中文姓名格式"
        case .phoneClean: return "提取纯数字，识别并清理异常/乱码号码"
        case .phonePrefixUnify: return "统一 +86/86-/86 等国际区号格式"
        case .phoneLabelUnify: return "统一手机/Mobile/MP等标签为\"手机\""
        case .phoneDeduplicate: return "同一下多个相同号码保留一个"
        case .emailLabelUnify: return "统一邮箱/Email/邮件等标签为\"邮箱\""
        case .emailDeduplicate: return "同一人下相同邮箱保留一个"
        case .emailValidation: return "校验邮箱格式，标记无效邮箱"
        case .contactDeduplicate: return "检测并合并姓名+联系方式相同的记录"
        case .removeEmptyContacts: return "删除没有任何联系方式的联系人"
        }
    }
}

enum MergeStrategy: String, CaseIterable {
    case keepMoreRecords = "保留更多记录"
    case keepMoreInfo = "信息更完整优先"
    case keepLatest = "最新记录优先"
}
