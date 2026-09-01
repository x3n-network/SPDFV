import Foundation
import SPDFVCore

private func loadQueue(at url: URL) throws -> PDFRecipeJobQueue {
    guard FileManager.default.fileExists(atPath: url.path) else { return PDFRecipeJobQueue() }
    let queue = try decodeFile(PDFRecipeJobQueue.self, at: url)
    guard queue.version == 1 else { throw CLIError.failure("Unsupported queue version: \(queue.version)") }
    return queue
}

func enqueueRecipe(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--recipe", "--output", "--queue"])
    guard parser.positional.count == 1 else { throw CLIError.usage("enqueue-recipe requires exactly one input PDF") }
    let inputURL = fileURL(parser.positional[0])
    let recipeURL = fileURL(try parser.requireOption("--recipe"))
    let outputURL = fileURL(try parser.requireOption("--output"))
    let queueURL = fileURL(try parser.requireOption("--queue"))
    guard FileManager.default.fileExists(atPath: inputURL.path) else { throw CLIError.failure("Input does not exist: \(inputURL.path)") }
    _ = try PDFRecipeRunner.decode(Data(contentsOf: recipeURL))
    var queue = try loadQueue(at: queueURL)
    let id = try queue.enqueue(inputPath: inputURL.path, recipePath: recipeURL.path, outputPath: outputURL.path)
    try writeJSONFile(queue, to: queueURL)
    print(try encode(
        RecipeQueueOperationReport(
            operation: "enqueue-recipe",
            queue: queueURL.path,
            job: queue.jobs.first { $0.id == id },
            summary: queue.summary,
            jobs: nil
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

func queueStatus(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--queue"])
    guard parser.positional.isEmpty else { throw CLIError.usage("queue-status does not accept positional arguments") }
    let queueURL = fileURL(try parser.requireOption("--queue"))
    let queue = try loadQueue(at: queueURL)
    print(try encode(
        RecipeQueueOperationReport(
            operation: "queue-status",
            queue: queueURL.path,
            job: nil,
            summary: queue.summary,
            jobs: queue.jobs
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

func runQueue(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--queue"])
    guard parser.positional.isEmpty else { throw CLIError.usage("run-queue does not accept positional arguments") }
    let queueURL = fileURL(try parser.requireOption("--queue"))
    var queue = try loadQueue(at: queueURL)
    let pending = queue.prepareForRun()
    try writeJSONFile(queue, to: queueURL)

    for id in pending {
        guard queue.markRunning(id), let job = queue.jobs.first(where: { $0.id == id }) else { continue }
        try writeJSONFile(queue, to: queueURL)
        do {
            let outputURL = fileURL(job.outputPath)
            if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
                throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
            }
            let recipe = try PDFRecipeRunner.decode(Data(contentsOf: fileURL(job.recipePath)))
            let result = try PDFRecipeRunner.run(recipe, on: Data(contentsOf: fileURL(job.inputPath)))
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try result.data.write(to: outputURL, options: .atomic)
            _ = queue.markPassed(id, report: result.report)
        } catch {
            _ = queue.markFailed(id, error: errorMessage(error))
        }
        try writeJSONFile(queue, to: queueURL)
    }

    print(try encode(
        RecipeQueueOperationReport(
            operation: "run-queue",
            queue: queueURL.path,
            job: nil,
            summary: queue.summary,
            jobs: queue.jobs
        ),
        pretty: parser.flags.contains("--pretty")
    ))
    if queue.summary.failed > 0 {
        throw CLIError.failure("Queue contains \(queue.summary.failed) failed job\(queue.summary.failed == 1 ? "" : "s")")
    }
}
