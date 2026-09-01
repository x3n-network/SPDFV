import Foundation
import PDFKit

public struct PDFRecipeStepReport: Codable, Equatable, Sendable, Identifiable {
    public let index: Int
    public let operation: String
    public let summary: String
    public let pageCount: Int
    public let widgetCount: Int
    public let skipped: Bool

    public var id: Int { index }

    public init(index: Int, operation: String, summary: String, pageCount: Int, widgetCount: Int, skipped: Bool = false) {
        self.index = index
        self.operation = operation
        self.summary = summary
        self.pageCount = pageCount
        self.widgetCount = widgetCount
        self.skipped = skipped
    }

    private enum CodingKeys: String, CodingKey { case index, operation, summary, pageCount, widgetCount, skipped }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            index: try container.decode(Int.self, forKey: .index),
            operation: try container.decode(String.self, forKey: .operation),
            summary: try container.decode(String.self, forKey: .summary),
            pageCount: try container.decode(Int.self, forKey: .pageCount),
            widgetCount: try container.decode(Int.self, forKey: .widgetCount),
            skipped: try container.decodeIfPresent(Bool.self, forKey: .skipped) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(operation, forKey: .operation)
        try container.encode(summary, forKey: .summary)
        try container.encode(pageCount, forKey: .pageCount)
        try container.encode(widgetCount, forKey: .widgetCount)
        if skipped { try container.encode(true, forKey: .skipped) }
    }
}

public struct PDFRecipeReport: Codable, Equatable, Sendable {
    public let recipe: String
    public let version: Int
    public let dryRun: Bool
    public let inputPageCount: Int
    public let outputPageCount: Int
    public let steps: [PDFRecipeStepReport]
    public let formGate: PDFFormGateReport?
    public let suggestedOutputName: String?
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

    public static func suggestedOutputName(
        for recipe: PDFRecipe,
        context: PDFRecipeExecutionContext = PDFRecipeExecutionContext()
    ) throws -> String? {
        try validateContract(recipe)
        return try suggestedOutputName(recipe: recipe, variables: resolvedVariables(recipe: recipe, context: context))
    }

