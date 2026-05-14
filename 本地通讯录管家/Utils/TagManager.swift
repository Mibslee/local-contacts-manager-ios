import Foundation

/// 管理用户自定义标签的创建、删除和持久化
class TagManager {
    static let shared = TagManager()
    private let tagsKey = "userDefinedTags"

    var tags: [String] {
        get { UserDefaults.standard.stringArray(forKey: tagsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: tagsKey) }
    }

    func addTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    func renameTag(from old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = tags
        if let idx = current.firstIndex(of: old) {
            current[idx] = trimmed
        }
        tags = current
        // 不会更新已添加此 tag 的联系人——用户下次写入时自动同步
    }

    /// 将 tags 赋给指定的联系人列表（修改内存中的 contacts 数组）
    static func applyTag(_ tag: String, to contactIDs: Set<ContactItem.ID>, contacts: inout [ContactItem]) {
        for i in contacts.indices {
            if contactIDs.contains(contacts[i].id), !contacts[i].tags.contains(tag) {
                contacts[i].tags.append(tag)
            }
        }
    }
}
