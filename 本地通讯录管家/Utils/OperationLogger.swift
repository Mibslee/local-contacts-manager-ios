import Foundation
import Combine

@MainActor
class OperationLogger: ObservableObject {
    static let shared = OperationLogger()

    struct LogEntry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let operation: String
        let details: String
        let affectedCount: Int

        init(operation: String, details: String, affectedCount: Int) {
            self.id = UUID()
            self.timestamp = Date()
            self.operation = operation
            self.details = details
            self.affectedCount = affectedCount
        }
    }

    @Published private(set) var logs: [LogEntry] = []

    private let maxLogs = 100

    private init() {
        loadLogs()
    }

    func log(operation: String, details: String, affectedCount: Int) {
        let entry = LogEntry(operation: operation, details: details, affectedCount: affectedCount)
        logs.insert(entry, at: 0)
        if logs.count > maxLogs {
            logs = Array(logs.prefix(maxLogs))
        }
        saveLogs()
    }

    func clearLogs() {
        logs.removeAll()
        saveLogs()
    }

    private func saveLogs() {
        if let data = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(data, forKey: "operation_logs")
        }
    }

    private func loadLogs() {
        if let data = UserDefaults.standard.data(forKey: "operation_logs"),
           let decoded = try? JSONDecoder().decode([LogEntry].self, from: data) {
            logs = decoded
        }
    }
}