    public static func run(
        _ recipe: PDFRecipe,
        on sourceData: Data,
        dryRun: Bool = false,
        context: PDFRecipeExecutionContext = PDFRecipeExecutionContext()
    ) throws -> PDFRecipeRunResult {
        try validateContract(recipe)
        let variables = try resolvedVariables(recipe: recipe, context: context)
        guard var document = PDFDocument(data: sourceData), document.pageCount > 0 else {
            throw PDFOperationError.invalidInput("Input is not a readable PDF")
        }
        let inputPageCount = document.pageCount
        var stepReports: [PDFRecipeStepReport] = []

        for (offset, step) in recipe.steps.enumerated() {
            do {
                let resolved = try resolve(step: step, variables: variables)
                let skipped = try execute(
                    resolved,
                    document: &document,
                    variables: variables,
                    context: context
                )
                stepReports.append(Self.stepReport(resolved, index: offset + 1, document: document, skipped: skipped))
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
            formGate: formGate,
            suggestedOutputName: try suggestedOutputName(recipe: recipe, variables: variables)
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
        let parameterNames = recipe.parameters.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parameterNames.allSatisfy({ !$0.isEmpty }) else {
            throw PDFOperationError.invalidInput("Recipe parameter names cannot be empty")
        }
        guard Set(parameterNames).count == parameterNames.count else {
            throw PDFOperationError.invalidInput("Recipe parameter names must be unique")
        }
        let undeclaredConditions = conditionalParameterNames(recipe.steps).subtracting(Set(parameterNames)).sorted()
        guard undeclaredConditions.isEmpty else {
            throw PDFOperationError.invalidInput(
                "Conditional parameter\(undeclaredConditions.count == 1 ? " is" : "s are") not declared: \(undeclaredConditions.joined(separator: ", "))"
            )
        }
        if !recipe.parameters.isEmpty || recipe.outputNameTemplate != nil {
            guard recipe.version >= 3 else {
                throw PDFOperationError.invalidInput("Parameters and outputNameTemplate require recipe version 3")
            }
        }
        if let template = recipe.outputNameTemplate,
           template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PDFOperationError.invalidInput("outputNameTemplate cannot be empty")
        }
        guard !recipe.steps.isEmpty else { throw PDFOperationError.invalidInput("Recipe must contain at least one step") }
        guard flattenedStepCount(recipe.steps) <= 100 else { throw PDFOperationError.invalidInput("Recipe cannot exceed 100 total steps") }
        for (offset, step) in recipe.steps.enumerated() {
            do {
                guard recipe.version >= step.minimumRecipeVersion else {
                    throw PDFOperationError.invalidInput(
                        "\(step.operation) requires recipe version \(step.minimumRecipeVersion)"
                    )
                }
                try validateStepContract(step, depth: 0)
            } catch {
                throw PDFOperationError.invalidInput(
                    "Recipe step \(offset + 1) (\(step.operation)) is invalid: \(message(for: error))"
                )
            }
        }
    }

    private static func validateStepContract(_ step: PDFRecipeStep, depth: Int) throws {
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
        case .assertFormGate, .assertSafeShare, .assertDoctor:
            break
        case .importFormData(let source):
            guard !trimmed(source).isEmpty else { throw PDFOperationError.invalidInput("Form-data source is required") }
        case .assertCompare(let reference, let maximum, let options):
            guard !trimmed(reference).isEmpty else { throw PDFOperationError.invalidInput("Comparison reference is required") }
            guard maximum >= 0 else { throw PDFOperationError.invalidInput("maximumChangedPages cannot be negative") }
            guard options.minimumAppearanceSimilarity.isFinite else {
                throw PDFOperationError.invalidInput("Comparison similarity must be finite")
            }
        case .ifParameter(let name, _, let steps):
            guard depth < 5 else { throw PDFOperationError.invalidInput("Conditional nesting cannot exceed five levels") }
            guard !trimmed(name).isEmpty else { throw PDFOperationError.invalidInput("Conditional parameter name is required") }
            guard !steps.isEmpty else { throw PDFOperationError.invalidInput("Conditional steps cannot be empty") }
            for nested in steps {
                guard nested.minimumRecipeVersion <= 3 else {
                    throw PDFOperationError.invalidInput("Unsupported nested recipe operation")
                }
                try validateStepContract(nested, depth: depth + 1)
            }
        }
    }

    private static func flattenedStepCount(_ steps: [PDFRecipeStep]) -> Int {
        steps.reduce(0) { count, step in
            if case .ifParameter(_, _, let nested) = step {
                return count + 1 + flattenedStepCount(nested)
            }
            return count + 1
        }
    }

    private static func conditionalParameterNames(_ steps: [PDFRecipeStep]) -> Set<String> {
        steps.reduce(into: Set<String>()) { names, step in
            if case .ifParameter(let name, _, let nested) = step {
                names.insert(name.trimmingCharacters(in: .whitespacesAndNewlines))
                names.formUnion(conditionalParameterNames(nested))
            }
        }
    }

    private static func resolvedVariables(
        recipe: PDFRecipe,
        context: PDFRecipeExecutionContext
    ) throws -> [String: String] {
        let declared = Set(recipe.parameters.map(\.name))
        let unknown = Set(context.parameters.keys).subtracting(declared).sorted()
        guard unknown.isEmpty else {
            throw PDFOperationError.invalidInput("Unknown recipe parameter\(unknown.count == 1 ? "" : "s"): \(unknown.joined(separator: ", "))")
        }
        var values: [String: String] = [:]
        for parameter in recipe.parameters {
            if let supplied = context.parameters[parameter.name] {
                values[parameter.name] = supplied
            } else if let fallback = parameter.defaultValue {
                values[parameter.name] = fallback
            } else if parameter.required {
                throw PDFOperationError.invalidInput("Missing required recipe parameter: \(parameter.name)")
            } else {
                values[parameter.name] = ""
            }
        }
        values["recipeName"] = recipe.name
        if let inputName = context.inputName {
            values["inputName"] = URL(fileURLWithPath: inputName).deletingPathExtension().lastPathComponent
        } else {
            values["inputName"] = "output"
        }
        return values
    }

