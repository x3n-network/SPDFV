import Foundation
import PDFKit
import SPDFVCore

func forms(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: [])
    guard parser.positional.count == 1 else { throw CLIError.usage("forms requires exactly one input PDF") }
    let url = fileURL(parser.positional[0])
    let document = try PDFOperations.open(url)
    print(try encode(FormInspectionReport(input: url.path, report: PDFOperations.formReport(for: document)), pretty: parser.flags.contains("--pretty")))
}

func formGate(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: [])
    guard parser.positional.count == 1 else { throw CLIError.usage("form-gate requires exactly one input PDF") }
    let url = fileURL(parser.positional[0])
    let document = try PDFOperations.open(url)
    print(try encode(FormGateInspectionReport(input: url.path, gate: PDFOperations.formGate(for: document)), pretty: parser.flags.contains("--pretty")))
}

func exportFormData(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--output"])
    guard parser.positional.count == 1 else { throw CLIError.usage("export-form-data requires exactly one input PDF") }
    let inputURL = fileURL(parser.positional[0])
    let outputURL = fileURL(try parser.requireOption("--output"))
    if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
        throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
    }
    let document = try PDFOperations.open(inputURL)
    let dataFile = try PDFOperations.formData(for: document)
    try PDFOperations.encodeFormData(dataFile).write(to: outputURL, options: .atomic)
    print(try encode(FormDataExportOperationReport(operation: "export-form-data", input: inputURL.path, output: outputURL.path, fields: dataFile.fields.count), pretty: parser.flags.contains("--pretty")))
}

func validateFormData(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--data"])
    guard parser.positional.count == 1 else { throw CLIError.usage("validate-form-data requires exactly one input PDF") }
    let inputURL = fileURL(parser.positional[0])
    let dataURL = fileURL(try parser.requireOption("--data"))
    let document = try PDFOperations.open(inputURL)
    let dataFile = try PDFOperations.decodeFormData(Data(contentsOf: dataURL))
    print(try encode(FormDataValidationOperationReport(operation: "validate-form-data", input: inputURL.path, data: dataURL.path, report: PDFOperations.validateFormData(dataFile, for: document)), pretty: parser.flags.contains("--pretty")))
}

func importFormData(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--data", "--output"])
    guard parser.positional.count == 1 else { throw CLIError.usage("import-form-data requires exactly one input PDF") }
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
    guard let outputDocument = PDFDocument(data: result.data) else { throw CLIError.failure("The imported form could not be reopened") }
    try PDFOperations.write(outputDocument, to: outputURL, overwrite: parser.flags.contains("--force"))
    print(try encode(FormDataImportOperationReport(operation: "import-form-data", input: inputURL.path, data: dataURL.path, output: outputURL.path, validation: validation, report: result.report), pretty: parser.flags.contains("--pretty")))
}

