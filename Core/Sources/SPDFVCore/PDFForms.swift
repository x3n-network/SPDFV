import AppKit
import CoreGraphics
import Foundation
import PDFKit

public enum PDFFormFieldKind: String, Codable, Sendable {
    case text
    case checkbox
    case radio
    case pushButton
    case choice
    case signature
    case unknown
}

public struct PDFFormFieldReport: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let page: Int
    public let kind: PDFFormFieldKind
    public let value: String
    public let bounds: PDFRectReport
    public let choices: [String]
    public let readOnly: Bool
    public let hasNormalAppearance: Bool

    public init(
        id: String,
        name: String,
        page: Int,
        kind: PDFFormFieldKind,
        value: String,
        bounds: PDFRectReport,
        choices: [String],
        readOnly: Bool,
        hasNormalAppearance: Bool
    ) {
        self.id = id
        self.name = name
        self.page = page
        self.kind = kind
        self.value = value
        self.bounds = bounds
        self.choices = choices
        self.readOnly = readOnly
        self.hasNormalAppearance = hasNormalAppearance
    }
}

public struct PDFFormReport: Codable, Equatable, Sendable {
    public let fields: [PDFFormFieldReport]
    public let widgetCount: Int
    public let canonicalFieldCount: Int
    public let widgetsWithNormalAppearance: Int
    public let canonicalFieldNames: [String]
    public let orphanWidgetNames: [String]
    public let canonicalFieldsWithoutWidgets: [String]
    public let conflictingWidgetNames: [String]
    public let widgetsMissingAppearances: [String]

    public var isInteractive: Bool { widgetCount > 0 && canonicalFieldCount > 0 }
}

public enum PDFFormGateLevel: String, Codable, Comparable, CaseIterable, Sendable {
    case pass
    case warning
    case stop

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let rank: [Self: Int] = [.pass: 0, .warning: 1, .stop: 2]
        return rank[lhs, default: 0] < rank[rhs, default: 0]
    }
}

public struct PDFFormGateIssue: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let level: PDFFormGateLevel
    public let title: String
    public let detail: String
    public let fields: [String]
}

public struct PDFFormGateReport: Codable, Equatable, Sendable {
    public let level: PDFFormGateLevel
    public let widgetCount: Int
    public let canonicalFieldCount: Int
    public let issues: [PDFFormGateIssue]

    public var canSave: Bool { level != .stop }
}

public struct PDFFormFillResult: Sendable {
    public let data: Data
    public let report: PDFFormReport
}

public struct PDFFormFieldDraft: Codable, Equatable, Sendable {
    public let name: String
    public let kind: PDFFormFieldKind
    public let value: String
    public let choices: [String]

    public init(name: String, kind: PDFFormFieldKind, value: String = "", choices: [String] = []) {
        self.name = name
        self.kind = kind
        self.value = value
        self.choices = choices
    }
}

public extension PDFOperations {
    @discardableResult
    static func addFormField(
        _ draft: PDFFormFieldDraft,
        to document: PDFDocument,
        pageIndex: Int,
        bounds: CGRect
    ) throws -> PDFAnnotation {
        try requirePermission(.annotations, for: document)
        guard let page = document.page(at: pageIndex) else {
            throw PDFOperationError.invalidPageSelection("Page \(pageIndex + 1) is outside the document")
        }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PDFOperationError.invalidInput("Field name cannot be empty") }
        let existingNames = Set(formReport(for: document).fields.map(\.name))
        guard !existingNames.contains(name) else {
            throw PDFOperationError.invalidInput("A form field named \(name) already exists")
        }
        guard [.text, .checkbox, .choice].contains(draft.kind) else {
            throw PDFOperationError.invalidInput("Unsupported authored field type: \(draft.kind.rawValue)")
        }
        let pageBounds = page.bounds(for: .cropBox)
        let fieldBounds = bounds.standardized.intersection(pageBounds)
        guard fieldBounds.width >= 16, fieldBounds.height >= 16 else {
            throw PDFOperationError.invalidInput("Field bounds must occupy at least 16 by 16 points on the page")
        }
        let choices = draft.choices.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if draft.kind == .choice, choices.count < 2 {
            throw PDFOperationError.invalidInput("Choice fields require at least two options")
        }