    private static func resolve(_ value: String, variables: [String: String]) throws -> String {
        var result = value
        for (name, replacement) in variables {
            result = result.replacingOccurrences(of: "{{\(name)}}", with: replacement)
        }
        let expression = try NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#)
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        if let match = expression.firstMatch(in: result, range: range),
           let nameRange = Range(match.range(at: 1), in: result) {
            throw PDFOperationError.invalidInput("Unknown recipe variable: \(result[nameRange])")
        }
        return result
    }

    private static func resolve(step: PDFRecipeStep, variables: [String: String]) throws -> PDFRecipeStep {
        switch step {
        case .renameField(let source, let destination):
            return .renameField(from: try resolve(source, variables: variables), to: try resolve(destination, variables: variables))
        case .fillForm(let values):
            var resolvedValues: [String: String] = [:]
            for (name, value) in values {
                let resolvedName = try resolve(name, variables: variables)
                guard resolvedValues[resolvedName] == nil else {
                    throw PDFOperationError.invalidInput("Variable substitution produced duplicate field name: \(resolvedName)")
                }
                resolvedValues[resolvedName] = try resolve(value, variables: variables)
            }
            return .fillForm(values: resolvedValues)
        case .rotate(let pages, let degrees): return .rotate(pages: try resolve(pages, variables: variables), degrees: degrees)
        case .crop(let pages, let insets): return .crop(pages: try resolve(pages, variables: variables), insets: insets)
        case .extract(let pages): return .extract(pages: try resolve(pages, variables: variables))
        case .duplicatePages(let pages): return .duplicatePages(pages: try resolve(pages, variables: variables))
        case .deletePages(let pages): return .deletePages(pages: try resolve(pages, variables: variables))
        case .ocr(let pages, let configuration): return .ocr(pages: try resolve(pages, variables: variables), configuration: configuration)
        case .assertPageCount: return step
        case .assertText(let contains, let excludes):
            return .assertText(
                contains: try contains.map { try resolve($0, variables: variables) },
                excludes: try excludes.map { try resolve($0, variables: variables) }
            )
        case .assertFields(let names): return .assertFields(names: try names.map { try resolve($0, variables: variables) })
        case .assertFormGate, .assertSafeShare, .assertDoctor: return step
        case .importFormData(let source): return .importFormData(source: try resolve(source, variables: variables))
        case .assertCompare(let reference, let maximum, let options):
            return .assertCompare(reference: try resolve(reference, variables: variables), maximumChangedPages: maximum, options: options)
        case .ifParameter(let name, let expected, let steps):
            return .ifParameter(
                name: try resolve(name, variables: variables),
                equals: try resolve(expected, variables: variables),
                steps: try steps.map { try resolve(step: $0, variables: variables) }
            )
        }
    }

