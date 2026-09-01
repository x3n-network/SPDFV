import Foundation
import PDFKit

public enum PDFDoctorRepairAction: String, Codable, CaseIterable, Sendable {
    case ocrPages
    case normalizeForms
    case removeMetadata
}

public struct PDFDoctorRepairItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let action: PDFDoctorRepairAction
    public let title: String
    public let detail: String
    public let pages: [Int]
    public let fields: [String]
}

public struct PDFDoctorRepairPlan: Codable, Equatable, Sendable {
    public let before: PDFDoctorReport
    public let items: [PDFDoctorRepairItem]
    public let reviewIssueIDs: [String]
    public let warnings: [String]

    public var isEmpty: Bool { items.isEmpty }
    public var actions: [PDFDoctorRepairAction] { items.map(\.action) }
}

public struct PDFDoctorRepairVerification: Codable, Equatable, Sendable {
    public let before: PDFDoctorReport
    public let after: PDFDoctorReport
    public let appliedActions: [PDFDoctorRepairAction]
    public let pageCountPreserved: Bool
    public let remainingIssueIDs: [String]
}

public struct PDFDoctorRepairResult: Sendable {
    public let data: Data
    public let verification: PDFDoctorRepairVerification
    public let ocrReport: PDFOCRReport?
}

public extension PDFOperations {
    static func doctorRepairPlan(for document: PDFDocument) -> PDFDoctorRepairPlan {
        let before = diagnose(document)
        guard !document.isLocked else {
            return PDFDoctorRepairPlan(
                before: before,
                items: [],
                reviewIssueIDs: before.issues.map(\.id),
                warnings: ["Unlock the document before preparing a repair copy."]
            )
        }

        var items: [PDFDoctorRepairItem] = []
        let textPages = before.issues
            .first { $0.id == "no-searchable-text" || $0.id == "partial-searchable-text" }?.pages ?? []
        if !textPages.isEmpty {
            items.append(PDFDoctorRepairItem(
                id: "ocr-missing-text",
                action: .ocrPages,
                title: "Add searchable text",
                detail: "Run on-device OCR only on pages that currently lack searchable text.",
                pages: textPages,
                fields: []
            ))
        }

        if let orphanIssue = before.issues.first(where: { $0.id == "form-orphan-widgets" }) {
            items.append(PDFDoctorRepairItem(
                id: "normalize-orphan-forms",
                action: .normalizeForms,
                title: "Normalize form structure",
                detail: "Attach orphaned widgets to the canonical AcroForm tree and verify appearances.",
                pages: [],
                fields: orphanIssue.fields
            ))
        }

        if let metadataIssue = before.issues.first(where: { $0.id == "privacy-document-metadata" }) {
            items.append(PDFDoctorRepairItem(
                id: "remove-document-metadata",
                action: .removeMetadata,
                title: "Remove document metadata",
                detail: "Clear populated title, author, subject, keyword, creator, producer, and date attributes.",
                pages: [],
                fields: metadataIssue.fields
            ))
        }

        let repairIssueIDs = Set(items.flatMap { item -> [String] in
            switch item.action {
            case .ocrPages: ["no-searchable-text", "partial-searchable-text"]
            case .normalizeForms: ["form-orphan-widgets"]
            case .removeMetadata: ["privacy-document-metadata"]
            }
        })
        let reviewIssueIDs = before.issues.map(\.id).filter { !repairIssueIDs.contains($0) }
        var warnings: [String] = []
        if !before.issues.filter({ $0.id.contains("certificate-signatures") }).isEmpty {
            warnings.append("The repaired copy may not preserve certificate signature validity.")
        }
        if !reviewIssueIDs.isEmpty {
            warnings.append("Review-only findings will remain unchanged in the repaired copy.")
        }
        return PDFDoctorRepairPlan(
            before: before,
            items: items,
            reviewIssueIDs: reviewIssueIDs,
            warnings: warnings
        )
    }

    static func applyDoctorRepairs(
        data: Data,
        actions requestedActions: [PDFDoctorRepairAction]? = nil,
        ocrConfiguration: PDFOCRConfiguration = PDFOCRConfiguration()
    ) throws -> PDFDoctorRepairResult {
        guard let source = PDFDocument(data: data), !source.isLocked else {
            throw PDFOperationError.invalidInput("Input must be a readable, unlocked PDF")
        }
        let plan = doctorRepairPlan(for: source)
        let availableActions = plan.actions
        let actions = requestedActions ?? availableActions
        guard !actions.isEmpty else {
            throw PDFOperationError.invalidInput("Document Doctor did not find any automatic repairs to apply")
        }
        guard Set(actions).isSubset(of: Set(availableActions)) else {
            throw PDFOperationError.invalidInput("One or more requested repairs is not present in the current repair plan")
        }

        var stagedData = data
        var ocrReport: PDFOCRReport?
        if actions.contains(.ocrPages),
           let item = plan.items.first(where: { $0.action == .ocrPages }) {
            let result = try makeSearchable(
                data: stagedData,
                pageIndices: item.pages.map { $0 - 1 },
                configuration: ocrConfiguration
            )
            stagedData = result.data
            ocrReport = result.report
        }
        if actions.contains(.normalizeForms) {
            stagedData = try normalizeFormData(stagedData).data
        }
        if actions.contains(.removeMetadata) {
            stagedData = try dataByRemovingDoctorMetadata(stagedData)
        }

        guard let repaired = PDFDocument(data: stagedData), repaired.pageCount == source.pageCount else {
            throw PDFOperationError.operationFailed("The repaired copy failed PDF round-trip verification")
        }
        let after = diagnose(repaired)
        let remainingIssueIDs = after.issues.map(\.id)
        for action in actions {
            let repairedIssueIDs: Set<String> = switch action {
            case .ocrPages: ["no-searchable-text", "partial-searchable-text"]
            case .normalizeForms: ["form-orphan-widgets"]
            case .removeMetadata: ["privacy-document-metadata"]
            }
            guard repairedIssueIDs.isDisjoint(with: remainingIssueIDs) else {
                throw PDFOperationError.operationFailed("A Doctor repair did not pass before/after verification: \(action.rawValue)")
            }
        }
        return PDFDoctorRepairResult(
            data: stagedData,
            verification: PDFDoctorRepairVerification(
                before: plan.before,
                after: after,
                appliedActions: actions,
                pageCountPreserved: repaired.pageCount == source.pageCount,
                remainingIssueIDs: remainingIssueIDs
            ),
            ocrReport: ocrReport
        )
    }

