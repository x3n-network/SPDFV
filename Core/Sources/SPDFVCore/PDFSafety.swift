import Foundation
import PDFKit

public enum PDFSafetyGateLevel: String, Codable, Comparable, CaseIterable, Sendable {
    case pass
    case warning
    case stop

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let rank: [Self: Int] = [.pass: 0, .warning: 1, .stop: 2]
        return rank[lhs, default: 0] < rank[rhs, default: 0]
    }
}

public struct PDFPermissionReport: Codable, Equatable, Sendable {
    public let printing: Bool
    public let copying: Bool
    public let documentChanges: Bool
    public let documentAssembly: Bool
    public let contentAccessibility: Bool
    public let commenting: Bool
    public let formFieldEntry: Bool

    public var restrictedCapabilities: [String] {
        [
            printing ? nil : "printing",
            copying ? nil : "content copying",
            documentChanges ? nil : "document changes",
            documentAssembly ? nil : "page assembly",
            contentAccessibility ? nil : "accessibility extraction",
            commenting ? nil : "annotations",
            formFieldEntry ? nil : "form entry"
        ].compactMap { $0 }
    }
}

public struct PDFSafetyGateIssue: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let level: PDFSafetyGateLevel
    public let title: String
    public let detail: String
}

public struct PDFSafetyGateReport: Codable, Equatable, Sendable {
    public let level: PDFSafetyGateLevel
    public let encrypted: Bool
    public let locked: Bool
    public let permissions: PDFPermissionReport
    public let certificateSignatureFields: [String]
    public let issues: [PDFSafetyGateIssue]

    public var canReadContent: Bool { !locked }
    public var canEditContent: Bool { !locked && permissions.documentChanges }
    public var canAssemblePages: Bool { !locked && permissions.documentAssembly }
    public var canAnnotate: Bool { !locked && permissions.commenting }
    public var canFillForms: Bool { !locked && permissions.formFieldEntry }

    public func decision(for capability: PDFMutationCapability) -> PDFPermissionDecision {
        guard !locked else {
            return PDFPermissionDecision(
                capability: capability,
                allowed: false,
                reason: "Unlock this PDF before \(capability.actionDescription)."
            )
        }
        let allowed = switch capability {
        case .contentCopying: permissions.copying
        case .contentEditing: permissions.documentChanges
        case .pageAssembly: permissions.documentAssembly
        case .annotations: permissions.commenting
        case .formEntry: permissions.formFieldEntry
        }
        return PDFPermissionDecision(
            capability: capability,
            allowed: allowed,
            reason: allowed ? nil : "This PDF does not allow \(capability.actionDescription)."
        )
    }
}

public enum PDFMutationCapability: String, Codable, CaseIterable, Sendable {
    case contentCopying
    case contentEditing
    case pageAssembly
    case annotations
    case formEntry

    public var actionDescription: String {
        switch self {
        case .contentCopying: "content copying"
        case .contentEditing: "content editing"
        case .pageAssembly: "page assembly"
        case .annotations: "annotation or form-field editing"
        case .formEntry: "form entry"
        }
    }
}

public struct PDFPermissionDecision: Codable, Equatable, Sendable {
    public let capability: PDFMutationCapability
    public let allowed: Bool
    public let reason: String?
}

public extension PDFOperations {
    static func requirePermission(_ capability: PDFMutationCapability, for document: PDFDocument) throws {
        let decision = safetyGate(for: document).decision(for: capability)
        guard decision.allowed else {
            throw PDFOperationError.operationFailed(decision.reason ?? "PDF permission denied")
        }
    }

    static func safetyGate(for document: PDFDocument) -> PDFSafetyGateReport {
        let permissions = PDFPermissionReport(
            printing: document.allowsPrinting,
            copying: document.allowsCopying,
            documentChanges: document.allowsDocumentChanges,
            documentAssembly: document.allowsDocumentAssembly,
            contentAccessibility: document.allowsContentAccessibility,
            commenting: document.allowsCommenting,
            formFieldEntry: document.allowsFormFieldEntry
        )
        let signatureFields = document.isLocked ? [] : certificateSignatureFields(in: document)
        var issues: [PDFSafetyGateIssue] = []

        if document.isLocked {
            issues.append(PDFSafetyGateIssue(
                id: "locked-document",
                level: .stop,
                title: "Password required",
                detail: "Unlock this PDF before SPDFV reads or changes its contents."
            ))
        } else {
            if document.isEncrypted {
                issues.append(PDFSafetyGateIssue(
                    id: "encrypted-document",
                    level: .warning,
                    title: "Encrypted document",
                    detail: "Treat an edited export as a separate copy and verify its password protection before sharing."
                ))
            }
            if !permissions.restrictedCapabilities.isEmpty {
                issues.append(PDFSafetyGateIssue(
                    id: "restricted-permissions",
                    level: .warning,
                    title: "Restricted permissions",
                    detail: "The PDF restricts: \(permissions.restrictedCapabilities.joined(separator: ", "))."
                ))
            }
            if !signatureFields.isEmpty {
                issues.append(PDFSafetyGateIssue(
                    id: "certificate-signatures",
                    level: .warning,
                    title: "Certificate signature fields",
                    detail: "Editing may invalidate an existing digital signature. Run Signature Verification against the saved file before making changes."
                ))
            }
        }

        return PDFSafetyGateReport(
            level: issues.map(\.level).max() ?? .pass,
            encrypted: document.isEncrypted,
            locked: document.isLocked,
            permissions: permissions,
            certificateSignatureFields: signatureFields,
            issues: issues
        )
    }

    private static func certificateSignatureFields(in document: PDFDocument) -> [String] {
        var names: [String] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for (annotationIndex, annotation) in page.annotations.enumerated()
                where annotation.widgetFieldType == .signature {
                let name = annotation.fieldName?.trimmingCharacters(in: .whitespacesAndNewlines)
                names.append(name?.isEmpty == false ? name! : "unnamed_\(pageIndex + 1)_\(annotationIndex + 1)")
            }
        }
        return Array(Set(names)).sorted()
    }
}
