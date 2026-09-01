import Foundation
import PDFKit

public enum PDFFormDataTableFormat: String, Codable, CaseIterable, Sendable {
    case csv
    case tsv

    var delimiter: Character { self == .csv ? "," : "\t" }
}

public struct PDFFormDataColumnMapping: Codable, Equatable, Sendable, Identifiable {
    public var id: String { column }
    public let column: String
    public let field: String

    public init(column: String, field: String) {
        self.column = column
        self.field = field
    }
}

public struct PDFFormDataBatchMapping: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let columns: [PDFFormDataColumnMapping]
    public let filenameTemplate: String

    public init(
        version: Int = Self.currentVersion,
        columns: [PDFFormDataColumnMapping],
        filenameTemplate: String = "completed-{row}.pdf"
    ) {
        self.version = version
        self.columns = columns
        self.filenameTemplate = filenameTemplate
    }
}

public struct PDFFormDataTableSummary: Codable, Equatable, Sendable {
    public let format: PDFFormDataTableFormat
    public let columns: [String]
    public let rowCount: Int
}

public struct PDFFormDataBatchItemReport: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { row }
    public let row: Int
    public let outputName: String?
    public let validation: PDFFormDataValidationReport?
    public let errors: [String]
}

public struct PDFFormDataBatchReport: Codable, Equatable, Sendable {
    public let table: PDFFormDataTableSummary
    public let filenameTemplate: String
    public let mappedColumns: [PDFFormDataColumnMapping]
    public let validRows: Int
    public let invalidRows: Int
    public let canWrite: Bool
    public let items: [PDFFormDataBatchItemReport]
}

public struct PDFFormDataBatchOutput: Sendable {
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

public struct PDFFormDataBatchRunResult: Sendable {
    public let report: PDFFormDataBatchReport
    public let outputs: [PDFFormDataBatchOutput]
}

public extension PDFOperations {
    static func formDataTableSummary(
        _ tableData: Data,
        format: PDFFormDataTableFormat
    ) throws -> PDFFormDataTableSummary {
        let table = try parseFormDataTable(tableData, format: format)
        return PDFFormDataTableSummary(format: format, columns: table.headers, rowCount: table.rows.count)
    }

    static func suggestedFormDataBatchMapping(
        tableData: Data,
        format: PDFFormDataTableFormat,
        for document: PDFDocument
    ) throws -> PDFFormDataBatchMapping {
        let table = try parseFormDataTable(tableData, format: format)
        guard !document.isLocked else {
            throw PDFOperationError.invalidInput("Unlock the PDF before preparing a batch mapping")
        }
        let writableFields = formReport(for: document).fields.filter {
            !$0.readOnly && ![.signature, .pushButton, .unknown].contains($0.kind)
        }
        var fieldsByLowercaseName: [String: String] = [:]
        for field in writableFields where fieldsByLowercaseName[field.name.lowercased()] == nil {
            fieldsByLowercaseName[field.name.lowercased()] = field.name
        }
        let mappings = table.headers.compactMap { column -> PDFFormDataColumnMapping? in
            guard let field = fieldsByLowercaseName[column.lowercased()] else { return nil }
            return PDFFormDataColumnMapping(column: column, field: field)
        }
        return PDFFormDataBatchMapping(columns: mappings)
    }

    static func encodeFormDataBatchMapping(_ mapping: PDFFormDataBatchMapping) throws -> Data {
        try validateBatchMappingVersion(mapping)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(mapping)
    }

    static func decodeFormDataBatchMapping(_ data: Data) throws -> PDFFormDataBatchMapping {
        do {
            let mapping = try JSONDecoder().decode(PDFFormDataBatchMapping.self, from: data)
            try validateBatchMappingVersion(mapping)
            return mapping
        } catch let error as PDFOperationError {
            throw error
        } catch {
            throw PDFOperationError.invalidInput("Batch form mapping is not valid SPDFV JSON: \(error.localizedDescription)")
        }
    }

    static func validateFormDataBatch(
        templateData: Data,
        tableData: Data,
        format: PDFFormDataTableFormat,
        mapping: PDFFormDataBatchMapping
    ) throws -> PDFFormDataBatchReport {
        try prepareFormDataBatch(
            templateData: templateData,
            tableData: tableData,
            format: format,
            mapping: mapping
        ).report
    }