    static func write(
        _ result: PDFDoctorRepairResult,
        to url: URL,
        overwrite: Bool = false
    ) throws {
        if FileManager.default.fileExists(atPath: url.path), !overwrite {
            throw PDFOperationError.outputExists("Output already exists; pass --force to replace it: \(url.path)")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try result.data.write(to: url, options: .atomic)
        guard let reopened = PDFDocument(url: url),
              reopened.pageCount == result.verification.after.pageCount else {
            throw PDFOperationError.operationFailed("Doctor repair output failed PDF round-trip verification")
        }
    }
}

private extension PDFOperations {
    static func dataByRemovingDoctorMetadata(_ data: Data) throws -> Data {
        guard let document = PDFDocument(data: data) else {
            throw PDFOperationError.invalidInput("Input is not a readable PDF")
        }
        // Blank the source values before serialization. PDFKit still synthesizes
        // Producer and timestamp fields, so the serialized Info object is
        // removed below as a second, byte-stable step.
        document.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: "",
            PDFDocumentAttribute.authorAttribute: "",
            PDFDocumentAttribute.subjectAttribute: "",
            PDFDocumentAttribute.keywordsAttribute: [String](),
            PDFDocumentAttribute.creatorAttribute: "",
            PDFDocumentAttribute.producerAttribute: NSNull(),
            PDFDocumentAttribute.creationDateAttribute: NSNull(),
            PDFDocumentAttribute.modificationDateAttribute: NSNull()
        ]
        guard let serialized = document.dataRepresentation() else {
            throw PDFOperationError.operationFailed("The metadata-cleaned copy could not be serialized")
        }
        let output = stripSerializedInfoDictionary(from: serialized)
        guard let reopened = PDFDocument(data: output) else {
            throw PDFOperationError.operationFailed("The metadata-cleaned copy could not be reopened")
        }
        let remainingMetadata = safeShareAudit(for: reopened).metadataKeys
        guard remainingMetadata.isEmpty else {
            throw PDFOperationError.operationFailed(
                "Document metadata remained after cleaning: \(remainingMetadata.joined(separator: ", "))"
            )
        }
        return output
    }

    /// PDFKit always adds an Info dictionary containing its producer and the
    /// current timestamps. Replacing only that dictionary's body with an empty
    /// dictionary keeps every byte offset stable, including classic xref tables.
    static func stripSerializedInfoDictionary(from data: Data) -> Data {
        var bytes = Array(data)
        let infoMarker = Array("/Info ".utf8)
        guard let infoRange = bytes.lastRange(of: infoMarker, before: bytes.count) else { return data }

        var cursor = infoRange.upperBound
        func consumeInteger() -> String {
            while cursor < bytes.count, bytes[cursor] == 0x20 { cursor += 1 }
            let start = cursor
            while cursor < bytes.count, bytes[cursor] >= 0x30, bytes[cursor] <= 0x39 { cursor += 1 }
            return String(decoding: bytes[start..<cursor], as: UTF8.self)
        }
        let objectNumber = consumeInteger()
        let generation = consumeInteger()
        guard !objectNumber.isEmpty, !generation.isEmpty else { return data }

        let objectMarker = Array("\(objectNumber) \(generation) obj".utf8)
        guard let objectRange = bytes.lastRange(of: objectMarker, before: infoRange.lowerBound) else { return data }
        let endMarker = Array("endobj".utf8)
        guard let endRange = bytes.firstRange(of: endMarker, after: objectRange.upperBound) else { return data }

        let body = objectRange.upperBound..<endRange.lowerBound
        guard body.count >= 6 else { return data }
        bytes.replaceSubrange(body, with: Array(repeating: 0x20, count: body.count))
        bytes.replaceSubrange(body.prefix(6), with: Array("\n<<>>\n".utf8))
        return Data(bytes)
    }
}

private extension Array where Element == UInt8 {
    func firstRange(of needle: [UInt8], after lowerBound: Int) -> Range<Int>? {
        guard !needle.isEmpty, lowerBound <= count - needle.count else { return nil }
        for start in lowerBound...(count - needle.count) where self[start..<(start + needle.count)].elementsEqual(needle) {
            return start..<(start + needle.count)
        }
        return nil
    }

    func lastRange(of needle: [UInt8], before upperBound: Int) -> Range<Int>? {
        guard !needle.isEmpty, upperBound >= needle.count else { return nil }
        for start in stride(from: upperBound - needle.count, through: 0, by: -1)
            where self[start..<(start + needle.count)].elementsEqual(needle) {
            return start..<(start + needle.count)
        }
        return nil
    }
}
