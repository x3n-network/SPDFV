import Foundation
import SPDFVCore

func watchOnce(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--recipe", "--output-dir", "--state"])
    guard parser.positional.count == 1 else { throw CLIError.usage("watch-once requires exactly one input directory") }
    let inputDirectory = fileURL(parser.positional[0])
    let outputDirectory = fileURL(try parser.requireOption("--output-dir"))
    let recipeURL = fileURL(try parser.requireOption("--recipe"))
    let stateURL = fileURL(try parser.requireOption("--state"))
    guard inputDirectory != outputDirectory else { throw CLIError.failure("Input and output directories must be different") }
    let recipe = try PDFRecipeRunner.decode(Data(contentsOf: recipeURL))
    var state = FileManager.default.fileExists(atPath: stateURL.path)
        ? try decodeFile(RecipeWatchState.self, at: stateURL)
        : RecipeWatchState()
    var processed = Set(state.processed)
    let inputs = try FileManager.default.contentsOfDirectory(
        at: inputDirectory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )
        .filter { $0.pathExtension.lowercased() == "pdf" }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    var items: [RecipeWatchItemReport] = []

    for inputURL in inputs {
        let name = inputURL.lastPathComponent
        let outputURL = outputDirectory.appendingPathComponent(name)
        if processed.contains(name) || FileManager.default.fileExists(atPath: outputURL.path) {
            items.append(RecipeWatchItemReport(input: inputURL.path, output: outputURL.path, status: "skipped", error: nil))
            continue
        }
        do {
            let result = try PDFRecipeRunner.run(recipe, on: Data(contentsOf: inputURL))
            try result.data.write(to: outputURL, options: .atomic)
            processed.insert(name)
            state.processed = processed.sorted()
            try writeJSONFile(state, to: stateURL)
            items.append(RecipeWatchItemReport(input: inputURL.path, output: outputURL.path, status: "passed", error: nil))
        } catch {
            items.append(RecipeWatchItemReport(input: inputURL.path, output: outputURL.path, status: "failed", error: errorMessage(error)))
        }
    }
    if !FileManager.default.fileExists(atPath: stateURL.path) { try writeJSONFile(state, to: stateURL) }
    let report = RecipeWatchOperationReport(
        operation: "watch-once",
        inputDirectory: inputDirectory.path,
        outputDirectory: outputDirectory.path,
        recipe: recipeURL.path,
        state: stateURL.path,
        discovered: inputs.count,
        passed: items.count { $0.status == "passed" },
        failed: items.count { $0.status == "failed" },
        skipped: items.count { $0.status == "skipped" },
        items: items
    )
    print(try encode(report, pretty: parser.flags.contains("--pretty")))
    if report.failed > 0 { throw CLIError.failure("Watch pass contains \(report.failed) failed PDF\(report.failed == 1 ? "" : "s")") }
}
