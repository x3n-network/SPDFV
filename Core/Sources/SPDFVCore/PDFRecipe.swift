import Foundation
import PDFKit

public struct PDFRecipe: Codable, Equatable, Sendable {
    public static let latestVersion = 2

    public let version: Int
    public let name: String
    public let steps: [PDFRecipeStep]

    public init(version: Int = 1, name: String, steps: [PDFRecipeStep]) {
        self.version = version
        self.name = name
        self.steps = steps
    }

    public static let starter = PDFRecipe(
        name: "Verified proof copy",
        steps: [
            .assertPageCount(minimum: 1, maximum: nil),
            .rotate(pages: "all", degrees: 0),
            .crop(pages: "all", insets: .zero),
            .extract(pages: "all")
        ]
    )
}

public enum PDFRecipeStep: Equatable, Sendable {
    case renameField(from: String, to: String)
    case fillForm(values: [String: String])
    case rotate(pages: String, degrees: Int)
    case crop(pages: String, insets: PDFEdgeInsets)
    case extract(pages: String)
    case duplicatePages(pages: String)
    case deletePages(pages: String)
    case ocr(pages: String, configuration: PDFOCRConfiguration)
    case assertPageCount(minimum: Int?, maximum: Int?)
    case assertText(contains: [String], excludes: [String])
    case assertFields(names: [String])
    case assertFormGate(maximum: PDFFormGateLevel)
    case assertSafeShare(maximum: PDFSafetyGateLevel)

    public var operation: String {
        switch self {
        case .renameField: "renameField"
        case .fillForm: "fillForm"
        case .rotate: "rotate"
        case .crop: "crop"
        case .extract: "extract"
        case .duplicatePages: "duplicatePages"
        case .deletePages: "deletePages"
        case .ocr: "ocr"
        case .assertPageCount: "assertPageCount"
        case .assertText: "assertText"
        case .assertFields: "assertFields"
        case .assertFormGate: "assertFormGate"
        case .assertSafeShare: "assertSafeShare"
        }
    }

    public var summary: String {
        switch self {
        case .renameField(let source, let destination): "Rename \(source) to \(destination)"
        case .fillForm(let values): "Fill \(values.count) field\(values.count == 1 ? "" : "s")"
        case .rotate(let pages, let degrees): "Rotate pages \(pages) by \(degrees) degrees"
        case .crop(let pages, let insets):
            "Crop pages \(pages) by \(Self.insetsLabel(insets)) pt"
        case .extract(let pages): "Keep pages \(pages)"
        case .duplicatePages(let pages): "Duplicate pages \(pages)"
        case .deletePages(let pages): "Delete pages \(pages)"
        case .ocr(let pages, let configuration):
            "OCR pages \(pages) at \(Self.number(configuration.renderDPI)) DPI"
        case .assertPageCount(let minimum, let maximum):
            switch (minimum, maximum) {
            case let (minimum?, maximum?): "Require \(minimum)-\(maximum) pages"
            case let (minimum?, nil): "Require at least \(minimum) page\(minimum == 1 ? "" : "s")"
            case let (nil, maximum?): "Require at most \(maximum) page\(maximum == 1 ? "" : "s")"
            case (nil, nil): "Require a valid page count"
            }
        case .assertText(let contains, let excludes):
            "Require \(contains.count) and exclude \(excludes.count) text term\(contains.count + excludes.count == 1 ? "" : "s")"
        case .assertFields(let names): "Require \(names.count) field\(names.count == 1 ? "" : "s")"
        case .assertFormGate(let maximum): "Require Form Gate \(maximum.rawValue) or better"
        case .assertSafeShare(let maximum): "Require Safe Share \(maximum.rawValue) or better"
        }
    }

    public var minimumRecipeVersion: Int {
        switch self {
        case .duplicatePages, .deletePages, .ocr, .assertSafeShare: 2
        default: 1
        }
    }

