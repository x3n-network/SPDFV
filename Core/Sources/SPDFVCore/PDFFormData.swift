import Foundation
import PDFKit

public struct PDFFormDataEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct PDFFormDataFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let fields: [PDFFormDataEntry]

    public init(version: Int = Self.currentVersion, fields: [PDFFormDataEntry]) {
        self.version = version
        self.fields = fields
    }
}

public enum PDFFormDataIssueKind: String, Codable, Sendable {
    case duplicate
    case missing
    case readOnly
    case unsupported
    case invalidChoice
    case conflictingWidgets
}

public struct PDFFormDataIssue: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(kind.rawValue):\(name)" }
    public let kind: PDFFormDataIssueKind
    public let name: String
    public let detail: String
}

public struct PDFFormDataValidationReport: Codable, Equatable, Sendable {
    public let inputFields: Int
    public let matchedFields: Int
    public let updatedFields: [String]
    public let unchangedFields: [String]
    public let issues: [PDFFormDataIssue]
    public let canApply: Bool
}

public extension PDFOperations {
    static func formData(for document: PDFDocument) throws -> PDFFormDataFile {
        guard !document.isLocked else {
            throw PDFOperationError.invalidInput("Unlock the PDF before exporting form data")
        }
        try requirePermission(.contentCopying, for: document)
        let report = formReport(for: document)
        guard !report.fields.isEmpty else {
            throw PDFOperationError.invalidInput("PDF does not contain interactive form fields")
        }
        guard report.conflictingWidgetNames.isEmpty else {
            throw PDFOperationError.invalidInput(
                "Resolve conflicting repeated fields before export: \(report.conflictingWidgetNames.joined(separator: ", "))"
            )
        }
        let grouped = Dictionary(grouping: report.fields, by: \.name)
        let entries = grouped.keys.sorted().compactMap { name -> PDFFormDataEntry? in
            guard let fields = grouped[name], let first = fields.first,
                  !fields.contains(where: \.readOnly),
                  ![.signature, .pushButton, .unknown].contains(first.kind) else { return nil }
            let value = first.value
            return PDFFormDataEntry(name: name, value: value)
        }
        guard !entries.isEmpty else {
            throw PDFOperationError.invalidInput("PDF does not contain writable data fields")
        }
        return PDFFormDataFile(fields: entries)
    }

    static func encodeFormData(_ file: PDFFormDataFile, pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    static func decodeFormData(_ data: Data) throws -> PDFFormDataFile {
        do {
            let file = try JSONDecoder().decode(PDFFormDataFile.self, from: data)
            guard file.version == PDFFormDataFile.currentVersion else {
                throw PDFOperationError.invalidInput(
                    "Unsupported form data version \(file.version); expected version \(PDFFormDataFile.currentVersion)"
                )
            }
            return file
        } catch let error as PDFOperationError {
            throw error
        } catch {
            throw PDFOperationError.invalidInput("Form data is not valid SPDFV JSON: \(error.localizedDescription)")
        }
    }

    static func validateFormData(_ file: PDFFormDataFile, for document: PDFDocument) -> PDFFormDataValidationReport {
        let report = formReport(for: document)
        let groupedFields = Dictionary(grouping: report.fields, by: \.name)
        let groupedInput = Dictionary(grouping: file.fields) { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        var issues: [PDFFormDataIssue] = []
        var updated: [String] = []
        var unchanged: [String] = []

        for name in groupedInput.keys.sorted() {
            guard !name.isEmpty else {
                issues.append(PDFFormDataIssue(kind: .missing, name: "(empty)", detail: "Field names cannot be empty."))
                continue
            }
            guard let entries = groupedInput[name], entries.count == 1, let entry = entries.first else {
                issues.append(PDFFormDataIssue(kind: .duplicate, name: name, detail: "The data file defines this field more than once."))
                continue
            }
            guard let widgets = groupedFields[name], !widgets.isEmpty else {
                issues.append(PDFFormDataIssue(kind: .missing, name: name, detail: "No matching field exists in this PDF."))
                continue
            }
            if widgets.contains(where: \.readOnly) {
                issues.append(PDFFormDataIssue(kind: .readOnly, name: name, detail: "The matching field is read-only."))
                continue
            }
            let kinds = Set(widgets.map(\.kind))
            if kinds.count != 1 || Set(widgets.map(\.value)).count > 1 {
                issues.append(PDFFormDataIssue(kind: .conflictingWidgets, name: name, detail: "Repeated widgets disagree on type or current value."))
                continue
            }
            guard let kind = kinds.first, ![.signature, .pushButton, .unknown].contains(kind) else {
                issues.append(PDFFormDataIssue(kind: .unsupported, name: name, detail: "This field type cannot accept imported data."))
                continue
            }
            if kind == .choice {
                let choices = Set(widgets.flatMap(\.choices))
                if !choices.isEmpty, !choices.contains(entry.value) {
                    issues.append(PDFFormDataIssue(kind: .invalidChoice, name: name, detail: "The imported value is not one of this field’s choices."))
                    continue
                }
            }
            if widgets.allSatisfy({ valuesEquivalent($0.value, entry.value, kind: kind) }) {
                unchanged.append(name)
            } else {
                updated.append(name)
            }
        }

        return PDFFormDataValidationReport(
            inputFields: file.fields.count,
            matchedFields: updated.count + unchanged.count,
            updatedFields: updated,
            unchangedFields: unchanged,
            issues: issues,
            canApply: !file.fields.isEmpty && issues.isEmpty
        )
    }

    @discardableResult
    static func applyFormData(_ file: PDFFormDataFile, to document: PDFDocument) throws -> PDFFormDataValidationReport {
        guard file.version == PDFFormDataFile.currentVersion else {
            throw PDFOperationError.invalidInput("Unsupported form data version \(file.version)")
        }
        try requirePermission(.formEntry, for: document)
        let validation = validateFormData(file, for: document)
        guard validation.canApply else {
            let names = validation.issues.map(\.name).joined(separator: ", ")
            throw PDFOperationError.invalidInput("Form data cannot be applied; review: \(names)")
        }
        let values = Dictionary(uniqueKeysWithValues: file.fields.map {
            ($0.name.trimmingCharacters(in: .whitespacesAndNewlines), $0.value)
        })
        for name in validation.updatedFields {
            if let value = values[name] { try applyFormValue(value, named: name, in: document) }
        }
        return validation
    }

    static func fillForm(data: Data, formData: PDFFormDataFile) throws -> PDFFormFillResult {
        guard formData.version == PDFFormDataFile.currentVersion else {
            throw PDFOperationError.invalidInput("Unsupported form data version \(formData.version)")
        }
        guard let document = PDFDocument(data: data) else {
            throw PDFOperationError.invalidInput("Input is not a readable PDF")
        }
        let validation = validateFormData(formData, for: document)
        guard validation.canApply else {
            let names = validation.issues.map(\.name).joined(separator: ", ")
            throw PDFOperationError.invalidInput("Form data cannot be applied; review: \(names)")
        }
        let values = Dictionary(uniqueKeysWithValues: formData.fields.map { ($0.name, $0.value) })
        return try fillForm(data: data, values: values)
    }

    private static func valuesEquivalent(_ current: String, _ proposed: String, kind: PDFFormFieldKind) -> Bool {
        switch kind {
        case .checkbox, .radio:
            return truthyDataValue(current) == truthyDataValue(proposed)
        default:
            return current == proposed
        }
    }

    private static func truthyDataValue(_ value: String) -> Bool {
        ["1", "true", "yes", "on", "checked"].contains(value.lowercased())
    }
}
