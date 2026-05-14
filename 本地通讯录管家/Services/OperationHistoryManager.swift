import Foundation
import Contacts

/// 操作记录条目
struct OperationRecord: Codable, Identifiable {
    let id: String
    let date: Date
    let description: String
    let contactCount: Int
    let vcfFileName: String

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: date)
    }
}

/// 管理写入操作历史：写入前备份联系人 → 记录操作 → 支持回滚
@MainActor
class OperationHistoryManager {
    static let shared = OperationHistoryManager()
    private let historyKey = "operationHistory"
    private let fileManager = FileManager.default

    private var backupDir: URL {
        let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OperationBackups", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 读取历史记录
    var history: [OperationRecord] {
        get {
            guard let data = UserDefaults.standard.data(forKey: historyKey),
                  let records = try? JSONDecoder().decode([OperationRecord].self, from: data)
            else { return [] }
            return records.sorted { $0.date > $1.date }
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: historyKey)
            }
        }
    }

    /// 写入前调用：备份当前通讯录并记录操作
    func recordOperation(description: String, contacts: [ContactItem]) {
        let vcf = ContactExporter.exportToVCard(contacts)
        let fileName = "backup_\(Date().timeIntervalSince1970).vcf"
        let fileURL = backupDir.appendingPathComponent(fileName)
        try? vcf.data(using: .utf8)?.write(to: fileURL)

        let record = OperationRecord(
            id: UUID().uuidString,
            date: Date(),
            description: description,
            contactCount: contacts.count,
            vcfFileName: fileName
        )

        var current = history
        current.insert(record, at: 0)
        // 最多保留 30 条
        if current.count > 30 {
            for old in current[30...] {
                try? fileManager.removeItem(at: backupDir.appendingPathComponent(old.vcfFileName))
            }
            current = Array(current.prefix(30))
        }
        history = current
    }

    /// 回滚到指定历史版本
    func restore(to record: OperationRecord) async -> Bool {
        let fileURL = backupDir.appendingPathComponent(record.vcfFileName)
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        let importResult = ContactImporter.importFromVCard(data: data)
        guard !importResult.contacts.isEmpty else { return false }

        let store = CNContactStore()
        // 清空现有通讯录
        var existingIds: [String] = []
        try? store.enumerateContacts(
            with: CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
        ) { c, _ in existingIds.append(c.identifier) }

        if !existingIds.isEmpty {
            let deleteReq = CNSaveRequest()
            for id in existingIds {
                if let c = try? store.unifiedContact(withIdentifier: id, keysToFetch: []),
                   let m = c.mutableCopy() as? CNMutableContact {
                    deleteReq.delete(m)
                }
            }
            try? store.execute(deleteReq)
        }

        // 重新写入备份数据
        let addReq = CNSaveRequest()
        for contact in importResult.contacts {
            let cn = CNMutableContact()
            cn.familyName = contact.familyName
            cn.givenName = contact.givenName
            cn.organizationName = contact.organization
            cn.departmentName = contact.department
            cn.note = contact.note
            cn.phoneNumbers = contact.phoneNumbers.map {
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0.value))
            }
            cn.emailAddresses = contact.emailAddresses.map {
                CNLabeledValue(label: CNLabelHome, value: $0.value as NSString)
            }
            addReq.add(cn, toContainerWithIdentifier: nil)
        }
        try? store.execute(addReq)
        return true
    }

    /// 获取备份文件中的联系人
    func loadContacts(from record: OperationRecord) -> [ContactItem] {
        let fileURL = backupDir.appendingPathComponent(record.vcfFileName)
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return ContactImporter.importFromVCard(data: data).contacts
    }
}
