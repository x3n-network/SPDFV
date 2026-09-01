import Foundation
import SPDFVCore

func verifySignatures(_ arguments: [String]) throws {
    let parser = try OptionParser(arguments)
    try parser.rejectUnknownOptions(allowing: [])
    guard parser.positional.count == 1 else {
        throw CLIError.usage("verify-signatures requires exactly one input PDF")
    }
    let inputURL = fileURL(parser.positional[0])
    let report = PDFOperations.verifySignatures(in: try Data(contentsOf: inputURL))
    print(try encode(
        SignatureVerificationOperationReport(
            operation: "verify-signatures",
            input: inputURL.path,
            report: report
        ),
        pretty: parser.flags.contains("--pretty")
    ))
}
