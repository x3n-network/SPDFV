import Foundation
import SPDFVCore

func recipeTemplate(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: [])
    guard parser.positional.isEmpty else { throw CLIError.usage("recipe-template does not accept positional arguments") }
    print(String(decoding: try PDFRecipeRunner.encodedStarterRecipe(pretty: true), as: UTF8.self))
}

func validateRecipe(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: recipeContextOptions.union(["--recipe"]))
    guard parser.positional.count == 1 else {
        throw CLIError.usage("validate-recipe requires exactly one input PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let recipeURL = fileURL(try parser.requireOption("--recipe"))
    let recipe = try PDFRecipeRunner.decode(Data(contentsOf: recipeURL))
    let context = try recipeContext(parser, inputName: inputURL.lastPathComponent)
    let result = try PDFRecipeRunner.run(recipe, on: Data(contentsOf: inputURL), dryRun: true, context: context)
    print(try encode(
        RecipeOperationReport(
            operation: "validate-recipe",
            input: inputURL.path,
            recipe: recipeURL.path,
            output: nil,
            report: result.report
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

func runRecipe(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: recipeContextOptions.union(["--recipe", "--output", "--output-dir"]))
    guard parser.positional.count == 1 else {
        throw CLIError.usage("run-recipe requires exactly one input PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let recipeURL = fileURL(try parser.requireOption("--recipe"))
    let recipe = try PDFRecipeRunner.decode(Data(contentsOf: recipeURL))
    let context = try recipeContext(parser, inputName: inputURL.lastPathComponent)
    let result = try PDFRecipeRunner.run(recipe, on: Data(contentsOf: inputURL), context: context)
    let outputURL: URL
    if let explicit = parser.options["--output"] {
        outputURL = fileURL(explicit)
    } else if let directory = parser.options["--output-dir"], let suggested = result.report.suggestedOutputName {
        outputURL = fileURL(directory).appendingPathComponent(suggested)
    } else {
        throw CLIError.usage("run-recipe requires --output, or --output-dir with a v3 outputNameTemplate")
    }
    if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
        throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
    }
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try result.data.write(to: outputURL, options: .atomic)
    print(try encode(
        RecipeOperationReport(
            operation: "run-recipe",
            input: inputURL.path,
            recipe: recipeURL.path,
            output: outputURL.path,
            report: result.report
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

func batchRecipe(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: recipeContextOptions.union(["--recipe", "--output-dir"]))
    guard parser.positional.count == 1 else {
        throw CLIError.usage("batch-recipe requires exactly one input directory")
    }
    let inputDirectory = fileURL(parser.positional[0])
    let recipeURL = fileURL(try parser.requireOption("--recipe"))
    let dryRun = parser.flags.contains("--dry-run")
    let outputDirectory = parser.options["--output-dir"].map(fileURL)
    if !dryRun, outputDirectory == nil {
        throw CLIError.usage("batch-recipe requires --output-dir unless --dry-run is used")
    }
    if let outputDirectory, outputDirectory == inputDirectory {
        throw CLIError.failure("Input and output directories must be different")
    }

    let inputURLs = try FileManager.default.contentsOfDirectory(
        at: inputDirectory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )
        .filter { $0.pathExtension.lowercased() == "pdf" }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    guard !inputURLs.isEmpty else { throw CLIError.failure("Input directory contains no PDF files") }

    let recipe = try PDFRecipeRunner.decode(Data(contentsOf: recipeURL))
    let inputs = try inputURLs.map {
        PDFRecipeBatchInput(name: $0.lastPathComponent, data: try Data(contentsOf: $0))
    }
    let context = try recipeContext(parser, inputName: nil)
    let result = PDFRecipeBatchRunner.run(recipe, inputs: inputs, dryRun: dryRun, context: context)
    let manifestURL = outputDirectory?.appendingPathComponent("spdfv-batch-manifest.json")
    let operationReport = BatchRecipeOperationReport(
        operation: "batch-recipe",
        inputDirectory: inputDirectory.path,
        recipe: recipeURL.path,
        outputDirectory: outputDirectory?.path,
        manifest: dryRun ? nil : manifestURL?.path,
        report: result.report
    )

    if !dryRun, let outputDirectory, let manifestURL {
        let destinations = result.outputs.map { outputDirectory.appendingPathComponent($0.name) } + [manifestURL]
        if !parser.flags.contains("--force"), let collision = destinations.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            throw CLIError.failure("Batch output already exists; pass --force to replace it: \(collision.path)")
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for output in result.outputs {
            try output.data.write(to: outputDirectory.appendingPathComponent(output.name), options: .atomic)
        }
        guard let manifestData = try encode(operationReport, pretty: true).data(using: .utf8) else {
            throw CLIError.failure("Batch manifest could not be encoded")
        }
        try manifestData.write(to: manifestURL, options: .atomic)
    }

    print(try encode(operationReport, pretty: parser.flags.contains("--pretty")))
    if result.report.failedCount > 0 {
        throw CLIError.failure("Batch completed with \(result.report.failedCount) failed PDF\(result.report.failedCount == 1 ? "" : "s")")
    }
}

private let recipeContextOptions: Set<String> = ["--parameters", "--references", "--form-data"]

private func recipeContext(_ parser: OptionParser, inputName: String?) throws -> PDFRecipeExecutionContext {
    let parameters = try stringMap(parser.options["--parameters"], option: "--parameters")
    let referencePaths = try stringMap(parser.options["--references"], option: "--references")
    let formDataPaths = try stringMap(parser.options["--form-data"], option: "--form-data")
    var references: [String: Data] = [:]
    for (name, path) in referencePaths { references[name] = try Data(contentsOf: fileURL(path)) }
    var formData: [String: PDFFormDataFile] = [:]
    for (name, path) in formDataPaths {
        formData[name] = try PDFOperations.decodeFormData(Data(contentsOf: fileURL(path)))
    }
    return PDFRecipeExecutionContext(
        parameters: parameters,
        references: references,
        formData: formData,
        inputName: inputName
    )
}

private func stringMap(_ json: String?, option: String) throws -> [String: String] {
    guard let json else { return [:] }
    do {
        return try JSONDecoder().decode([String: String].self, from: Data(json.utf8))
    } catch {
        throw CLIError.usage("\(option) must be a JSON object whose keys and values are strings")
    }
}