        let annotation = PDFAnnotation(bounds: fieldBounds, forType: .widget, withProperties: nil)
        let fieldInk = NSColor(srgbRed: 0.08, green: 0.10, blue: 0.14, alpha: 1)
        annotation.backgroundColor = NSColor(white: 0.98, alpha: 0.98)
        annotation.color = NSColor(srgbRed: 0.22, green: 0.35, blue: 0.58, alpha: 0.9)
        let border = PDFBorder()
        border.lineWidth = 1
        annotation.border = border

        switch draft.kind {
        case .text:
            annotation.widgetFieldType = .text
            annotation.widgetStringValue = draft.value
            annotation.font = NSFont.systemFont(ofSize: 12)
            annotation.fontColor = fieldInk
        case .checkbox:
            annotation.widgetFieldType = .button
            annotation.widgetControlType = .checkBoxControl
            annotation.buttonWidgetStateString = "Yes"
            annotation.buttonWidgetState = truthyFormValue(draft.value) ? .onState : .offState
        case .choice:
            annotation.widgetFieldType = .choice
            annotation.isListChoice = false
            annotation.choices = choices
            annotation.values = choices
            annotation.widgetStringValue = choices.contains(draft.value) ? draft.value : choices[0]
            annotation.font = NSFont.systemFont(ofSize: 12)
            annotation.fontColor = fieldInk
        default:
            break
        }
        // PDFKit derives an automatic name when the widget type changes. Assign
        // the intended name last so it survives serialization.
        annotation.fieldName = name
        page.addAnnotation(annotation)
        return annotation
    }

    static func normalizeFormData(_ data: Data) throws -> PDFFormFillResult {
        guard let document = PDFDocument(data: data) else {
            throw PDFOperationError.invalidInput("Input is not a readable PDF")
        }
        try requirePermission(.formEntry, for: document)
        let initial = formReport(for: document)
        guard initial.widgetCount > 0 else {
            throw PDFOperationError.invalidInput("PDF does not contain any interactive form widgets")
        }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where isFormWidget(annotation) {
                switch formFieldKind(annotation) {
                case .checkbox, .radio:
                    annotation.buttonWidgetState = annotation.buttonWidgetState
                case .pushButton:
                    continue
                default:
                    annotation.widgetStringValue = annotation.widgetStringValue ?? ""
                }
            }
        }

        guard let output = document.dataRepresentation(), let reopened = PDFDocument(data: output) else {
            throw PDFOperationError.operationFailed("The authored form could not be serialized")
        }
        let report = formReport(for: reopened)
        let expectedNames = Set(initial.fields.map(\.name))
        let actualNames = Set(report.fields.map(\.name))
        guard expectedNames.isSubset(of: actualNames), report.canonicalFieldCount > 0 else {
            throw PDFOperationError.operationFailed("The authored fields were not attached to the canonical AcroForm tree")
        }
        guard report.fields.allSatisfy(\.hasNormalAppearance) else {
            throw PDFOperationError.operationFailed("One or more authored fields has no normal appearance")
        }
        return PDFFormFillResult(data: output, report: report)
    }

    static func formReport(for document: PDFDocument) -> PDFFormReport {
        let serialized = document.dataRepresentation()
        let audit = serialized.map(PDFFormStructureAudit.init(data:)) ?? PDFFormStructureAudit.empty
        var appearanceIndex = audit.widgetNormalAppearances.makeIterator()
        let fields = (0..<document.pageCount).flatMap { pageIndex -> [PDFFormFieldReport] in
            guard let page = document.page(at: pageIndex) else { return [] }
            var widgetIndex = 0
            return page.annotations.compactMap { annotation -> PDFFormFieldReport? in
                guard isFormWidget(annotation) else { return nil }
                defer { widgetIndex += 1 }
                let name = annotation.fieldName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedName = name?.isEmpty == false ? name! : "unnamed_\(pageIndex + 1)_\(widgetIndex + 1)"
                let hasAppearance = appearanceIndex.next() ?? false
                return PDFFormFieldReport(
                    id: "\(pageIndex + 1):\(widgetIndex + 1):\(resolvedName)",
                    name: resolvedName,
                    page: pageIndex + 1,
                    kind: formFieldKind(annotation),
                    value: formValue(annotation),
                    bounds: PDFRectReport(annotation.bounds),
                    choices: annotation.choices ?? [],
                    readOnly: annotation.isReadOnly,
                    hasNormalAppearance: hasAppearance
                )
            }
        }
        let canonicalNames = Array(Set(audit.canonicalFieldNames)).sorted()
        let widgetNames = Set(fields.map(\.name))
        let grouped = Dictionary(grouping: fields, by: \.name)
        let conflicts = grouped.compactMap { name, widgets -> String? in
            let kinds = Set(widgets.map(\.kind))
            let values = Set(widgets.map(\.value))
            if kinds.count > 1 { return name }
            if kinds == [.radio] { return nil }
            return values.count > 1 ? name : nil
        }.sorted()
        return PDFFormReport(
            fields: fields,
            widgetCount: fields.count,
            canonicalFieldCount: canonicalNames.count,
            widgetsWithNormalAppearance: fields.filter(\.hasNormalAppearance).count,
            canonicalFieldNames: canonicalNames,
            orphanWidgetNames: widgetNames.subtracting(canonicalNames).sorted(),
            canonicalFieldsWithoutWidgets: Set(canonicalNames).subtracting(widgetNames).sorted(),
            conflictingWidgetNames: conflicts,
            widgetsMissingAppearances: fields.filter { !$0.hasNormalAppearance }.map(\.name).sorted()
        )
    }

    static func formGate(for document: PDFDocument) -> PDFFormGateReport {
        formGate(for: formReport(for: document))
    }

    static func formGate(for report: PDFFormReport) -> PDFFormGateReport {
        var issues: [PDFFormGateIssue] = []
        if !report.widgetsMissingAppearances.isEmpty {
            issues.append(PDFFormGateIssue(
                id: "missing-appearances",
                level: .stop,
                title: "Missing appearances",
                detail: "These widgets may render blank or stale after save.",
                fields: report.widgetsMissingAppearances
            ))
        }
        if !report.conflictingWidgetNames.isEmpty {
            issues.append(PDFFormGateIssue(
                id: "conflicting-widgets",
                level: .stop,
                title: "Conflicting widget values",
                detail: "Repeated field names disagree on their type or current value.",
                fields: report.conflictingWidgetNames
            ))
        }
        if !report.orphanWidgetNames.isEmpty {
            issues.append(PDFFormGateIssue(
                id: "orphan-widgets",
                level: .warning,
                title: "Widgets need attachment",
                detail: "These page widgets are missing from the canonical field tree. SPDFV will repair them when saving.",
                fields: report.orphanWidgetNames
            ))
        }
        if !report.canonicalFieldsWithoutWidgets.isEmpty {
            issues.append(PDFFormGateIssue(
                id: "fields-without-widgets",
                level: .warning,
                title: "Fields have no page widget",
                detail: "Canonical fields exist without a visible control on any page.",
                fields: report.canonicalFieldsWithoutWidgets
            ))
        }
        let level = issues.map(\.level).max() ?? .pass
        return PDFFormGateReport(
            level: level,
            widgetCount: report.widgetCount,
            canonicalFieldCount: report.canonicalFieldCount,
            issues: issues
        )
    }

    static func fillForm(data: Data, values: [String: String]) throws -> PDFFormFillResult {
        guard let document = PDFDocument(data: data) else {
            throw PDFOperationError.invalidInput("Input is not a readable PDF")
        }
        let existing = formReport(for: document)
        let names = Set(existing.fields.map(\.name))
        let missing = Set(values.keys).subtracting(names).sorted()
        guard missing.isEmpty else {
            throw PDFOperationError.invalidInput("Form fields not found: \(missing.joined(separator: ", "))")
        }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where isFormWidget(annotation) {
                guard let name = annotation.fieldName, let value = values[name] else { continue }
                guard !annotation.isReadOnly else {
                    throw PDFOperationError.operationFailed("Form field is read-only: \(name)")
                }
                switch formFieldKind(annotation) {
                case .checkbox, .radio:
                    annotation.buttonWidgetState = truthyFormValue(value) ? .onState : .offState
                case .pushButton:
                    throw PDFOperationError.operationFailed("Push buttons cannot be assigned a value: \(name)")
                default:
                    annotation.widgetStringValue = value
                }
            }
        }

        guard let output = document.dataRepresentation(), let reopened = PDFDocument(data: output) else {
            throw PDFOperationError.operationFailed("The filled PDF could not be serialized")
        }
        let report = formReport(for: reopened)
        guard report.canonicalFieldCount > 0 else {
            throw PDFOperationError.operationFailed("The PDF has widgets but no canonical AcroForm field tree")
        }
        let valuesByName = Dictionary(grouping: report.fields, by: \.name)
        for (name, expected) in values {
            guard let widgets = valuesByName[name], !widgets.isEmpty else {
                throw PDFOperationError.operationFailed("Filled field disappeared after writing: \(name)")
            }
            let matches = widgets.allSatisfy { field in
                switch field.kind {
                case .checkbox, .radio:
                    truthyFormValue(field.value) == truthyFormValue(expected)
                default:
                    field.value == expected
                }
            }
            guard matches else {
                throw PDFOperationError.operationFailed("Field value did not survive round-trip: \(name)")
            }
            guard widgets.allSatisfy(\.hasNormalAppearance) else {
                throw PDFOperationError.operationFailed("Field has no normal appearance after writing: \(name)")
            }
        }
        return PDFFormFillResult(data: output, report: report)
    }

    static func applyFormValue(_ value: String, named name: String, in document: PDFDocument) throws {
        try requirePermission(.formEntry, for: document)
        let matching = (0..<document.pageCount).flatMap { document.page(at: $0)?.annotations ?? [] }
            .filter { isFormWidget($0) && $0.fieldName == name }
        guard !matching.isEmpty else { throw PDFOperationError.invalidInput("Form field not found: \(name)") }
        for annotation in matching {
            guard !annotation.isReadOnly else { throw PDFOperationError.operationFailed("Form field is read-only: \(name)") }
            switch formFieldKind(annotation) {
            case .checkbox, .radio:
                annotation.buttonWidgetState = truthyFormValue(value) ? .onState : .offState
            case .pushButton:
                throw PDFOperationError.operationFailed("Push buttons cannot be assigned a value: \(name)")
            default:
                annotation.widgetStringValue = value
            }
        }
    }

    /// Renames every page widget that belongs to the same logical field.
    /// Repeated widgets intentionally move together so the canonical AcroForm
    /// name cannot diverge between pages.
    @discardableResult
    static func renameFormField(named currentName: String, to proposedName: String, in document: PDFDocument) throws -> Int {
        try requirePermission(.annotations, for: document)
        let source = currentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw PDFOperationError.invalidInput("Current field name cannot be empty") }
        guard !destination.isEmpty else { throw PDFOperationError.invalidInput("New field name cannot be empty") }

        let widgets = (0..<document.pageCount).flatMap { document.page(at: $0)?.annotations ?? [] }
            .filter { isFormWidget($0) }
        let matching = widgets.filter { $0.fieldName == source }
        guard !matching.isEmpty else { throw PDFOperationError.invalidInput("Form field not found: \(source)") }
        if source == destination { return matching.count }

        let names = Set(widgets.compactMap { $0.fieldName?.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard !names.contains(destination) else {
            throw PDFOperationError.invalidInput("A form field named \(destination) already exists")
        }

        for annotation in matching {
            annotation.fieldName = destination
            annotation.modificationDate = Date()
        }
        return matching.count
    }

    private static func formFieldKind(_ annotation: PDFAnnotation) -> PDFFormFieldKind {
        switch annotation.widgetFieldType {
        case .text: return .text
        case .choice: return .choice
        case .signature: return .signature
        case .button:
            switch annotation.widgetControlType {
            case .checkBoxControl: return .checkbox
            case .radioButtonControl: return .radio
            case .pushButtonControl: return .pushButton
            case .unknownControl: return .unknown
            @unknown default: return .unknown
            }
        default: return .unknown
        }
    }

    private static func formValue(_ annotation: PDFAnnotation) -> String {
        switch formFieldKind(annotation) {
        case .checkbox, .radio:
            annotation.buttonWidgetState == .onState ? "true" : "false"
        default:
            annotation.widgetStringValue ?? ""
        }
    }

    private static func truthyFormValue(_ value: String) -> Bool {
        ["1", "true", "yes", "on", "checked"].contains(value.lowercased())
    }

    private static func isFormWidget(_ annotation: PDFAnnotation) -> Bool {
        annotation.type?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "Widget"
    }
}