    static func fillFormBatch(
        templateData: Data,
        tableData: Data,
        format: PDFFormDataTableFormat,
        mapping: PDFFormDataBatchMapping
    ) throws -> PDFFormDataBatchRunResult {
        let prepared = try prepareFormDataBatch(
            templateData: templateData,
            tableData: tableData,
            format: format,
            mapping: mapping
        )
        guard prepared.report.canWrite else {
            throw PDFOperationError.invalidInput("Batch validation failed; no PDFs were produced")
        }

        var outputs: [PDFFormDataBatchOutput] = []
        outputs.reserveCapacity(prepared.jobs.count)
        for job in prepared.jobs {
            let filled = try fillForm(data: templateData, formData: job.data)
            outputs.append(PDFFormDataBatchOutput(name: job.outputName, data: filled.data))
        }
        return PDFFormDataBatchRunResult(report: prepared.report, outputs: outputs)
    }
}

private extension PDFOperations {
    struct FormDataTable {
        let headers: [String]
        let rows: [[String]]
    }

    struct PreparedFormDataBatch {
        struct Job {
            let outputName: String
            let data: PDFFormDataFile
        }

        let report: PDFFormDataBatchReport
        let jobs: [Job]
    }

    static func prepareFormDataBatch(
        templateData: Data,
        tableData: Data,
        format: PDFFormDataTableFormat,
        mapping: PDFFormDataBatchMapping
    ) throws -> PreparedFormDataBatch {
        try validateBatchMappingVersion(mapping)
        guard let document = PDFDocument(data: templateData), !document.isLocked else {
            throw PDFOperationError.invalidInput("Template must be a readable, unlocked PDF")
        }
        try requirePermission(.formEntry, for: document)
        let table = try parseFormDataTable(tableData, format: format)
        let headerSet = Set(table.headers)
        let normalizedColumns = mapping.columns.map {
            PDFFormDataColumnMapping(
                column: $0.column.trimmingCharacters(in: .whitespacesAndNewlines),
                field: $0.field.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard !normalizedColumns.isEmpty else {
            throw PDFOperationError.invalidInput("Map at least one table column to a PDF field")
        }
        guard Set(normalizedColumns.map(\.column)).count == normalizedColumns.count else {
            throw PDFOperationError.invalidInput("Each table column can be mapped only once")
        }
        guard Set(normalizedColumns.map(\.field)).count == normalizedColumns.count else {
            throw PDFOperationError.invalidInput("Each PDF field can be mapped only once")
        }
        if let missing = normalizedColumns.first(where: { !headerSet.contains($0.column) }) {
            throw PDFOperationError.invalidInput("Mapped column does not exist in the table: \(missing.column)")
        }

        let headerIndices = Dictionary(uniqueKeysWithValues: table.headers.enumerated().map { ($1, $0) })
        var reports: [PDFFormDataBatchItemReport] = []
        var jobs: [PreparedFormDataBatch.Job] = []
        var outputNames = Set<String>()

        for (rowIndex, row) in table.rows.enumerated() {
            let rowNumber = rowIndex + 1
            let entries = normalizedColumns.compactMap { item -> PDFFormDataEntry? in
                guard let index = headerIndices[item.column] else { return nil }
                return PDFFormDataEntry(name: item.field, value: row[index])
            }
            let dataFile = PDFFormDataFile(fields: entries)
            let validation = validateFormData(dataFile, for: document)
            var errors: [String] = []
            let outputName: String?
            do {
                let rendered = try renderBatchFilename(
                    mapping.filenameTemplate,
                    rowNumber: rowNumber,
                    headers: table.headers,
                    values: row
                )
                if outputNames.insert(rendered.lowercased()).inserted {
                    outputName = rendered
                } else {
                    outputName = rendered
                    errors.append("The filename template produces a duplicate output name.")
                }
            } catch {
                outputName = nil
                errors.append((error as? PDFOperationError)?.description ?? error.localizedDescription)
            }
            if !validation.canApply { errors.append("One or more mapped values cannot be applied to the template.") }
            reports.append(PDFFormDataBatchItemReport(
                row: rowNumber,
                outputName: outputName,
                validation: validation,
                errors: errors
            ))
            if errors.isEmpty, let outputName {
                jobs.append(PreparedFormDataBatch.Job(outputName: outputName, data: dataFile))
            }
        }

        let validRows = reports.filter { $0.errors.isEmpty }.count
        let report = PDFFormDataBatchReport(
            table: PDFFormDataTableSummary(format: format, columns: table.headers, rowCount: table.rows.count),
            filenameTemplate: mapping.filenameTemplate,
            mappedColumns: normalizedColumns,
            validRows: validRows,
            invalidRows: reports.count - validRows,
            canWrite: !reports.isEmpty && validRows == reports.count,
            items: reports
        )
        return PreparedFormDataBatch(report: report, jobs: report.canWrite ? jobs : [])
    }

    static func parseFormDataTable(_ data: Data, format: PDFFormDataTableFormat) throws -> FormDataTable {
        guard var text = String(data: data, encoding: .utf8) else {
            throw PDFOperationError.invalidInput("Form data table must use UTF-8 encoding")
        }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if quoted {
                if character == "\"" {
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    quoted = false
                } else {
                    field.append(character)
                }
            } else if character == "\"", field.isEmpty {
                quoted = true
            } else if character == format.delimiter {
                record.append(field)
                field = ""
            } else if character == "\n" || character == "\r" {
                record.append(field)
                field = ""
                if !record.allSatisfy({ $0.isEmpty }) { records.append(record) }
                record = []
                if character == "\r", next < text.endIndex, text[next] == "\n" {
                    index = text.index(after: next)
                    continue
                }
            } else {
                field.append(character)
            }
            index = next
        }
        guard !quoted else { throw PDFOperationError.invalidInput("Form data table contains an unterminated quoted value") }
        record.append(field)
        if !record.allSatisfy({ $0.isEmpty }) { records.append(record) }
        guard let rawHeaders = records.first else {
            throw PDFOperationError.invalidInput("Form data table is empty")
        }
        let headers = rawHeaders.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !headers.isEmpty, !headers.contains(where: \.isEmpty) else {
            throw PDFOperationError.invalidInput("Form data table headers cannot be empty")
        }
        guard Set(headers).count == headers.count else {
            throw PDFOperationError.invalidInput("Form data table headers must be unique")
        }
        let rows = Array(records.dropFirst())
        if let invalid = rows.firstIndex(where: { $0.count != headers.count }) {
            throw PDFOperationError.invalidInput("Table row \(invalid + 1) has \(rows[invalid].count) values; expected \(headers.count)")
        }
        guard !rows.isEmpty else { throw PDFOperationError.invalidInput("Form data table does not contain any data rows") }
        return FormDataTable(headers: headers, rows: rows)
    }

    static func renderBatchFilename(
        _ template: String,
        rowNumber: Int,
        headers: [String],
        values: [String]
    ) throws -> String {
        var rendered = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rendered.isEmpty else { throw PDFOperationError.invalidInput("Filename template cannot be empty") }
        rendered = rendered.replacingOccurrences(of: "{row}", with: String(rowNumber))
        for (index, header) in headers.enumerated() {
            rendered = rendered.replacingOccurrences(of: "{\(header)}", with: values[index])
        }
        if rendered.contains("{") || rendered.contains("}") {
            throw PDFOperationError.invalidInput("Filename template contains an unknown placeholder")
        }
        let forbidden = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        rendered = rendered.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        guard !rendered.isEmpty, rendered != ".pdf" else {
            throw PDFOperationError.invalidInput("Filename template produced an empty name")
        }
        if !rendered.lowercased().hasSuffix(".pdf") { rendered += ".pdf" }
        return rendered
    }

    static func validateBatchMappingVersion(_ mapping: PDFFormDataBatchMapping) throws {
        guard mapping.version == PDFFormDataBatchMapping.currentVersion else {
            throw PDFOperationError.invalidInput(
                "Unsupported batch form mapping version \(mapping.version); expected \(PDFFormDataBatchMapping.currentVersion)"
            )
        }
        let columns = mapping.columns.map { $0.column.trimmingCharacters(in: .whitespacesAndNewlines) }
        let fields = mapping.columns.map { $0.field.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !columns.contains(where: \.isEmpty), !fields.contains(where: \.isEmpty) else {
            throw PDFOperationError.invalidInput("Batch form mapping names cannot be empty")
        }
        guard Set(columns).count == columns.count else {
            throw PDFOperationError.invalidInput("Batch form mapping contains a duplicate table column")
        }
        guard Set(fields).count == fields.count else {
            throw PDFOperationError.invalidInput("Batch form mapping contains a duplicate PDF field")
        }
        guard !mapping.filenameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PDFOperationError.invalidInput("Batch filename template cannot be empty")
        }
    }
}
