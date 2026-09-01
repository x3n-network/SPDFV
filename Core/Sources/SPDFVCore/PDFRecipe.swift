import Foundation
import PDFKit

public struct PDFRecipeStepReport: Codable, Equatable, Sendable, Identifiable {
    public let index: Int
    public let operation: String
    public let summary: String
    public let pageCount: Int
    public let widgetCount: Int

    public var id: Int { index }
}

public struct PDFRecipeReport: Codable, Equatable, Sendable {
    public let recipe: String
    public let version: Int
    public let dryRun: Bool
    public let inputPageCount: Int
    public let outputPageCount: Int
    public let steps: [PDFRecipeStepReport]
    public let formGate: PDFFormGateReport?
}

public struct PDFRecipeRunResult: Sendable {
    public let data: Data
    public let report: PDFRecipeReport
}

public enum PDFRecipeRunner {
    public static func decode(_ data: Data) throws -> PDFRecipe {
        do {
            let recipe = try JSONDecoder().decode(PDFRecipe.self, from: data)
            try validateContract(recipe)
            return recipe
        } catch let error as PDFOperationError {
            throw error
        } catch {
            throw PDFOperationError.invalidInput("Recipe JSON is invalid: \(error.localizedDescription)")
        }
    }

    public static func encodedStarterRecipe(pretty: Bool = true) throws -> Data {
        try encode(.starter, pretty: pretty)
    }

    public static func encode(_ recipe: PDFRecipe, pretty: Bool = true) throws -> Data {
        try validateContract(recipe)
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
        return try encoder.encode(recipe)
    }

    public static func validate(_ recipe: PDFRecipe) throws {
        try validateContract(recipe)
    }

    public static func run(_ recipe: PDFRecipe, on sourceData: Data, dryRun: Bool = false) throws -> PDFRecipeRunResult {
        try validateContract(recipe)
        guard var document = PDFDocument(data: sourceData), document.pageCount > 0 else {
            throw PDFOperationError.invalidInput("Input is not a readable PDF")
        }
        let inputPageCount = document.pageCount
        var stepReports: [PDFRecipeStepReport] = []

        for (offset, step) in recipe.steps.enumerated() {
            do {
                switch step {
                case .renameField(let source, let destination):
                    try PDFOperations.renameFormField(named: source, to: destination, in: document)
                case .fillForm(let values):
                    guard !values.isEmpty else {
                        throw PDFOperationError.invalidInput("fillForm values cannot be empty")
                    }
                    for (name, value) in values.sorted(by: { $0.key < $1.key }) {
                        try PDFOperations.applyFormValue(value, named: name, in: document)
                    }
                case .rotate(let pages, let degrees):
                    let indices = try PDFPageSelection.parse(pages, pageCount: document.pageCount)
                    try PDFOperations.rotate(document, pageIndices: indices, degrees: degrees)
                case .crop(let pages, let insets):
                    let indices = try PDFPageSelection.parse(pages, pageCount: document.pageCount)
                    try PDFOperations.crop(document, pageIndices: indices, insets: insets)
                case .extract(let pages):
                    let indices = try PDFPageSelection.parse(pages, pageCount: document.pageCount)
                    document = try PDFOperations.extract(document, pageIndices: indices)
                case .duplicatePages(let pages):
                    let indices = try PDFPageSelection.parse(pages, pageCount: document.pageCount)
                    try PDFOperations.duplicatePages(document, pageIndices: indices)
                case .deletePages(let pages):
                    let indices = try PDFPageSelection.parse(pages, pageCount: document.pageCount)
                    try PDFOperations.deletePages(document, pageIndices: indices)
                case .ocr(let pages, let configuration):
                    let indices = try PDFPageSelection.parse(pages, pageCount: document.pageCount)
                    guard let data = document.dataRepresentation() else {
                        throw PDFOperationError.operationFailed("Could not serialize the PDF before OCR")
                    }
                    let result = try PDFOperations.makeSearchable(
                        data: data,
                        pageIndices: indices,
                        configuration: configuration
                    )
                    guard let processed = PDFDocument(data: result.data) else {
                        throw PDFOperationError.operationFailed("Could not reopen the OCR result")
                    }
                    document = processed
                case .assertPageCount(let minimum, let maximum):
                    try Self.assertPageCount(document.pageCount, minimum: minimum, maximum: maximum)
                case .assertText(let contains, let excludes):
                    try Self.assertText(document.string ?? "", contains: contains, excludes: excludes)
                case .assertFields(let names):
                    try Self.assertFields(names, document: document)
                case .assertFormGate(let maximum):
                    try Self.assertFormGate(maximum, document: document)
                case .assertSafeShare(let maximum):
                    try Self.assertSafeShare(maximum, document: document)
                }
                stepReports.append(Self.stepReport(step, index: offset + 1, document: document))
            } catch {
                throw PDFOperationError.operationFailed(
                    "Recipe step \(offset + 1) (\(step.operation)) failed: \(Self.message(for: error))"
                )
            }
        }

        guard let staged = document.dataRepresentation() else {
            throw PDFOperationError.operationFailed("Recipe output could not be serialized")
        }
        let stagedForm = PDFOperations.formReport(for: document)
        let outputData: Data
        let formGate: PDFFormGateReport?
        if stagedForm.widgetCount > 0 {
            let normalized = try PDFOperations.normalizeFormData(staged)
            let gate = PDFOperations.formGate(for: normalized.report)
            guard gate.canSave else {
                throw PDFOperationError.operationFailed("Form Gate stopped the recipe output")
            }
            outputData = normalized.data
            formGate = gate
        } else {
            outputData = staged
            formGate = nil
        }
        guard let reopened = PDFDocument(data: outputData), reopened.pageCount == document.pageCount else {
            throw PDFOperationError.operationFailed("Recipe output failed PDF round-trip verification")
        }
        let report = PDFRecipeReport(
            recipe: recipe.name,
            version: recipe.version,
            dryRun: dryRun,
            inputPageCount: inputPageCount,
            outputPageCount: reopened.pageCount,
            steps: stepReports,
            formGate: formGate
        )
        return PDFRecipeRunResult(data: outputData, report: report)
    }

