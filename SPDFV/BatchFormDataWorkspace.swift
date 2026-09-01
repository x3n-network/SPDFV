import AppKit
import Combine
import PDFKit
import SPDFVCore
import SwiftUI
import UniformTypeIdentifiers

struct BatchFormDataWorkspace: View {
    @ObservedObject var session: DocumentSession
    @StateObject private var model: BatchFormDataWorkspaceModel

    init(session: DocumentSession) {
        self.session = session
        _model = StateObject(wrappedValue: BatchFormDataWorkspaceModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                mappingColumn
                    .frame(minWidth: 310, idealWidth: 350)
                reportColumn
                    .frame(minWidth: 300, maxWidth: .infinity)
            }
        }
        .background(SPDFVTheme.canvas)
        .foregroundStyle(SPDFVTheme.navigatorText)
        .accessibilityIdentifier("form-data.batch.workspace")
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BATCH FORM DATA")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.1)
                Text(model.tableName ?? "Choose a UTF-8 CSV or TSV file")
                    .font(.system(size: 10))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }
            Spacer()
            Button("LOAD MAPPING", action: model.loadMapping)
                .buttonStyle(.bordered)
            Button("SAVE MAPPING", action: model.saveMapping)
                .buttonStyle(.bordered)
                .disabled(model.columns.isEmpty)
            Button("CHOOSE DATA…", action: model.chooseTable)
                .buttonStyle(.borderedProminent)
                .tint(SPDFVTheme.cobalt)
                .accessibilityIdentifier("form-data.batch.choose")
        }
        .padding(14)
        .background(SPDFVTheme.navigator)
    }

    private var mappingColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("COLUMN MAPPING")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(0.9)
                .padding(12)
            Divider()
            if model.columns.isEmpty {
                Text("Column headers appear here. Matching PDF field names are mapped automatically; aliases can be assigned manually.")
                    .font(.system(size: 11))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(model.columns, id: \.self) { column in
                            HStack {
                                Text(column)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Picker("PDF field", selection: model.binding(for: column)) {
                                    Text("Ignore").tag("")
                                    ForEach(model.availableFields, id: \.self) { field in
                                        Text(field).tag(field)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 160)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(SPDFVTheme.navigatorInset)
                        }
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("FILENAME TEMPLATE")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorFaint)
                TextField("completed-{row}.pdf", text: $model.filenameTemplate)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.filenameTemplate) { _, _ in model.invalidate() }
                Text("Use {row} or a column header such as {Case ID}.")
                    .font(.system(size: 9))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }
            .padding(12)
            HStack {
                Button("PREFLIGHT ALL ROWS", action: model.validate)
                    .buttonStyle(.bordered)
                    .disabled(!model.canValidate || model.isWorking)
                    .accessibilityIdentifier("form-data.batch.validate")
                Button(model.isWorking ? "WORKING…" : "CREATE PDFS…", action: model.createPDFs)
                    .buttonStyle(.borderedProminent)
                    .tint(SPDFVTheme.cobalt)
                    .disabled(model.report?.canWrite != true || model.isWorking)
                    .accessibilityIdentifier("form-data.batch.create")
            }
            .padding(12)
        }
        .background(SPDFVTheme.navigator)
    }

    private var reportColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let report = model.report {
                HStack {
                    Text(report.canWrite ? "READY TO WRITE" : "PREFLIGHT NEEDS ATTENTION")
                    Spacer()
                    Text("\(report.validRows) READY · \(report.invalidRows) BLOCKED")
                }
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(report.canWrite ? SPDFVTheme.paleCobalt : SPDFVTheme.redaction)
                .padding(12)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(report.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("ROW \(item.row)")
                                        .font(.system(size: 9, weight: .black, design: .monospaced))
                                    Spacer()
                                    Text(item.outputName ?? "NO OUTPUT NAME")
                                        .font(.system(size: 9, design: .monospaced))
                                        .lineLimit(1)
                                }
                                if item.errors.isEmpty {
                                    Text("\(item.validation?.matchedFields ?? 0) fields validated")
                                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                                } else {
                                    ForEach(item.errors, id: \.self) { error in
                                        Text(error).foregroundStyle(SPDFVTheme.redaction)
                                    }
                                    ForEach(item.validation?.issues.prefix(3) ?? []) { issue in
                                        Text("\(issue.name): \(issue.detail)")
                                            .foregroundStyle(SPDFVTheme.redaction)
                                    }
                                }
                            }
                            .font(.system(size: 9))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SPDFVTheme.navigatorInset)
                        }
                    }
                }
            } else {
                Text("Preflight validates every row, mapped field, choice value, and output filename before SPDFV writes any PDF.")
                    .font(.system(size: 11))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let status = model.statusMessage {
                Divider()
                HStack {
                    Text(status)
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    if model.lastOutputDirectory != nil {
                        Button("SHOW OUTPUT", action: model.revealOutput)
                            .buttonStyle(.bordered)
                    }
                }
                .padding(12)
            }
        }
        .background(SPDFVTheme.canvas)
    }
}

@MainActor
private final class BatchFormDataWorkspaceModel: ObservableObject {
    @Published var columns: [String] = []
    @Published var mappedFields: [String: String] = [:]
    @Published var filenameTemplate = "completed-{row}.pdf"
    @Published var report: PDFFormDataBatchReport?
    @Published var isWorking = false
    @Published var statusMessage: String?
    @Published var lastOutputDirectory: URL?
    @Published var tableName: String?