func formDataMappingTemplate(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--data", "--output", "--filename", "--format"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("form-data-mapping-template requires exactly one template PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let dataURL = fileURL(try parser.requireOption("--data"))
    let outputURL = fileURL(try parser.requireOption("--output"))
    if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
        throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
    }
    let format = try formDataTableFormat(parser.options["--format"], url: dataURL)
    let document = try PDFOperations.open(inputURL)
    let suggested = try PDFOperations.suggestedFormDataBatchMapping(
        tableData: Data(contentsOf: dataURL),
        format: format,
        for: document
    )
    let mapping = PDFFormDataBatchMapping(
        columns: suggested.columns,
        filenameTemplate: parser.options["--filename"] ?? suggested.filenameTemplate
    )
    try PDFOperations.encodeFormDataBatchMapping(mapping).write(to: outputURL, options: .atomic)
    print(try encode(
        FormDataBatchMappingOperationReport(
            operation: "form-data-mapping-template",
            input: inputURL.path,
            data: dataURL.path,
            output: outputURL.path,
            mapping: mapping
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

func batchFormData(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--data", "--mapping", "--filename", "--format", "--output-dir"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("batch-form-data requires exactly one template PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let dataURL = fileURL(try parser.requireOption("--data"))
    let format = try formDataTableFormat(parser.options["--format"], url: dataURL)
    let templateData = try Data(contentsOf: inputURL)
    let tableData = try Data(contentsOf: dataURL)
    let document = try PDFOperations.open(inputURL)
    let baseMapping: PDFFormDataBatchMapping
    if let mappingPath = parser.options["--mapping"] {
        baseMapping = try PDFOperations.decodeFormDataBatchMapping(Data(contentsOf: fileURL(mappingPath)))
    } else {
        baseMapping = try PDFOperations.suggestedFormDataBatchMapping(
            tableData: tableData,
            format: format,
            for: document
        )
    }
    let mapping = PDFFormDataBatchMapping(
        columns: baseMapping.columns,
        filenameTemplate: parser.options["--filename"] ?? baseMapping.filenameTemplate
    )
    let report = try PDFOperations.validateFormDataBatch(
        templateData: templateData,
        tableData: tableData,
        format: format,
        mapping: mapping
    )
    let dryRun = parser.flags.contains("--dry-run")
    var outputDirectory: URL?
    if !dryRun {
        guard report.canWrite else {
            throw CLIError.failure("Batch validation failed; no PDFs were written")
        }
        let directory = fileURL(try parser.requireOption("--output-dir"))
        let destinations = report.items.compactMap(\.outputName).map { directory.appendingPathComponent($0) }
        if !parser.flags.contains("--force"), let existing = destinations.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            throw CLIError.failure("Output already exists; pass --force to replace it: \(existing.path)")
        }
        let result = try PDFOperations.fillFormBatch(
            templateData: templateData,
            tableData: tableData,
            format: format,
            mapping: mapping
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for output in result.outputs {
            try output.data.write(to: directory.appendingPathComponent(output.name), options: .atomic)
        }
        outputDirectory = directory
    }
    print(try encode(
        FormDataBatchOperationReport(
            operation: "batch-form-data",
            input: inputURL.path,
            data: dataURL.path,
            outputDirectory: outputDirectory?.path,
            dryRun: dryRun,
            report: report
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func formDataTableFormat(_ explicit: String?, url: URL) throws -> PDFFormDataTableFormat {
    if let explicit {
        guard let format = PDFFormDataTableFormat(rawValue: explicit.lowercased()) else {
            throw CLIError.usage("--format must be csv or tsv")
        }
        return format
    }
    switch url.pathExtension.lowercased() {
    case "csv": return .csv
    case "tsv", "tab": return .tsv
    default: throw CLIError.usage("Use a .csv or .tsv data file, or pass --format")
    }
}

func fillForm(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--values", "--output"])
    guard parser.positional.count == 1 else { throw CLIError.usage("fill-form requires exactly one input PDF") }
    let inputURL = fileURL(parser.positional[0])
    let outputURL = fileURL(try parser.requireOption("--output"))
    if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
        throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
    }
    let rawValues = try parser.requireOption("--values")
    guard let json = rawValues.data(using: .utf8),
          let values = try JSONSerialization.jsonObject(with: json) as? [String: String], !values.isEmpty else {
        throw CLIError.usage("--values expects a non-empty JSON object of string values")
    }
    let result = try PDFOperations.fillForm(data: Data(contentsOf: inputURL), values: values)
    try result.data.write(to: outputURL, options: .atomic)
    print(try encode(FormFillOperationReport(operation: "fill-form", input: inputURL.path, output: outputURL.path, updatedFields: values.keys.sorted(), report: result.report), pretty: parser.flags.contains("--pretty")))
}

func addField(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--page", "--type", "--name", "--bounds", "--value", "--choices", "--output"])
    guard parser.positional.count == 1 else { throw CLIError.usage("add-field requires exactly one input PDF") }
    let inputURL = fileURL(parser.positional[0])
    let outputURL = fileURL(try parser.requireOption("--output"))
    if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
        throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
    }
    guard let page = Int(try parser.requireOption("--page")), page > 0 else { throw CLIError.usage("--page must be a positive one-based page number") }
    let type = try parser.requireOption("--type")
    guard let kind = PDFFormFieldKind(rawValue: type), [.text, .checkbox, .choice].contains(kind) else { throw CLIError.usage("--type must be text, checkbox, or choice") }
    let draft = PDFFormFieldDraft(name: try parser.requireOption("--name"), kind: kind, value: parser.options["--value"] ?? "", choices: parser.options["--choices"]?.split(separator: ",").map(String.init) ?? [])
    let document = try PDFOperations.open(inputURL)
    _ = try PDFOperations.addFormField(draft, to: document, pageIndex: page - 1, bounds: try parseRect(try parser.requireOption("--bounds")))
    guard let staged = document.dataRepresentation() else { throw CLIError.failure("The authored form could not be prepared for writing") }
    let result = try PDFOperations.normalizeFormData(staged)
    try result.data.write(to: outputURL, options: .atomic)
    guard let field = result.report.fields.first(where: { $0.name == draft.name }) else { throw CLIError.failure("The authored field disappeared after writing") }
    print(try encode(FormAuthoringOperationReport(operation: "add-field", input: inputURL.path, output: outputURL.path, page: page, field: field, report: result.report), pretty: parser.flags.contains("--pretty")))
}

func renameField(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--from", "--to", "--output"])
    guard parser.positional.count == 1 else { throw CLIError.usage("rename-field requires exactly one input PDF") }
    let inputURL = fileURL(parser.positional[0])
    let outputURL = fileURL(try parser.requireOption("--output"))
    if FileManager.default.fileExists(atPath: outputURL.path), !parser.flags.contains("--force") {
        throw CLIError.failure("Output already exists; pass --force to replace it: \(outputURL.path)")
    }
    let previousName = try parser.requireOption("--from")
    let newName = try parser.requireOption("--to")
    let document = try PDFOperations.open(inputURL)
    let widgetCount = try PDFOperations.renameFormField(named: previousName, to: newName, in: document)
    guard let staged = document.dataRepresentation() else { throw CLIError.failure("The renamed form could not be prepared for writing") }
    let result = try PDFOperations.normalizeFormData(staged)
    try result.data.write(to: outputURL, options: .atomic)
    print(try encode(FormRenameOperationReport(operation: "rename-field", input: inputURL.path, output: outputURL.path, previousName: previousName, name: newName.trimmingCharacters(in: .whitespacesAndNewlines), widgetCount: widgetCount, report: result.report), pretty: parser.flags.contains("--pretty")))
}
