import Foundation

struct CleanupResult {
    let option: CleanupOption
    let beforeCount: Int
    let afterCount: Int
    let details: [String]
    let affectedContacts: [ContactItem]

    var improvedCount: Int { beforeCount - afterCount }
    var improved: Bool { improvedCount > 0 }
}

struct CleanupSummary {
    let results: [CleanupResult]
    let startTime: Date
    let endTime: Date

    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }
    var totalImproved: Int { results.reduce(0) { $0 + $1.improvedCount } }
    var hasImprovements: Bool { totalImproved > 0 }
}