    let availableFields: [String]
    private weak var session: DocumentSession?
    private var tableData: Data?
    private var format: PDFFormDataTableFormat?

    init(session: DocumentSession) {
        self.session = session
        availableFields = Array(Set(session.formFields.compactMap { field in
            guard !field.readOnly, ![.signature, .pushButton, .unknown].contains(field.kind) else { return nil }
            return field.name
        })).sorted()
    }

    var canValidate: Bool {
        tableData != nil && format != nil && mappedFields.values.contains { !$0.isEmpty }
    }

    func binding(for column: String) -> Binding<String> {
        Binding(
            get: { self.mappedFields[column] ?? "" },
            set: {
                self.mappedFields[column] = $0
                self.report = nil
                self.lastOutputDirectory = nil
            }
        )
    }

    func chooseTable() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["csv", "tsv", "tab"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose UTF-8 CSV or TSV data; values remain on this Mac"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let selectedFormat: PDFFormDataTableFormat = url.pathExtension.lowercased() == "csv" ? .csv : .tsv
            let summary = try PDFOperations.formDataTableSummary(data, format: selectedFormat)
            tableData = data
            format = selectedFormat
            columns = summary.columns
            tableName = url.lastPathComponent
            mappedFields = Dictionary(uniqueKeysWithValues: columns.map { column in
                let automatic = availableFields.first { $0.caseInsensitiveCompare(column) == .orderedSame } ?? ""
                return (column, mappedFields[column].flatMap { $0.isEmpty ? nil : $0 } ?? automatic)
            })
            report = nil
            statusMessage = "Loaded \(summary.rowCount) row\(summary.rowCount == 1 ? "" : "s"). Map aliases, then preflight."
            lastOutputDirectory = nil
        } catch {
            fail(error)
        }
    }

    func loadMapping() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let mapping = try PDFOperations.decodeFormDataBatchMapping(Data(contentsOf: url))
            mappedFields = Dictionary(uniqueKeysWithValues: mapping.columns.map { ($0.column, $0.field) })
            filenameTemplate = mapping.filenameTemplate
            report = nil
            statusMessage = "Loaded reusable mapping \(url.lastPathComponent)."
        } catch {
            fail(error)
        }
    }

    func saveMapping() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "form-data-mapping.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PDFOperations.encodeFormDataBatchMapping(mapping).write(to: url, options: .atomic)
            statusMessage = "Saved reusable column mapping."
        } catch {
            fail(error)
        }
    }

    func validate() {
        guard let inputs else { return }
        isWorking = true
        report = nil
        statusMessage = "Validating every row…"
        Task { @MainActor in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try PDFOperations.validateFormDataBatch(
                        templateData: inputs.template,
                        tableData: inputs.table,
                        format: inputs.format,
                        mapping: inputs.mapping
                    )
                }.value
                report = result
                statusMessage = result.canWrite
                    ? "All rows passed. No PDFs have been written yet."
                    : "Resolve blocked rows or mappings before creating PDFs."
            } catch {
                fail(error)
            }
            isWorking = false
        }
    }

    func createPDFs() {
        guard let inputs, report?.canWrite == true else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose an output folder. Existing filenames will block the entire batch."
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        isWorking = true
        lastOutputDirectory = nil
        statusMessage = "Generating verified PDFs…"
        let activityID = ActivityCenterStore.shared.begin(
            kind: .batch,
            title: "Batch form data",
            detail: "Generating \(report?.validRows ?? 0) completed PDFs",
            documentName: session?.displayName
        )
        Task { @MainActor in
            do {
                let count = try await Task.detached(priority: .userInitiated) {
                    let result = try PDFOperations.fillFormBatch(
                        templateData: inputs.template,
                        tableData: inputs.table,
                        format: inputs.format,
                        mapping: inputs.mapping
                    )
                    let destinations = result.outputs.map { directory.appendingPathComponent($0.name) }
                    if let existing = destinations.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                        throw PDFOperationError.outputExists("Output already exists; choose another folder: \(existing.lastPathComponent)")
                    }
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    for output in result.outputs {
                        try output.data.write(to: directory.appendingPathComponent(output.name), options: .atomic)
                    }
                    return result.outputs.count
                }.value
                lastOutputDirectory = directory
                statusMessage = "Created \(count) verified PDF\(count == 1 ? "" : "s")."
                ActivityCenterStore.shared.finish(activityID, detail: "Created \(count) completed PDFs", outputURL: directory)
            } catch {
                fail(error)
                ActivityCenterStore.shared.fail(activityID, detail: error.localizedDescription)
            }
            isWorking = false
        }
    }

    func revealOutput() {
        guard let lastOutputDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastOutputDirectory])
    }

    func invalidate() {
        report = nil
        lastOutputDirectory = nil
    }

    private var mapping: PDFFormDataBatchMapping {
        PDFFormDataBatchMapping(
            columns: columns.compactMap { column in
                guard let field = mappedFields[column], !field.isEmpty else { return nil }
                return PDFFormDataColumnMapping(column: column, field: field)
            },
            filenameTemplate: filenameTemplate
        )
    }

    private var inputs: (template: Data, table: Data, format: PDFFormDataTableFormat, mapping: PDFFormDataBatchMapping)? {
        guard let template = session?.document?.dataRepresentation(), let tableData, let format else { return nil }
        return (template, tableData, format, mapping)
    }

    private func fail(_ error: Error) {
        let message = (error as? PDFOperationError)?.description ?? error.localizedDescription
        statusMessage = message
        session?.errorMessage = message
    }
}