private struct PDFFormStructureAudit {
    let canonicalFieldCount: Int
    let canonicalFieldNames: [String]
    let widgetNormalAppearances: [Bool]

    static let empty = PDFFormStructureAudit(canonicalFieldCount: 0, canonicalFieldNames: [], widgetNormalAppearances: [])

    private init(canonicalFieldCount: Int, canonicalFieldNames: [String], widgetNormalAppearances: [Bool]) {
        self.canonicalFieldCount = canonicalFieldCount
        self.canonicalFieldNames = canonicalFieldNames
        self.widgetNormalAppearances = widgetNormalAppearances
    }

    init(data: Data) {
        guard
            let provider = CGDataProvider(data: data as CFData),
            let document = CGPDFDocument(provider),
            let catalog = document.catalog
        else {
            self = .empty
            return
        }

        var acroForm: CGPDFDictionaryRef?
        var fields: CGPDFArrayRef?
        if CGPDFDictionaryGetDictionary(catalog, "AcroForm", &acroForm),
           let acroForm,
           CGPDFDictionaryGetArray(acroForm, "Fields", &fields),
           let fields {
            canonicalFieldNames = Self.collectFieldNames(fields, prefix: nil)
            canonicalFieldCount = canonicalFieldNames.count
        } else {
            canonicalFieldNames = []
            canonicalFieldCount = 0
        }

        var appearances: [Bool] = []
        for pageNumber in 1...document.numberOfPages {
            guard let page = document.page(at: pageNumber), let pageDictionary = page.dictionary else { continue }
            var annotations: CGPDFArrayRef?
            guard CGPDFDictionaryGetArray(pageDictionary, "Annots", &annotations), let annotations else { continue }
            for index in 0..<CGPDFArrayGetCount(annotations) {
                var dictionary: CGPDFDictionaryRef?
                guard CGPDFArrayGetDictionary(annotations, index, &dictionary), let dictionary else { continue }
                var subtype: UnsafePointer<CChar>?
                guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype),
                      subtype.map({ String(cString: $0) }) == "Widget" else { continue }
                var appearance: CGPDFDictionaryRef?
                var normal: CGPDFObjectRef?
                let hasNormal = CGPDFDictionaryGetDictionary(dictionary, "AP", &appearance)
                    && appearance.map { CGPDFDictionaryGetObject($0, "N", &normal) } == true
                    && normal != nil
                appearances.append(hasNormal)
            }
        }
        widgetNormalAppearances = appearances
    }

    private static func collectFieldNames(_ fields: CGPDFArrayRef, prefix: String?) -> [String] {
        var names: [String] = []
        for index in 0..<CGPDFArrayGetCount(fields) {
            var field: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(fields, index, &field), let field else { continue }
            var nameString: CGPDFStringRef?
            let partialName: String? = if CGPDFDictionaryGetString(field, "T", &nameString), let nameString {
                CGPDFStringCopyTextString(nameString) as String?
            } else {
                nil
            }
            let fullName = [prefix, partialName]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: ".")
            var kids: CGPDFArrayRef?
            let hasKids = CGPDFDictionaryGetArray(field, "Kids", &kids) && kids != nil
            var fieldType: UnsafePointer<CChar>?
            let hasFieldType = CGPDFDictionaryGetName(field, "FT", &fieldType)
            if partialName?.isEmpty == false, hasFieldType || !hasKids { names.append(fullName) }
            if hasKids, let kids {
                names.append(contentsOf: collectFieldNames(kids, prefix: fullName.isEmpty ? prefix : fullName))
            }
        }
        return names
    }
}
