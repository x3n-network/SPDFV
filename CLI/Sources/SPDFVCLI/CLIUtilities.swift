import Foundation
import PDFKit
import SPDFVCore

func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: path).standardizedFileURL
}

func encode<T: Encodable>(_ value: T, pretty: Bool) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = pretty
        ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        : [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

func decodeFile<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: url))
}

func writeJSONFile<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let parent = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    try encoder.encode(value).write(to: url, options: .atomic)
}

func errorMessage(_ error: Error) -> String {
    if let operationError = error as? PDFOperationError { return operationError.description }
    if let cliError = error as? CLIError { return cliError.description }
    return error.localizedDescription
}

func selectedPages(_ parser: OptionParser, document: PDFDocument) throws -> [Int] {
    try PDFPageSelection.parse(try parser.requireOption("--pages"), pageCount: document.pageCount)
}

func write(
    _ document: PDFDocument,
    to outputURL: URL,
    parser: OptionParser,
    operation: String,
    inputs: [URL],
    pages: [Int]? = nil,
    details: [String: String]? = nil
) throws {
    try PDFOperations.write(document, to: outputURL, overwrite: parser.flags.contains("--force"))
    let report = OperationReport(
        operation: operation,
        inputs: inputs.map(\.path),
        output: outputURL.path,
        pages: pages?.map { $0 + 1 },
        pageCount: document.pageCount,
        details: details
    )
    print(try encode(report, pretty: parser.flags.contains("--pretty")))
}

func parseRedactionRegions(_ value: String) throws -> [PDFRedactionRegion] {
    let regions = try value.split(separator: ";").map { raw -> PDFRedactionRegion in
        let pair = raw.split(separator: ":", maxSplits: 1)
        guard pair.count == 2, let page = Int(pair[0]), page > 0 else {
            throw CLIError.usage("Each redaction region must use page:x,y,width,height")
        }
        let values = pair[1].split(separator: ",").compactMap {
            Double($0.trimmingCharacters(in: .whitespaces))
        }
        guard values.count == 4, values[2] > 0, values[3] > 0 else {
            throw CLIError.usage("Each redaction region must use page:x,y,width,height")
        }
        return PDFRedactionRegion(
            page: page,
            bounds: CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        )
    }
    guard !regions.isEmpty else { throw CLIError.usage("--regions cannot be empty") }
    return regions
}

func parseInsets(_ value: String) throws -> PDFEdgeInsets {
    let components = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    if components.count == 1, let uniform = components.first {
        return PDFEdgeInsets(top: uniform, right: uniform, bottom: uniform, left: uniform)
    }
    guard components.count == 4 else {
        throw CLIError.usage("--insets expects one value or top,right,bottom,left")
    }
    return PDFEdgeInsets(top: components[0], right: components[1], bottom: components[2], left: components[3])
}

func parseRect(_ value: String) throws -> CGRect {
    let parts = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 4, parts[2] >= 16, parts[3] >= 16 else {
        throw CLIError.usage("--bounds expects x,y,width,height with dimensions of at least 16 points")
    }
    return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
}