    /// Executes one resolved step and returns whether it was skipped.
    private static func execute(
        _ step: PDFRecipeStep,
        document: inout PDFDocument,
        variables: [String: String],
        context: PDFRecipeExecutionContext
    ) throws -> Bool {
        switch step {
        case .renameField(let source, let destination):
            try PDFOperations.renameFormField(named: source, to: destination, in: document)
        case .fillForm(let values):
            for (name, value) in values.sorted(by: { $0.key < $1.key }) {
                try PDFOperations.applyFormValue(value, named: name, in: document)
            }
        case .rotate(let pages, let degrees):
            try PDFOperations.rotate(document, pageIndices: PDFPageSelection.parse(pages, pageCount: document.pageCount), degrees: degrees)
        case .crop(let pages, let insets):
            try PDFOperations.crop(document, pageIndices: PDFPageSelection.parse(pages, pageCount: document.pageCount), insets: insets)
        case .extract(let pages):
            document = try PDFOperations.extract(document, pageIndices: PDFPageSelection.parse(pages, pageCount: document.pageCount))
        case .duplicatePages(let pages):
            try PDFOperations.duplicatePages(document, pageIndices: PDFPageSelection.parse(pages, pageCount: document.pageCount))
        case .deletePages(let pages):
            try PDFOperations.deletePages(document, pageIndices: PDFPageSelection.parse(pages, pageCount: document.pageCount))
        case .ocr(let pages, let configuration):
            guard let data = document.dataRepresentation() else {
                throw PDFOperationError.operationFailed("Could not serialize the PDF before OCR")
            }
            let result = try PDFOperations.makeSearchable(
                data: data,
                pageIndices: PDFPageSelection.parse(pages, pageCount: document.pageCount),
                configuration: configuration
            )
            guard let processed = PDFDocument(data: result.data) else {
                throw PDFOperationError.operationFailed("Could not reopen the OCR result")
            }
            document = processed
        case .assertPageCount(let minimum, let maximum):
            try assertPageCount(document.pageCount, minimum: minimum, maximum: maximum)
        case .assertText(let contains, let excludes):
            try assertText(document.string ?? "", contains: contains, excludes: excludes)
        case .assertFields(let names): try assertFields(names, document: document)
        case .assertFormGate(let maximum): try assertFormGate(maximum, document: document)
        case .assertSafeShare(let maximum): try assertSafeShare(maximum, document: document)
        case .importFormData(let source):
            guard let file = context.formData[source] else {
                throw PDFOperationError.invalidInput("Missing recipe form-data source: \(source)")
            }
            try PDFOperations.applyFormData(file, to: document)
        case .assertCompare(let reference, let maximum, let options):
            guard let data = context.references[reference], let referenceDocument = PDFDocument(data: data) else {
                throw PDFOperationError.invalidInput("Missing or unreadable recipe reference: \(reference)")
            }
            let report = try PDFOperations.compare(reference: referenceDocument, candidate: document, options: options)
            let changed = report.changedPages + report.addedPages + report.removedPages
            guard changed <= maximum else {
                throw PDFOperationError.operationFailed("Comparison found \(changed) changed page\(changed == 1 ? "" : "s"); maximum is \(maximum)")
            }
        case .assertDoctor(let maximum):
            let report = PDFOperations.diagnose(document)
            guard report.level <= maximum else {
                throw PDFOperationError.operationFailed("Doctor is \(report.level.rawValue); required \(maximum.rawValue) or better")
            }
        case .ifParameter(let name, let expected, let steps):
            guard variables[name] == expected else { return true }
            for (offset, nested) in steps.enumerated() {
                do {
                    _ = try execute(nested, document: &document, variables: variables, context: context)
                } catch {
                    throw PDFOperationError.operationFailed(
                        "Conditional step \(offset + 1) (\(nested.operation)) failed: \(message(for: error))"
                    )
                }
            }
        }
        return false
    }

    private static func suggestedOutputName(recipe: PDFRecipe, variables: [String: String]) throws -> String? {
        guard let template = recipe.outputNameTemplate else { return nil }
        var name = try resolve(template, variables: variables)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        name = name.components(separatedBy: invalid).joined(separator: "-")
        while name.contains("--") { name = name.replacingOccurrences(of: "--", with: "-") }
        guard !name.isEmpty, name != ".pdf" else {
            throw PDFOperationError.invalidInput("outputNameTemplate resolves to an empty filename")
        }
        if !name.lowercased().hasSuffix(".pdf") { name += ".pdf" }
        return name
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

    private static func stepReport(
        _ step: PDFRecipeStep,
        index: Int,
        document: PDFDocument,
        skipped: Bool = false
    ) -> PDFRecipeStepReport {
        let widgets = PDFOperations.formReport(for: document).widgetCount
        return PDFRecipeStepReport(
            index: index,
            operation: step.operation,
            summary: step.summary,
            pageCount: document.pageCount,
            widgetCount: widgets,
            skipped: skipped
        )
    }

    private static func message(for error: Error) -> String {
        (error as? PDFOperationError)?.description ?? error.localizedDescription
    }
}