    private static func insetsLabel(_ insets: PDFEdgeInsets) -> String {
        if insets.top == insets.right, insets.top == insets.bottom, insets.top == insets.left {
            return Self.number(insets.top)
        }
        return [insets.top, insets.right, insets.bottom, insets.left].map(Self.number).joined(separator: ",")
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

extension PDFRecipeStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case operation, from, to, values, pages, degrees, insets, configuration
        case minimum, maximum, contains, excludes, names
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let operation = try container.decode(String.self, forKey: .operation)
        switch operation {
        case "renameField":
            self = .renameField(
                from: try container.decode(String.self, forKey: .from),
                to: try container.decode(String.self, forKey: .to)
            )
        case "fillForm":
            self = .fillForm(values: try container.decode([String: String].self, forKey: .values))
        case "rotate":
            self = .rotate(
                pages: try container.decode(String.self, forKey: .pages),
                degrees: try container.decode(Int.self, forKey: .degrees)
            )
        case "crop":
            self = .crop(
                pages: try container.decode(String.self, forKey: .pages),
                insets: try container.decode(PDFEdgeInsets.self, forKey: .insets)
            )
        case "extract":
            self = .extract(pages: try container.decode(String.self, forKey: .pages))
        case "duplicatePages":
            self = .duplicatePages(pages: try container.decode(String.self, forKey: .pages))
        case "deletePages":
            self = .deletePages(pages: try container.decode(String.self, forKey: .pages))
        case "ocr":
            self = .ocr(
                pages: try container.decode(String.self, forKey: .pages),
                configuration: try container.decode(PDFOCRConfiguration.self, forKey: .configuration)
            )
        case "assertPageCount":
            self = .assertPageCount(
                minimum: try container.decodeIfPresent(Int.self, forKey: .minimum),
                maximum: try container.decodeIfPresent(Int.self, forKey: .maximum)
            )
        case "assertText":
            self = .assertText(
                contains: try container.decodeIfPresent([String].self, forKey: .contains) ?? [],
                excludes: try container.decodeIfPresent([String].self, forKey: .excludes) ?? []
            )
        case "assertFields":
            self = .assertFields(names: try container.decode([String].self, forKey: .names))
        case "assertFormGate":
            self = .assertFormGate(maximum: try container.decode(PDFFormGateLevel.self, forKey: .maximum))
        case "assertSafeShare":
            self = .assertSafeShare(maximum: try container.decode(PDFSafetyGateLevel.self, forKey: .maximum))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .operation,
                in: container,
                debugDescription: "Unsupported recipe operation: \(operation)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operation, forKey: .operation)
        switch self {
        case .renameField(let source, let destination):
            try container.encode(source, forKey: .from)
            try container.encode(destination, forKey: .to)
        case .fillForm(let values):
            try container.encode(values, forKey: .values)
        case .rotate(let pages, let degrees):
            try container.encode(pages, forKey: .pages)
            try container.encode(degrees, forKey: .degrees)
        case .crop(let pages, let insets):
            try container.encode(pages, forKey: .pages)
            try container.encode(insets, forKey: .insets)
        case .extract(let pages):
            try container.encode(pages, forKey: .pages)
        case .duplicatePages(let pages), .deletePages(let pages):
            try container.encode(pages, forKey: .pages)
        case .ocr(let pages, let configuration):
            try container.encode(pages, forKey: .pages)
            try container.encode(configuration, forKey: .configuration)
        case .assertPageCount(let minimum, let maximum):
            try container.encodeIfPresent(minimum, forKey: .minimum)
            try container.encodeIfPresent(maximum, forKey: .maximum)
        case .assertText(let contains, let excludes):
            if !contains.isEmpty { try container.encode(contains, forKey: .contains) }
            if !excludes.isEmpty { try container.encode(excludes, forKey: .excludes) }
        case .assertFields(let names):
            try container.encode(names, forKey: .names)
        case .assertFormGate(let maximum):
            try container.encode(maximum, forKey: .maximum)
        case .assertSafeShare(let maximum):
            try container.encode(maximum, forKey: .maximum)
        }
    }
}

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

public struct PDFRecipeBatchInput: Sendable {
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

public enum PDFRecipeBatchStatus: String, Codable, Equatable, Sendable {
    case passed
    case failed
}

public struct PDFRecipeBatchItemReport: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let status: PDFRecipeBatchStatus
    public let error: String?
    public let report: PDFRecipeReport?

    public var id: String { name }
}

public struct PDFRecipeBatchReport: Codable, Equatable, Sendable {
    public let recipe: String
    public let dryRun: Bool
    public let inputCount: Int
    public let passedCount: Int
    public let failedCount: Int
    public let items: [PDFRecipeBatchItemReport]
}

public struct PDFRecipeBatchOutput: Sendable {
    public let name: String
    public let data: Data
}

public struct PDFRecipeBatchRunResult: Sendable {
    public let report: PDFRecipeBatchReport
    public let outputs: [PDFRecipeBatchOutput]
}

public enum PDFRecipeBatchRunner {
    public static func run(
        _ recipe: PDFRecipe,
        inputs: [PDFRecipeBatchInput],
        dryRun: Bool = false
    ) -> PDFRecipeBatchRunResult {
        var items: [PDFRecipeBatchItemReport] = []
        var outputs: [PDFRecipeBatchOutput] = []
        for input in inputs {
            do {
                let result = try PDFRecipeRunner.run(recipe, on: input.data, dryRun: dryRun)
                items.append(PDFRecipeBatchItemReport(name: input.name, status: .passed, error: nil, report: result.report))
                if !dryRun { outputs.append(PDFRecipeBatchOutput(name: input.name, data: result.data)) }
            } catch {
                let message = (error as? PDFOperationError)?.description ?? error.localizedDescription
                items.append(PDFRecipeBatchItemReport(name: input.name, status: .failed, error: message, report: nil))
            }
        }
        let passed = items.filter { $0.status == .passed }.count
        return PDFRecipeBatchRunResult(
            report: PDFRecipeBatchReport(
                recipe: recipe.name,
                dryRun: dryRun,
                inputCount: inputs.count,
                passedCount: passed,
                failedCount: inputs.count - passed,
                items: items
            ),
            outputs: outputs
        )
    }
}
