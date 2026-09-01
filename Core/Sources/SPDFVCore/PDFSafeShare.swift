import Foundation
import PDFKit

public enum PDFSafeShareCategory: String, Codable, CaseIterable, Sendable {
    case access
    case metadata
    case review
    case forms
    case attachments
    case signatures
}

public struct PDFSafeShareFinding: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let level: PDFSafetyGateLevel
    public let category: PDFSafeShareCategory
    public let title: String
    public let detail: String
    public let pages: [Int]
}

public struct PDFSafeShareReport: Codable, Equatable, Sendable {
    public let level: PDFSafetyGateLevel
    public let pages: Int
    public let encrypted: Bool
    public let locked: Bool
    public let searchableTextPages: Int
    public let searchableTextCharacters: Int
    public let metadataKeys: [String]
    public let reviewAnnotationCount: Int
    public let reviewAnnotationPages: [Int]
    public let annotationsWithContents: Int
    public let filledFormFields: [String]
    public let fileAttachmentCount: Int
    public let certificateSignatureFields: [String]
    public let findings: [PDFSafeShareFinding]

    public var isReadyToShare: Bool { level == .pass }
}

public extension PDFOperations {
    /// Inspects common sharing hazards without copying metadata values, annotation
    /// contents, or form values into the resulting report.
    static func safeShareAudit(for document: PDFDocument) -> PDFSafeShareReport {
        let gate = safetyGate(for: document)
        guard !document.isLocked else {
            let finding = PDFSafeShareFinding(
                id: "locked-document",
                level: .stop,
                category: .access,
                title: "Password required",
                detail: "Unlock this PDF before SPDFV can inspect content that may travel with it.",
                pages: []
            )
            return PDFSafeShareReport(
                level: .stop,
                pages: document.pageCount,
                encrypted: document.isEncrypted,
                locked: true,
                searchableTextPages: 0,
                searchableTextCharacters: 0,
                metadataKeys: [],
                reviewAnnotationCount: 0,
                reviewAnnotationPages: [],
                annotationsWithContents: 0,
                filledFormFields: [],
                fileAttachmentCount: 0,
                certificateSignatureFields: [],
                findings: [finding]
            )
        }

        let metadataKeys = safeShareMetadataKeys(in: document)
        let formReport = formReport(for: document)
        let filledFields = Array(Set(formReport.fields.compactMap { field -> String? in
            guard field.kind != .signature, fieldContainsShareableValue(field) else { return nil }
            return field.name
        })).sorted()

        var searchableTextPages = 0
        var searchableTextCharacters = 0
        var reviewAnnotationCount = 0
        var annotationsWithContents = 0
        var reviewPages = Set<Int>()
        var fileAttachmentCount = 0

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty {
                searchableTextPages += 1
                searchableTextCharacters += text.count
            }

            for annotation in page.annotations where !annotation.isSafeShareFormWidget {
                if annotation.isSafeShareFileAttachment {
                    fileAttachmentCount += 1
                    continue
                }
                reviewAnnotationCount += 1
                reviewPages.insert(pageIndex + 1)
                let contents = annotation.contents?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let author = annotation.userName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !contents.isEmpty || !author.isEmpty { annotationsWithContents += 1 }
            }
        }

        let reviewAnnotationPages = reviewPages.sorted()
        var findings: [PDFSafeShareFinding] = []
        if document.isEncrypted {
            findings.append(PDFSafeShareFinding(
                id: "encrypted-document",
                level: .warning,
                category: .access,
                title: "Verify export protection",
                detail: "This PDF is encrypted. Confirm that the shared copy retains the intended password and permissions.",
                pages: []
            ))
        }
        if !metadataKeys.isEmpty {
            findings.append(PDFSafeShareFinding(
                id: "document-metadata",
                level: .warning,
                category: .metadata,
                title: "Document metadata",
                detail: "The PDF contains (metadataKeys.count) populated metadata field\(metadataKeys.count == 1 ? "" : "s"). Review or remove them before sharing.",
                pages: []
            ))
        }
        if reviewAnnotationCount > 0 {
            findings.append(PDFSafeShareFinding(
                id: "review-annotations",
                level: .warning,
                category: .review,
                title: "Review annotations",
                detail: "The PDF contains (reviewAnnotationCount) non-form annotation\(reviewAnnotationCount == 1 ? "" : "s"), including (annotationsWithContents) with text or author information.",
                pages: reviewAnnotationPages
            ))
        }
        if !filledFields.isEmpty {
            findings.append(PDFSafeShareFinding(
                id: "filled-form-fields",
                level: .warning,
                category: .forms,
                title: "Filled form fields",
                detail: "The PDF contains (filledFields.count) field\(filledFields.count == 1 ? "" : "s") with values. The report lists field names only.",
                pages: []
            ))
        }
        if fileAttachmentCount > 0 {
            findings.append(PDFSafeShareFinding(
                id: "file-attachments",
                level: .warning,
                category: .attachments,
                title: "Embedded attachments",
                detail: "The PDF contains (fileAttachmentCount) file attachment\(fileAttachmentCount == 1 ? "" : "s") that will travel with the document.",
                pages: []
            ))
        }
        if !gate.certificateSignatureFields.isEmpty {
            findings.append(PDFSafeShareFinding(
                id: "certificate-signatures",
                level: .warning,
                category: .signatures,
                title: "Certificate signature fields",
                detail: "The PDF contains signature fields. SPDFV has detected but not cryptographically validated them.",
                pages: []
            ))
        }

        return PDFSafeShareReport(
            level: findings.map(\.level).max() ?? .pass,
            pages: document.pageCount,
            encrypted: document.isEncrypted,
            locked: false,
            searchableTextPages: searchableTextPages,
            searchableTextCharacters: searchableTextCharacters,
            metadataKeys: metadataKeys,
            reviewAnnotationCount: reviewAnnotationCount,
            reviewAnnotationPages: reviewAnnotationPages,
            annotationsWithContents: annotationsWithContents,
            filledFormFields: filledFields,
            fileAttachmentCount: fileAttachmentCount,
            certificateSignatureFields: gate.certificateSignatureFields,
            findings: findings
        )
    }

    private static func safeShareMetadataKeys(in document: PDFDocument) -> [String] {
        let attributes = document.documentAttributes ?? [:]
        let candidates: [(String, PDFDocumentAttribute)] = [
            ("title", .titleAttribute),
            ("author", .authorAttribute),
            ("subject", .subjectAttribute),
            ("keywords", .keywordsAttribute),
            ("creator", .creatorAttribute),
            ("producer", .producerAttribute),
            ("creationDate", .creationDateAttribute),
            ("modificationDate", .modificationDateAttribute)
        ]
        return candidates.compactMap { name, key in
            guard let value = attributes[key] else { return nil }
            if let string = value as? String, string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil
            }
            if let values = value as? [Any], values.isEmpty { return nil }
            return name
        }
    }

    private static func fieldContainsShareableValue(_ field: PDFFormFieldReport) -> Bool {
        let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if field.kind == .checkbox || field.kind == .radio {
            return !["off", "no", "false", "0"].contains(value.lowercased())
        }
        return true
    }
}

private extension PDFAnnotation {
    var isSafeShareFormWidget: Bool {
        type?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "Widget"
    }

    var isSafeShareFileAttachment: Bool {
        type?.trimmingCharacters(in: CharacterSet(charactersIn: "/")).caseInsensitiveCompare("FileAttachment") == .orderedSame
    }
}
