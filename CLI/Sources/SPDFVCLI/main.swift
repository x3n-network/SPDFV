import Foundation
import PDFKit
import SPDFVCore

private func inspect(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: [])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("inspect requires exactly one input PDF")
    }
    let url = fileURL(parser.positional[0])
    let document = try PDFOperations.open(url)
    print(try encode(PDFOperations.inspect(document, sourceURL: url), pretty: parser.flags.contains("--pretty")))
}

private func annotations(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--pages"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("annotations requires exactly one input PDF")
    }
    let url = fileURL(parser.positional[0])
    let document = try PDFOperations.open(url)
    let pages = try PDFPageSelection.parse(parser.options["--pages"] ?? "all", pageCount: document.pageCount)
    let records = try PDFOperations.annotations(in: document, pageIndices: pages)
    print(try encode(
        AnnotationListReport(input: url.path, pages: pages.map { $0 + 1 }, count: records.count, annotations: records),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func text(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--pages"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("text requires exactly one input PDF")
    }
    let url = fileURL(parser.positional[0])
    let document = try PDFOperations.open(url)
    let pages = try PDFPageSelection.parse(parser.options["--pages"] ?? "all", pageCount: document.pageCount)
    let details = pages.compactMap { index -> TextPageReport? in
        guard let page = document.page(at: index) else { return nil }
        let value = page.string ?? ""
        return TextPageReport(page: index + 1, characters: value.count, text: value)
    }
    print(try encode(
        TextExtractionReport(
            input: url.path,
            pages: pages.map { $0 + 1 },
            characters: details.reduce(0) { $0 + $1.characters },
            pageDetails: details
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func forms(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: [])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("forms requires exactly one input PDF")
    }
    let url = fileURL(parser.positional[0])
    let document = try PDFOperations.open(url)
    print(try encode(
        FormInspectionReport(input: url.path, report: PDFOperations.formReport(for: document)),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func formGate(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: [])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("form-gate requires exactly one input PDF")
    }
    let url = fileURL(parser.positional[0])
    let document = try PDFOperations.open(url)
    print(try encode(
        FormGateInspectionReport(input: url.path, gate: PDFOperations.formGate(for: document)),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func exportFormData(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--output"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("export-form-data requires exactly one input PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let outputURL = fileURL(try parser.requireOption("--output"))
    if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
        throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
    }
    let document = try PDFOperations.open(inputURL)
    let dataFile = try PDFOperations.formData(for: document)
    try PDFOperations.encodeFormData(dataFile).write(to: outputURL, options: .atomic)
    print(try encode(
        FormDataExportOperationReport(
            operation: "export-form-data",
            input: inputURL.path,
            output: outputURL.path,
            fields: dataFile.fields.count
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func validateFormData(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--data"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("validate-form-data requires exactly one input PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let dataURL = fileURL(try parser.requireOption("--data"))
    let document = try PDFOperations.open(inputURL)
    let dataFile = try PDFOperations.decodeFormData(Data(contentsOf: dataURL))
    print(try encode(
        FormDataValidationOperationReport(
            operation: "validate-form-data",
            input: inputURL.path,
            data: dataURL.path,
            report: PDFOperations.validateFormData(dataFile, for: document)
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func importFormData(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--data", "--output"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("import-form-data requires exactly one input PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let dataURL = fileURL(try parser.requireOption("--data"))
    let outputURL = fileURL(try parser.requireOption("--output"))
    if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
        throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
    }
    let input = try Data(contentsOf: inputURL)
    let document = try PDFOperations.open(inputURL)
    let dataFile = try PDFOperations.decodeFormData(Data(contentsOf: dataURL))
    let validation = PDFOperations.validateFormData(dataFile, for: document)
    guard validation.canApply else {
        throw CLIError.failure("Form data validation failed for: \(validation.issues.map(\.name).joined(separator: ", "))")
    }
    let result = try PDFOperations.fillForm(data: input, formData: dataFile)
    guard let outputDocument = PDFDocument(data: result.data) else {
        throw CLIError.failure("The imported form could not be reopened")
    }
    try PDFOperations.write(outputDocument, to: outputURL, overwrite: parser.flags.contains("--force"))
    print(try encode(
        FormDataImportOperationReport(
            operation: "import-form-data",
            input: inputURL.path,
            data: dataURL.path,
            output: outputURL.path,
            validation: validation,
            report: result.report
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func safetyGate(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: [])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("safety-gate requires exactly one input PDF")
    }
    let url = fileURL(parser.positional[0])
    let document = try PDFOperations.open(url)
    print(try encode(
        SafetyGateInspectionReport(input: url.path, gate: PDFOperations.safetyGate(for: document)),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func safeShare(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: [])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("safe-share requires exactly one input PDF")
    }
    let url = fileURL(parser.positional[0])
    let document = try PDFOperations.open(url)
    print(try encode(
        SafeShareInspectionReport(input: url.path, report: PDFOperations.safeShareAudit(for: document)),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func compare(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: [])
    guard parser.positional.count == 2 else {
        throw CLIError.usage("compare requires a reference PDF and a candidate PDF")
    }
    let referenceURL = fileURL(parser.positional[0])
    let candidateURL = fileURL(parser.positional[1])
    let reference = try PDFOperations.open(referenceURL)
    let candidate = try PDFOperations.open(candidateURL)
    print(try encode(
        CompareOperationReport(
            operation: "compare",
            reference: referenceURL.path,
            candidate: candidateURL.path,
            report: try PDFOperations.compare(reference: reference, candidate: candidate)
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func doctor(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: [])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("doctor requires exactly one input PDF")
    }
    let url = fileURL(parser.positional[0])
    let document = try PDFOperations.open(url)
    print(try encode(
        DoctorInspectionReport(input: url.path, report: PDFOperations.diagnose(document)),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func fillForm(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--values", "--output"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("fill-form requires exactly one input PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let outputURL = fileURL(try parser.requireOption("--output"))
    if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
        throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
    }
    let rawValues = try parser.requireOption("--values")
    guard let json = rawValues.data(using: .utf8),
          let values = try JSONSerialization.jsonObject(with: json) as? [String: String],
          !values.isEmpty else {
        throw CLIError.usage("--values expects a non-empty JSON object of string values")
    }
    let input = try Data(contentsOf: inputURL)
    let result = try PDFOperations.fillForm(data: input, values: values)
    try result.data.write(to: outputURL, options: .atomic)
    print(try encode(
        FormFillOperationReport(
            operation: "fill-form",
            input: inputURL.path,
            output: outputURL.path,
            updatedFields: values.keys.sorted(),
            report: result.report
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func addField(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--page", "--type", "--name", "--bounds", "--value", "--choices", "--output"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("add-field requires exactly one input PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let outputURL = fileURL(try parser.requireOption("--output"))
    if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
        throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
    }
    guard let page = Int(try parser.requireOption("--page")), page > 0 else {
        throw CLIError.usage("--page must be a positive one-based page number")
    }
    let type = try parser.requireOption("--type")
    guard let kind = PDFFormFieldKind(rawValue: type), [.text, .checkbox, .choice].contains(kind) else {
        throw CLIError.usage("--type must be text, checkbox, or choice")
    }
    let bounds = try parseRect(try parser.requireOption("--bounds"))
    let choices = parser.options["--choices"]?.split(separator: ",").map(String.init) ?? []
    let draft = PDFFormFieldDraft(
        name: try parser.requireOption("--name"),
        kind: kind,
        value: parser.options["--value"] ?? "",
        choices: choices
    )
    let document = try PDFOperations.open(inputURL)
    _ = try PDFOperations.addFormField(draft, to: document, pageIndex: page - 1, bounds: bounds)
    guard let staged = document.dataRepresentation() else {
        throw CLIError.failure("The authored form could not be prepared for writing")
    }
    let result = try PDFOperations.normalizeFormData(staged)
    try result.data.write(to: outputURL, options: .atomic)
    guard let field = result.report.fields.first(where: { $0.name == draft.name }) else {
        throw CLIError.failure("The authored field disappeared after writing")
    }
    print(try encode(
        FormAuthoringOperationReport(
            operation: "add-field",
            input: inputURL.path,
            output: outputURL.path,
            page: page,
            field: field,
            report: result.report
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func renameField(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--from", "--to", "--output"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("rename-field requires exactly one input PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let outputURL = fileURL(try parser.requireOption("--output"))
    if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
        throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
    }
    let previousName = try parser.requireOption("--from")
    let newName = try parser.requireOption("--to")
    let document = try PDFOperations.open(inputURL)
    let widgetCount = try PDFOperations.renameFormField(named: previousName, to: newName, in: document)
    guard let staged = document.dataRepresentation() else {
        throw CLIError.failure("The renamed form could not be prepared for writing")
    }
    let result = try PDFOperations.normalizeFormData(staged)
    try result.data.write(to: outputURL, options: .atomic)
    print(try encode(
        FormRenameOperationReport(
            operation: "rename-field",
            input: inputURL.path,
            output: outputURL.path,
            previousName: previousName,
            name: newName.trimmingCharacters(in: .whitespacesAndNewlines),
            widgetCount: widgetCount,
            report: result.report
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func recipeTemplate(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: [])
    guard parser.positional.isEmpty else { throw CLIError.usage("recipe-template does not accept positional arguments") }
    print(String(decoding: try PDFRecipeRunner.encodedStarterRecipe(pretty: true), as: UTF8.self))
}

private func validateRecipe(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--recipe"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("validate-recipe requires exactly one input PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let recipeURL = fileURL(try parser.requireOption("--recipe"))
    let recipe = try PDFRecipeRunner.decode(Data(contentsOf: recipeURL))
    let result = try PDFRecipeRunner.run(recipe, on: Data(contentsOf: inputURL), dryRun: true)
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

private func runRecipe(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--recipe", "--output"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("run-recipe requires exactly one input PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let recipeURL = fileURL(try parser.requireOption("--recipe"))
    let outputURL = fileURL(try parser.requireOption("--output"))
    if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
        throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
    }
    let recipe = try PDFRecipeRunner.decode(Data(contentsOf: recipeURL))
    let result = try PDFRecipeRunner.run(recipe, on: Data(contentsOf: inputURL))
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

private func batchRecipe(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--recipe", "--output-dir"])
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
    let result = PDFRecipeBatchRunner.run(recipe, inputs: inputs, dryRun: dryRun)
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

private func libraryList(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--library"])
    guard parser.positional.isEmpty else { throw CLIError.usage("library-list does not accept positional arguments") }
    let libraryURL = fileURL(try parser.requireOption("--library"))
    let catalog = FileManager.default.fileExists(atPath: libraryURL.path)
        ? try decodeFile(PDFRecipeLibraryCatalog.self, at: libraryURL)
        : PDFRecipeLibraryCatalog()
    let entries = catalog.entries.sorted {
        if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
        return $0.updatedAt > $1.updatedAt
    }
    print(try encode(
        RecipeLibraryOperationReport(
            operation: "library-list",
            library: libraryURL.path,
            count: entries.count,
            entry: nil,
            entries: entries,
            output: nil
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func libraryAdd(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--library", "--recipe"])
    guard parser.positional.isEmpty else { throw CLIError.usage("library-add does not accept positional arguments") }
    let libraryURL = fileURL(try parser.requireOption("--library"))
    let recipeURL = fileURL(try parser.requireOption("--recipe"))
    var catalog = FileManager.default.fileExists(atPath: libraryURL.path)
        ? try decodeFile(PDFRecipeLibraryCatalog.self, at: libraryURL)
        : PDFRecipeLibraryCatalog()
    let recipe = try PDFRecipeRunner.decode(Data(contentsOf: recipeURL))
    let id = try catalog.save(recipe)
    if parser.flags.contains("--favorite") { catalog.toggleFavorite(id) }
    try writeJSONFile(catalog, to: libraryURL)
    let entry = catalog.entries.first { $0.id == id }
    print(try encode(
        RecipeLibraryOperationReport(
            operation: "library-add",
            library: libraryURL.path,
            count: catalog.entries.count,
            entry: entry,
            entries: nil,
            output: nil
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func libraryExport(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--library", "--id", "--output"])
    guard parser.positional.isEmpty else { throw CLIError.usage("library-export does not accept positional arguments") }
    let libraryURL = fileURL(try parser.requireOption("--library"))
    let outputURL = fileURL(try parser.requireOption("--output"))
    guard let id = UUID(uuidString: try parser.requireOption("--id")) else {
        throw CLIError.usage("--id must be a UUID")
    }
    if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
        throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
    }
    let catalog = try decodeFile(PDFRecipeLibraryCatalog.self, at: libraryURL)
    guard let entry = catalog.entries.first(where: { $0.id == id }) else {
        throw CLIError.failure("Recipe not found in library: \(id.uuidString)")
    }
    try writeJSONFile(entry.recipe, to: outputURL)
    print(try encode(
        RecipeLibraryOperationReport(
            operation: "library-export",
            library: libraryURL.path,
            count: catalog.entries.count,
            entry: entry,
            entries: nil,
            output: outputURL.path
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func loadQueue(at url: URL) throws -> PDFRecipeJobQueue {
    guard FileManager.default.fileExists(atPath: url.path) else { return PDFRecipeJobQueue() }
    let queue = try decodeFile(PDFRecipeJobQueue.self, at: url)
    guard queue.version == 1 else { throw CLIError.failure("Unsupported queue version: \(queue.version)") }
    return queue
}

private func enqueueRecipe(_ arguments: [String]) throws {
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

private func queueStatus(_ arguments: [String]) throws {
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

private func runQueue(_ arguments: [String]) throws {
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

private func watchOnce(_ arguments: [String]) throws {
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

private func extract(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--pages", "--output"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("extract requires exactly one input PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let outputURL = fileURL(try parser.requireOption("--output"))
    let document = try PDFOperations.open(inputURL)
    let pages = try selectedPages(parser, document: document)
    let extracted = try PDFOperations.extract(document, pageIndices: pages)
    try write(extracted, to: outputURL, parser: parser, operation: "extract", inputs: [inputURL], pages: pages)
}

private func merge(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--output"])
    guard parser.positional.count >= 2 else {
        throw CLIError.usage("merge requires at least two input PDFs")
    }
    let inputURLs = parser.positional.map(fileURL)
    let documents = try inputURLs.map(PDFOperations.open)
    let merged = try PDFOperations.merge(documents)
    try write(
        merged,
        to: fileURL(try parser.requireOption("--output")),
        parser: parser,
        operation: "merge",
        inputs: inputURLs
    )
}

private func rotate(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--pages", "--degrees", "--output"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("rotate requires exactly one input PDF")
    }
    guard let degrees = Int(try parser.requireOption("--degrees")) else {
        throw CLIError.usage("--degrees must be an integer multiple of 90")
    }
    let inputURL = fileURL(parser.positional[0])
    let document = try PDFOperations.open(inputURL)
    let pages = try selectedPages(parser, document: document)
    _ = try PDFOperations.rotate(document, pageIndices: pages, degrees: degrees)
    try write(
        document,
        to: fileURL(try parser.requireOption("--output")),
        parser: parser,
        operation: "rotate",
        inputs: [inputURL],
        pages: pages,
        details: ["degrees": "\(degrees)"]
    )
}

private func crop(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--pages", "--insets", "--output"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("crop requires exactly one input PDF")
    }
    let insets = try parseInsets(try parser.requireOption("--insets"))
    let inputURL = fileURL(parser.positional[0])
    let document = try PDFOperations.open(inputURL)
    let pages = try selectedPages(parser, document: document)
    _ = try PDFOperations.crop(document, pageIndices: pages, insets: insets)
    try write(
        document,
        to: fileURL(try parser.requireOption("--output")),
        parser: parser,
        operation: "crop",
        inputs: [inputURL],
        pages: pages,
        details: ["insets": "\(insets.top),\(insets.right),\(insets.bottom),\(insets.left)"]
    )
}

private func ocr(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--pages", "--quality", "--languages", "--dpi", "--output"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("ocr requires exactly one input PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let outputURL = fileURL(try parser.requireOption("--output"))
    let document = try PDFOperations.open(inputURL)
    let pages = try PDFPageSelection.parse(parser.options["--pages"] ?? "all", pageCount: document.pageCount)
    let qualityValue = parser.options["--quality"] ?? "accurate"
    guard let quality = PDFOCRRecognitionLevel(rawValue: qualityValue) else {
        throw CLIError.usage("--quality must be fast or accurate")
    }
    let languages = parser.options["--languages"]?
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty } ?? []
    let dpi: Double
    if let value = parser.options["--dpi"] {
        guard let parsed = Double(value), (72...400).contains(parsed) else {
            throw CLIError.usage("--dpi must be between 72 and 400")
        }
        dpi = parsed
    } else {
        dpi = 216
    }
    guard let data = document.dataRepresentation() else {
        throw CLIError.failure("Could not read input PDF data")
    }
    let result = try PDFOperations.makeSearchable(
        data: data,
        pageIndices: pages,
        configuration: PDFOCRConfiguration(
            recognitionLevel: quality,
            languages: languages,
            usesLanguageCorrection: true,
            renderDPI: dpi
        )
    )
    try PDFOperations.write(result, to: outputURL, overwrite: parser.flags.contains("--force"))
    print(try encode(
        OCROperationReport(operation: "ocr", input: inputURL.path, output: outputURL.path, report: result.report),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func redact(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--regions", "--verify-absent", "--quality", "--languages", "--dpi", "--output"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("redact requires exactly one input PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let outputURL = fileURL(try parser.requireOption("--output"))
    let regions = try parseRedactionRegions(try parser.requireOption("--regions"))
    let qualityValue = parser.options["--quality"] ?? "accurate"
    guard let quality = PDFOCRRecognitionLevel(rawValue: qualityValue) else {
        throw CLIError.usage("--quality must be fast or accurate")
    }
    let languages = parser.options["--languages"]?
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty } ?? []
    let dpi: Double
    if let value = parser.options["--dpi"] {
        guard let parsed = Double(value), (144...400).contains(parsed) else {
            throw CLIError.usage("--dpi must be between 144 and 400")
        }
        dpi = parsed
    } else {
        dpi = 216
    }
    let forbiddenTerms = parser.options["--verify-absent"]?
        .split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty } ?? []
    let document = try PDFOperations.open(inputURL)
    guard let data = document.dataRepresentation() else {
        throw CLIError.failure("Could not read input PDF data")
    }
    let result = try PDFOperations.sanitize(
        data: data,
        regions: regions,
        configuration: PDFRedactionConfiguration(
            renderDPI: dpi,
            restoresSearchableText: !parser.flags.contains("--no-ocr"),
            recognitionLevel: quality,
            languages: languages
        ),
        verifyAbsentTerms: forbiddenTerms
    )
    try PDFOperations.write(result, to: outputURL, overwrite: parser.flags.contains("--force"))
    print(try encode(
        RedactionOperationReport(
            operation: "redact",
            input: inputURL.path,
            output: outputURL.path,
            regions: regions,
            report: result.report
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

private let usage = """
SPDFV command line interface

USAGE
  spdfv inspect <input.pdf> [--pretty]
  spdfv annotations <input.pdf> [--pages <spec>] [--pretty]
  spdfv forms <input.pdf> [--pretty]
  spdfv form-gate <input.pdf> [--pretty]
  spdfv export-form-data <input.pdf> --output <data.json> [--force] [--pretty]
  spdfv validate-form-data <input.pdf> --data <data.json> [--pretty]
  spdfv import-form-data <input.pdf> --data <data.json> --output <output.pdf> [--force] [--pretty]
  spdfv safety-gate <input.pdf> [--pretty]
  spdfv safe-share <input.pdf> [--pretty]
  spdfv compare <reference.pdf> <candidate.pdf> [--pretty]
  spdfv doctor <input.pdf> [--pretty]
  spdfv fill-form <input.pdf> --values <json-object> --output <output.pdf> [--force] [--pretty]
  spdfv add-field <input.pdf> --page <n> --type <text|checkbox|choice> --name <field> --bounds <x,y,w,h> [--value <text>] [--choices <a,b,c>] --output <output.pdf> [--force] [--pretty]
  spdfv rename-field <input.pdf> --from <field> --to <field> --output <output.pdf> [--force] [--pretty]
  spdfv recipe-template
  spdfv validate-recipe <input.pdf> --recipe <recipe.json> [--pretty]
  spdfv run-recipe <input.pdf> --recipe <recipe.json> --output <output.pdf> [--force] [--pretty]
  spdfv batch-recipe <input-directory> --recipe <recipe.json> [--output-dir <directory>] [--dry-run] [--force] [--pretty]
  spdfv library-list --library <catalog.json> [--pretty]
  spdfv library-add --library <catalog.json> --recipe <recipe.json> [--favorite] [--pretty]
  spdfv library-export --library <catalog.json> --id <uuid> --output <recipe.json> [--force] [--pretty]
  spdfv enqueue-recipe <input.pdf> --recipe <recipe.json> --output <output.pdf> --queue <queue.json> [--pretty]
  spdfv queue-status --queue <queue.json> [--pretty]
  spdfv run-queue --queue <queue.json> [--force] [--pretty]
  spdfv watch-once <input-directory> --recipe <recipe.json> --output-dir <directory> --state <state.json> [--pretty]
  spdfv text <input.pdf> [--pages <spec>] [--pretty]
  spdfv extract <input.pdf> --pages <spec> --output <output.pdf> [--force] [--pretty]
  spdfv merge <one.pdf> <two.pdf> [...] --output <output.pdf> [--force] [--pretty]
  spdfv rotate <input.pdf> --pages <spec> --degrees <90|-90|180> --output <output.pdf> [--force] [--pretty]
  spdfv crop <input.pdf> --pages <spec> --insets <all|t,r,b,l> --output <output.pdf> [--force] [--pretty]
  spdfv ocr <input.pdf> [--pages <spec>] [--quality <fast|accurate>] [--languages <codes>] [--dpi <72...400>] --output <output.pdf> [--force] [--pretty]
  spdfv redact <input.pdf> --regions <page:x,y,w,h;...> [--verify-absent <terms>] [--no-ocr] [--dpi <144...400>] --output <output.pdf> [--force] [--pretty]

PAGE SPEC
  One-based pages and inclusive ranges: 1,3-5,9
  Use all to select the complete document.

OUTPUT
  Commands print stable JSON to stdout. Errors are written to stderr.
"""

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { throw CLIError.usage(usage) }
    switch command {
    case "help", "--help", "-h": print(usage)
    case "inspect": try inspect(Array(arguments.dropFirst()))
    case "annotations": try annotations(Array(arguments.dropFirst()))
    case "forms": try forms(Array(arguments.dropFirst()))
    case "form-gate": try formGate(Array(arguments.dropFirst()))
    case "export-form-data": try exportFormData(Array(arguments.dropFirst()))
    case "validate-form-data": try validateFormData(Array(arguments.dropFirst()))
    case "import-form-data": try importFormData(Array(arguments.dropFirst()))
    case "safety-gate": try safetyGate(Array(arguments.dropFirst()))
    case "safe-share": try safeShare(Array(arguments.dropFirst()))
    case "compare": try compare(Array(arguments.dropFirst()))
    case "doctor": try doctor(Array(arguments.dropFirst()))
    case "fill-form": try fillForm(Array(arguments.dropFirst()))
    case "add-field": try addField(Array(arguments.dropFirst()))
    case "rename-field": try renameField(Array(arguments.dropFirst()))
    case "recipe-template": try recipeTemplate(Array(arguments.dropFirst()))
    case "validate-recipe": try validateRecipe(Array(arguments.dropFirst()))
    case "run-recipe": try runRecipe(Array(arguments.dropFirst()))
    case "batch-recipe": try batchRecipe(Array(arguments.dropFirst()))
    case "library-list": try libraryList(Array(arguments.dropFirst()))
    case "library-add": try libraryAdd(Array(arguments.dropFirst()))
    case "library-export": try libraryExport(Array(arguments.dropFirst()))
    case "enqueue-recipe": try enqueueRecipe(Array(arguments.dropFirst()))
    case "queue-status": try queueStatus(Array(arguments.dropFirst()))
    case "run-queue": try runQueue(Array(arguments.dropFirst()))
    case "watch-once": try watchOnce(Array(arguments.dropFirst()))
    case "text": try text(Array(arguments.dropFirst()))
    case "extract": try extract(Array(arguments.dropFirst()))
    case "merge": try merge(Array(arguments.dropFirst()))
    case "rotate": try rotate(Array(arguments.dropFirst()))
    case "crop": try crop(Array(arguments.dropFirst()))
    case "ocr": try ocr(Array(arguments.dropFirst()))
    case "redact": try redact(Array(arguments.dropFirst()))
    default: throw CLIError.usage("Unknown command: \(command)\n\n\(usage)")
    }
} catch let error as CLIError {
    fputs("spdfv: \(error.description)\n", stderr)
    exit(error.isUsage ? 64 : 1)
} catch let error as PDFOperationError {
    fputs("spdfv: \(error.description)\n", stderr)
    exit(error.isUsage ? 64 : 1)
} catch {
    fputs("spdfv: \(error.localizedDescription)\n", stderr)
    exit(1)
}

private extension CLIError {
    var isUsage: Bool {
        if case .usage = self { return true }
        return false
    }
}

private extension PDFOperationError {
    var isUsage: Bool {
        switch self {
        case .invalidPageSelection: true
        default: false
        }
    }
}