    private static func validateContract(_ recipe: PDFRecipe) throws {
        guard (1...PDFRecipe.latestVersion).contains(recipe.version) else {
            throw PDFOperationError.invalidInput(
                "Unsupported recipe version \(recipe.version); expected versions 1...\(PDFRecipe.latestVersion)"
            )
        }
        guard !recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PDFOperationError.invalidInput("Recipe name cannot be empty")
        }
        guard !recipe.steps.isEmpty else { throw PDFOperationError.invalidInput("Recipe must contain at least one step") }
        guard recipe.steps.count <= 100 else { throw PDFOperationError.invalidInput("Recipe cannot exceed 100 steps") }
        for (offset, step) in recipe.steps.enumerated() {
            do {
                guard recipe.version >= step.minimumRecipeVersion else {
                    throw PDFOperationError.invalidInput(
                        "\(step.operation) requires recipe version \(step.minimumRecipeVersion)"
                    )
                }
                try validateStepContract(step)
            } catch {
                throw PDFOperationError.invalidInput(
                    "Recipe step \(offset + 1) (\(step.operation)) is invalid: \(message(for: error))"
                )
            }
        }
    }

    private static func validateStepContract(_ step: PDFRecipeStep) throws {
        let trimmed: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch step {
        case .renameField(let source, let destination):
            guard !trimmed(source).isEmpty, !trimmed(destination).isEmpty else {
                throw PDFOperationError.invalidInput("Both field names are required")
            }
        case .fillForm(let values):
            guard !values.isEmpty, values.keys.allSatisfy({ !trimmed($0).isEmpty }) else {
                throw PDFOperationError.invalidInput("fillForm requires at least one named field")
            }
        case .rotate(let pages, let degrees):
            guard !trimmed(pages).isEmpty else { throw PDFOperationError.invalidInput("Page selection cannot be empty") }
            guard degrees.isMultiple(of: 90) else {
                throw PDFOperationError.invalidInput("Rotation must be a multiple of 90 degrees")
            }
        case .crop(let pages, let insets):
            guard !trimmed(pages).isEmpty else { throw PDFOperationError.invalidInput("Page selection cannot be empty") }
            let values = [insets.top, insets.right, insets.bottom, insets.left]
            guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                throw PDFOperationError.invalidInput("Crop insets must be finite and non-negative")
            }
        case .extract(let pages):
            guard !trimmed(pages).isEmpty else { throw PDFOperationError.invalidInput("Page selection cannot be empty") }
        case .duplicatePages(let pages), .deletePages(let pages):
            guard !trimmed(pages).isEmpty else { throw PDFOperationError.invalidInput("Page selection cannot be empty") }
        case .ocr(let pages, let configuration):
            guard !trimmed(pages).isEmpty else { throw PDFOperationError.invalidInput("Page selection cannot be empty") }
            guard configuration.renderDPI.isFinite, (72...400).contains(configuration.renderDPI) else {
                throw PDFOperationError.invalidInput("OCR DPI must be between 72 and 400")
            }
        case .assertPageCount(let minimum, let maximum):
            guard minimum != nil || maximum != nil else {
                throw PDFOperationError.invalidInput("assertPageCount requires minimum, maximum, or both")
            }
            guard minimum.map({ $0 >= 0 }) ?? true, maximum.map({ $0 >= 0 }) ?? true else {
                throw PDFOperationError.invalidInput("Page bounds cannot be negative")
            }
            guard minimum == nil || maximum == nil || minimum! <= maximum! else {
                throw PDFOperationError.invalidInput("Page minimum cannot exceed maximum")
            }
        case .assertText(let contains, let excludes):
            let terms = (contains + excludes).map(trimmed).filter { !$0.isEmpty }
            guard !terms.isEmpty else {
                throw PDFOperationError.invalidInput("assertText requires contains, excludes, or both")
            }
        case .assertFields(let names):
            guard names.contains(where: { !trimmed($0).isEmpty }) else {
                throw PDFOperationError.invalidInput("assertFields requires at least one name")
            }
        case .assertFormGate, .assertSafeShare:
            break
        }
    }

    private static func assertPageCount(_ count: Int, minimum: Int?, maximum: Int?) throws {
        guard minimum != nil || maximum != nil else {
            throw PDFOperationError.invalidInput("assertPageCount requires minimum, maximum, or both")
        }
        if let minimum, minimum < 0 { throw PDFOperationError.invalidInput("Page minimum cannot be negative") }
        if let maximum, maximum < 0 { throw PDFOperationError.invalidInput("Page maximum cannot be negative") }
        if let minimum, let maximum, minimum > maximum {
            throw PDFOperationError.invalidInput("Page minimum cannot exceed maximum")
        }
        if let minimum, count < minimum {
            throw PDFOperationError.operationFailed("Expected at least \(minimum) pages; found \(count)")
        }
        if let maximum, count > maximum {
            throw PDFOperationError.operationFailed("Expected at most \(maximum) pages; found \(count)")
        }
    }

    private static func assertText(_ text: String, contains: [String], excludes: [String]) throws {
        let required = contains.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let forbidden = excludes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !required.isEmpty || !forbidden.isEmpty else {
            throw PDFOperationError.invalidInput("assertText requires contains, excludes, or both")
        }
        let missing = required.filter { !text.localizedCaseInsensitiveContains($0) }
        guard missing.isEmpty else {
            throw PDFOperationError.operationFailed("Required text not found: \(missing.joined(separator: ", "))")
        }
        let present = forbidden.filter { text.localizedCaseInsensitiveContains($0) }
        guard present.isEmpty else {
            throw PDFOperationError.operationFailed("Forbidden text is present: \(present.joined(separator: ", "))")
        }
    }

    private static func assertFields(_ names: [String], document: PDFDocument) throws {
        let expected = Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        guard !expected.isEmpty else { throw PDFOperationError.invalidInput("assertFields requires at least one name") }
        let actual = Set(PDFOperations.formReport(for: document).fields.map(\.name))
        let missing = expected.subtracting(actual).sorted()
        guard missing.isEmpty else {
            throw PDFOperationError.operationFailed("Required form fields not found: \(missing.joined(separator: ", "))")
        }
    }

    private static func assertFormGate(_ maximum: PDFFormGateLevel, document: PDFDocument) throws {
        let report = PDFOperations.formReport(for: document)
        guard report.widgetCount > 0 else {
            throw PDFOperationError.operationFailed("Form Gate assertion requires an interactive form")
        }
        let gate = PDFOperations.formGate(for: report)
        guard gate.level <= maximum else {
            throw PDFOperationError.operationFailed("Form Gate is \(gate.level.rawValue); required \(maximum.rawValue) or better")
        }
    }

    private static func assertSafeShare(_ maximum: PDFSafetyGateLevel, document: PDFDocument) throws {
        let report = PDFOperations.safeShareAudit(for: document)
        guard report.level <= maximum else {
            throw PDFOperationError.operationFailed(
                "Safe Share is \(report.level.rawValue); required \(maximum.rawValue) or better"
            )
        }
    }

    private static func stepReport(_ step: PDFRecipeStep, index: Int, document: PDFDocument) -> PDFRecipeStepReport {
        let widgets = PDFOperations.formReport(for: document).widgetCount
        return PDFRecipeStepReport(
            index: index,
            operation: step.operation,
            summary: step.summary,
            pageCount: document.pageCount,
            widgetCount: widgets
        )
    }

    private static func message(for error: Error) -> String {
        (error as? PDFOperationError)?.description ?? error.localizedDescription
    }
}
