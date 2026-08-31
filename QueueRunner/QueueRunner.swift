import Foundation
import SPDFVCore

@main
struct SPDFVQueueRunner {
    static func main() {
        do {
            let queueURL = try backgroundQueueURL()
            guard FileManager.default.fileExists(atPath: queueURL.path) else { return }
            var queue = try JSONDecoder().decode(PDFRecipeJobQueue.self, from: Data(contentsOf: queueURL))
            guard queue.version == 1 else { return }
            let pending = queue.prepareForRun()
            try write(queue, to: queueURL)

            for id in pending {
                guard queue.markRunning(id), let job = queue.jobs.first(where: { $0.id == id }) else { continue }
                try write(queue, to: queueURL)
                do {
                    let output = URL(fileURLWithPath: job.outputPath).standardizedFileURL
                    guard !FileManager.default.fileExists(atPath: output.path) else {
                        throw PDFOperationError.invalidInput("Output already exists: \(output.lastPathComponent)")
                    }
                    let recipeData = try Data(contentsOf: URL(fileURLWithPath: job.recipePath))
                    let inputData = try Data(contentsOf: URL(fileURLWithPath: job.inputPath))
                    let recipe = try PDFRecipeRunner.decode(recipeData)
                    let result = try PDFRecipeRunner.run(recipe, on: inputData)
                    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try result.data.write(to: output, options: .atomic)
                    _ = queue.markPassed(id, report: result.report)
                } catch {
                    _ = queue.markFailed(id, error: (error as? PDFOperationError)?.description ?? error.localizedDescription)
                }
                try write(queue, to: queueURL)
            }
        } catch {
            fputs("SPDFVQueueRunner: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func backgroundQueueURL() throws -> URL {
        let container = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.x3nllc.SPDFV/Data/Library/Application Support/SPDFV", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return container.appendingPathComponent("background-queue.json")
    }

    private static func write(_ queue: PDFRecipeJobQueue, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(queue).write(to: url, options: .atomic)
    }
}
