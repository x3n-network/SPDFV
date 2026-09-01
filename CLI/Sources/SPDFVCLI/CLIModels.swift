import Foundation
import SPDFVCore

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case failure(String)

    var description: String {
        switch self {
        case .usage(let message), .failure(let message): message
        }
    }
}

struct OptionParser {
    private(set) var positional: [String] = []
    private(set) var options: [String: String] = [:]
    private(set) var flags: Set<String> = []

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--force" || argument == "--pretty" || argument == "--no-ocr" || argument == "--dry-run" || argument == "--favorite" {
                flags.insert(argument)
                index += 1
            } else if argument.hasPrefix("--") {
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                    throw CLIError.usage("Missing value for \(argument)")
                }
                options[argument] = arguments[index + 1]
                index += 2
            } else {
                positional.append(argument)
                index += 1
            }
        }
    }

    func requireOption(_ name: String) throws -> String {
        guard let value = options[name], !value.isEmpty else {
            throw CLIError.usage("Missing required option \(name)")
        }
        return value
    }

    func rejectUnknownOptions(allowing allowed: Set<String>) throws {
        if let unknown = Set(options.keys).subtracting(allowed).sorted().first {
            throw CLIError.usage("Unknown option: \(unknown)")
        }
    }
}

struct OperationReport: Encodable {
    let operation: String
    let inputs: [String]
    let output: String
    let pages: [Int]?
    let pageCount: Int
    let details: [String: String]?
}

struct AnnotationListReport: Encodable {
    let input: String
    let pages: [Int]
    let count: Int
    let annotations: [PDFAnnotationReport]
}

struct OCROperationReport: Encodable {
    let operation: String
    let input: String
    let output: String
    let report: PDFOCRReport
}

struct TextPageReport: Encodable {
    let page: Int
    let characters: Int
    let text: String
}

struct TextExtractionReport: Encodable {
    let input: String
    let pages: [Int]
    let characters: Int
    let pageDetails: [TextPageReport]
}

struct RedactionOperationReport: Encodable {
    let operation: String
    let input: String
    let output: String
    let regions: [PDFRedactionRegion]
    let report: PDFRedactionReport
}

struct FormInspectionReport: Encodable {
    let input: String
    let report: PDFFormReport
}

struct FormGateInspectionReport: Encodable {
    let input: String
    let gate: PDFFormGateReport
}

struct FormDataExportOperationReport: Encodable {
    let operation: String
    let input: String
    let output: String
    let fields: Int
}

struct FormDataValidationOperationReport: Encodable {
    let operation: String
    let input: String
    let data: String
    let report: PDFFormDataValidationReport
}

struct FormDataImportOperationReport: Encodable {
    let operation: String
    let input: String
    let data: String
    let output: String
    let validation: PDFFormDataValidationReport
    let report: PDFFormReport
}

struct FormDataBatchMappingOperationReport: Encodable {
    let operation: String
    let input: String
    let data: String
    let output: String
    let mapping: PDFFormDataBatchMapping
}

struct FormDataBatchOperationReport: Encodable {
    let operation: String
    let input: String
    let data: String
    let outputDirectory: String?
    let dryRun: Bool
    let report: PDFFormDataBatchReport
}

struct SafetyGateInspectionReport: Encodable {
    let input: String
    let gate: PDFSafetyGateReport
}

struct SignatureVerificationOperationReport: Encodable {
    let operation: String
    let input: String
    let report: PDFSignatureVerificationReport
}

struct SafeShareInspectionReport: Encodable {
    let input: String
    let report: PDFSafeShareReport
}

struct CompareOperationReport: Encodable {
    let operation: String
    let reference: String
    let candidate: String
    let report: PDFComparisonReport
}

struct DoctorInspectionReport: Encodable {
    let input: String
    let report: PDFDoctorReport
    let plan: PDFDoctorRepairPlan
}

struct DoctorRepairOperationReport: Encodable {
    let operation: String
    let input: String
    let output: String
    let verification: PDFDoctorRepairVerification
    let ocr: PDFOCRReport?
}

struct FormFillOperationReport: Encodable {
    let operation: String
    let input: String
    let output: String
    let updatedFields: [String]
    let report: PDFFormReport
}

struct FormAuthoringOperationReport: Encodable {
    let operation: String
    let input: String
    let output: String
    let page: Int
    let field: PDFFormFieldReport
    let report: PDFFormReport
}

struct FormRenameOperationReport: Encodable {
    let operation: String
    let input: String
    let output: String
    let previousName: String
    let name: String
    let widgetCount: Int
    let report: PDFFormReport
}

struct RecipeOperationReport: Encodable {
    let operation: String
    let input: String
    let recipe: String
    let output: String?
    let report: PDFRecipeReport
}

struct BatchRecipeOperationReport: Encodable {
    let operation: String
    let inputDirectory: String
    let recipe: String
    let outputDirectory: String?
    let manifest: String?
    let report: PDFRecipeBatchReport
}

struct RecipeLibraryOperationReport: Encodable {
    let operation: String
    let library: String
    let count: Int
    let entry: PDFRecipeLibraryEntry?
    let entries: [PDFRecipeLibraryEntry]?
    let output: String?
}

struct RecipeQueueOperationReport: Encodable {
    let operation: String
    let queue: String
    let job: PDFRecipeJob?
    let summary: PDFRecipeJobQueueSummary
    let jobs: [PDFRecipeJob]?
}

struct RecipeWatchState: Codable {
    let version: Int
    var processed: [String]

    init(version: Int = 1, processed: [String] = []) {
        self.version = version
        self.processed = processed
    }
}

struct RecipeWatchItemReport: Encodable {
    let input: String
    let output: String
    let status: String
    let error: String?
}

struct RecipeWatchOperationReport: Encodable {
    let operation: String
    let inputDirectory: String
    let outputDirectory: String
    let recipe: String
    let state: String
    let discovered: Int
    let passed: Int
    let failed: Int
    let skipped: Int
    let items: [RecipeWatchItemReport]
}
