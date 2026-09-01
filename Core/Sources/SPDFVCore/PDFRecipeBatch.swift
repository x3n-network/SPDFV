import Foundation

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
        dryRun: Bool = false,
        context: PDFRecipeExecutionContext = PDFRecipeExecutionContext()
    ) -> PDFRecipeBatchRunResult {
        var items: [PDFRecipeBatchItemReport] = []
        var outputs: [PDFRecipeBatchOutput] = []
        var outputNames: Set<String> = []
        for input in inputs {
            do {
                let itemContext = PDFRecipeExecutionContext(
                    parameters: context.parameters,
                    references: context.references,
                    formData: context.formData,
                    inputName: input.name
                )
                let result = try PDFRecipeRunner.run(recipe, on: input.data, dryRun: dryRun, context: itemContext)
                let outputName = result.report.suggestedOutputName ?? input.name
                guard outputNames.insert(outputName.lowercased()).inserted else {
                    throw PDFOperationError.invalidInput("Output naming template produced a duplicate filename: \(outputName)")
                }
                items.append(PDFRecipeBatchItemReport(name: input.name, status: .passed, error: nil, report: result.report))
                if !dryRun { outputs.append(PDFRecipeBatchOutput(name: outputName, data: result.data)) }
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
