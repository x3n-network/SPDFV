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
    try parser.rejectUnknownOptions(allowing: ["--alignment", "--appearance-threshold", "--ignore-regions"])
    guard parser.positional.count == 2 else {
        throw CLIError.usage("compare requires a reference PDF and a candidate PDF")
    }
    let referenceURL = fileURL(parser.positional[0])
    let candidateURL = fileURL(parser.positional[1])
    let alignmentValue = parser.options["--alignment"] ?? PDFComparisonAlignment.intelligent.rawValue
    guard let alignment = PDFComparisonAlignment(rawValue: alignmentValue) else {
        throw CLIError.usage("--alignment must be intelligent or position")
    }
    let appearanceThreshold: Double
    if let value = parser.options["--appearance-threshold"] {
        guard let parsed = Double(value), (0...1).contains(parsed) else {
            throw CLIError.usage("--appearance-threshold must be between 0 and 1")
        }
        appearanceThreshold = parsed
    } else {
        appearanceThreshold = 0.999
    }
    let ignoredRegions = try parser.options["--ignore-regions"].map(parseComparisonIgnoredRegions) ?? []
    let options = PDFComparisonOptions(
        alignment: alignment,
        minimumAppearanceSimilarity: appearanceThreshold,
        ignoredRegions: ignoredRegions
    )
    let reference = try PDFOperations.open(referenceURL)
    let candidate = try PDFOperations.open(candidateURL)
    print(try encode(
        CompareOperationReport(
            operation: "compare",
            reference: referenceURL.path,
            candidate: candidateURL.path,
            report: try PDFOperations.compare(reference: reference, candidate: candidate, options: options)
        ),
        pretty: parser.flags.contains("--pretty")
    ))
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
  spdfv form-data-mapping-template <input.pdf> --data <rows.csv|rows.tsv> --output <mapping.json> [--filename <template>] [--format <csv|tsv>] [--force] [--pretty]
  spdfv batch-form-data <input.pdf> --data <rows.csv|rows.tsv> [--mapping <mapping.json>] [--filename <template>] [--format <csv|tsv>] [--output-dir <directory>] [--dry-run] [--force] [--pretty]
  spdfv safety-gate <input.pdf> [--pretty]
  spdfv verify-signatures <input.pdf> [--pretty]
  spdfv safe-share <input.pdf> [--pretty]
  spdfv compare <reference.pdf> <candidate.pdf> [--alignment <intelligent|position>] [--appearance-threshold <0...1>] [--ignore-regions <x,y,w,h;...>] [--pretty]
  spdfv doctor <input.pdf> [--pretty]
  spdfv doctor-repair <input.pdf> --output <output.pdf> [--actions <ocr,forms,metadata>] [--quality <fast|accurate>] [--languages <codes>] [--dpi <72...400>] [--force] [--pretty]
  spdfv fill-form <input.pdf> --values <json-object> --output <output.pdf> [--force] [--pretty]
  spdfv add-field <input.pdf> --page <n> --type <text|checkbox|choice> --name <field> --bounds <x,y,w,h> [--value <text>] [--choices <a,b,c>] --output <output.pdf> [--force] [--pretty]
  spdfv rename-field <input.pdf> --from <field> --to <field> --output <output.pdf> [--force] [--pretty]
  spdfv recipe-template
  spdfv validate-recipe <input.pdf> --recipe <recipe.json> [--parameters <json>] [--references <json>] [--form-data <json>] [--pretty]
  spdfv run-recipe <input.pdf> --recipe <recipe.json> (--output <output.pdf> | --output-dir <directory>) [--parameters <json>] [--references <json>] [--form-data <json>] [--force] [--pretty]
  spdfv batch-recipe <input-directory> --recipe <recipe.json> [--output-dir <directory>] [--parameters <json>] [--references <json>] [--form-data <json>] [--dry-run] [--force] [--pretty]
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
    case "form-data-mapping-template": try formDataMappingTemplate(Array(arguments.dropFirst()))
    case "batch-form-data": try batchFormData(Array(arguments.dropFirst()))
    case "safety-gate": try safetyGate(Array(arguments.dropFirst()))
    case "verify-signatures": try verifySignatures(Array(arguments.dropFirst()))
    case "safe-share": try safeShare(Array(arguments.dropFirst()))
    case "compare": try compare(Array(arguments.dropFirst()))
    case "doctor": try doctor(Array(arguments.dropFirst()))
    case "doctor-repair": try doctorRepair(Array(arguments.dropFirst()))
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
