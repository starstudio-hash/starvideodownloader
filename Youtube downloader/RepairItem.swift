import Foundation

enum RepairStatus: Equatable {
    case waiting
    case scanning
    case scanned(severity: String)
    case repairing(progress: Double, stage: Int, totalStages: Int)
    case completed
    case failed(String)
    case cancelled
}

enum RepairMode: String, CaseIterable {
    case auto = "Auto"
    case quickFix = "Quick Fix"
    case deepRepair = "Deep Repair"

    var description: String {
        switch self {
        case .auto: return "Tries light fixes first, escalates if needed"
        case .quickFix: return "Fast container rebuild only (no quality loss)"
        case .deepRepair: return "All repair stages including re-encode"
        }
    }

    var maxStage: Int {
        switch self {
        case .auto: return 4
        case .quickFix: return 2
        case .deepRepair: return 6
        }
    }
}

@Observable
class RepairItem: Identifiable {
    let id = UUID()
    var inputPath: URL
    var outputPath: URL?
    var fileName: String
    var fileSize: Int64
    var status: RepairStatus = .waiting
    var detectedIssues: [String] = []
    var issueCount: Int = 0
    var repairStage: Int = 0
    var duration: Double = 0
    var resolution: String = ""
    var codec: String = ""
    var addedDate = Date()

    init(inputPath: URL) {
        self.inputPath = inputPath
        self.fileName = inputPath.lastPathComponent
        self.fileSize = (try? FileManager.default.attributesOfItem(atPath: inputPath.path)[.size] as? Int64) ?? 0
    }

    var fileSizeString: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var severityColor: String {
        if case .scanned(let severity) = status {
            switch severity {
            case "None": return "green"
            case "Minor": return "yellow"
            case "Moderate": return "orange"
            case "Severe", "Critical": return "red"
            default: return "gray"
            }
        }
        return "gray"
    }

    var isActive: Bool {
        switch status {
        case .scanning, .repairing: return true
        default: return false
        }
    }

    var repairReport: String {
        let issues = detectedIssues.isEmpty ? "No issues recorded" : detectedIssues.joined(separator: ", ")
        let output = outputPath?.path ?? "No repaired output yet"
        return """
        File: \(fileName)
        Resolution: \(resolution.isEmpty ? "Unknown" : resolution)
        Codec: \(codec.isEmpty ? "Unknown" : codec)
        Issues: \(issues)
        Output: \(output)
        """
    }
}
