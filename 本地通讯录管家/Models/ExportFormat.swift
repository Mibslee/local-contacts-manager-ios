import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case vcard = "vCard (.vcf)"
    case csv = "CSV (.csv)"
    case excel = "CSV (Excel兼容)"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .vcard: return "doc.text"
        case .csv: return "tablecells"
        case .excel: return "tablecells.badge.ellipsis"
        }
    }

    var fileExtension: String {
        switch self {
        case .vcard: return "vcf"
        case .csv: return "csv"
        case .excel: return "csv"
        }
    }

    var mimeType: String {
        switch self {
        case .vcard: return "text/vcard"
        case .csv: return "text/csv"
        case .excel: return "text/csv"
        }
    }

    var utType: UTType {
        switch self {
        case .vcard: return .vCard
        case .csv: return .commaSeparatedText
        case .excel: return .commaSeparatedText
        }
    }
}
