import Foundation
import SPDFVCore

func doctor(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: [])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("doctor requires exactly one input PDF")
    }
    let url = fileURL(parser.positional[0])
    let document = try PDFOperations.open(url)
    let report = PDFOperations.diagnose(document)
    print(try encode(
        DoctorInspectionReport(
            input: url.path,
            report: report,
            plan: PDFOperations.doctorRepairPlan(for: document)
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

func doctorRepair(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: ["--output", "--actions", "--quality", "--languages", "--dpi"])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("doctor-repair requires exactly one input PDF")
    }

    let inputURL = fileURL(parser.positional[0])
    let outputURL = fileURL(try parser.requireOption("--output"))
    let actions = try parser.options["--actions"].map(parseDoctorActions)
    let qualityValue = parser.options["--quality"] ?? PDFOCRRecognitionLevel.accurate.rawValue
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

    let result = try PDFOperations.applyDoctorRepairs(
        data: Data(contentsOf: inputURL),
        actions: actions,
        ocrConfiguration: PDFOCRConfiguration(
            recognitionLevel: quality,
            languages: languages,
            usesLanguageCorrection: true,
            renderDPI: dpi
        )
    )
    try PDFOperations.write(result, to: outputURL, overwrite: parser.flags.contains("--force"))
    print(try encode(
        DoctorRepairOperationReport(
            operation: "doctor-repair",
            input: inputURL.path,
            output: outputURL.path,
            verification: result.verification,
            ocr: result.ocrReport
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}

private func parseDoctorActions(_ value: String) throws -> [PDFDoctorRepairAction] {
    let aliases: [String: PDFDoctorRepairAction] = [
        "ocr": .ocrPages,
        "ocrPages": .ocrPages,
        "forms": .normalizeForms,
        "normalizeForms": .normalizeForms,
        "metadata": .removeMetadata,
        "removeMetadata": .removeMetadata
    ]
    var actions: [PDFDoctorRepairAction] = []
    for component in value.split(separator: ",") {
        let name = component.trimmingCharacters(in: .whitespaces)
        guard let action = aliases[name] else {
            throw CLIError.usage("--actions accepts ocr, forms, and metadata")
        }
        if !actions.contains(action) { actions.append(action) }
    }
    guard !actions.isEmpty else { throw CLIError.usage("--actions cannot be empty") }
    return actions
}
