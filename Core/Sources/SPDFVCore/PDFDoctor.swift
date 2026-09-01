import Foundation
import PDFKit

public enum PDFDoctorLevel: String, Codable, Comparable, Sendable {
    case healthy
    case attention
    case critical

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let rank: [Self: Int] = [.healthy: 0, .attention: 1, .critical: 2]
        return rank[lhs, default: 0] < rank[rhs, default: 0]
    }
}

public enum PDFDoctorCategory: String, Codable, Sendable {
    case access
    case pages
    case text
    case forms
    case privacy
}

public enum PDFDoctorAction: String, Codable, CaseIterable, Sendable {
    case unlockDocument
    case reviewPermissions
    case inspectPages
    case runOCR
    case normalizeForms
    case reviewForms
    case runSafeShare
    case reviewAnnotations
}

public struct PDFDoctorIssue: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let level: PDFDoctorLevel
    public let category: PDFDoctorCategory
    public let title: String
    public let detail: String
    public let pages: [Int]
    public let fields: [String]
    public let action: PDFDoctorAction?
}

public struct PDFDoctorReport: Codable, Equatable, Sendable {
    public let level: PDFDoctorLevel
    public let pageCount: Int
    public let searchablePages: Int
    public let rotatedPages: Int
    public let distinctPageSizes: Int
    public let formWidgets: Int
    public let reviewAnnotations: Int
    public let issues: [PDFDoctorIssue]
    public let recommendedActions: [PDFDoctorAction]

    public var isHealthy: Bool { level == .healthy }
}

public extension PDFOperations {
    static func diagnose(_ document: PDFDocument) -> PDFDoctorReport {
        let safety = safetyGate(for: document)
        if safety.locked {
            let issue = PDFDoctorIssue(
                id: "locked-document",
                level: .critical,
                category: .access,
                title: "Document is locked",
                detail: "Unlock the PDF before its pages and interactive content can be diagnosed.",
                pages: [],
                fields: [],
                action: .unlockDocument
            )
            return PDFDoctorReport(
                level: .critical,
                pageCount: document.pageCount,
                searchablePages: 0,
                rotatedPages: 0,
                distinctPageSizes: 0,
                formWidgets: 0,
                reviewAnnotations: 0,
                issues: [issue],
                recommendedActions: [.unlockDocument]
            )
        }

        var issues: [PDFDoctorIssue] = []
        let pageCount = document.pageCount
        if pageCount == 0 {
            issues.append(PDFDoctorIssue(
                id: "no-pages", level: .critical, category: .pages,
                title: "Document has no pages", detail: "No readable page tree was found.",
                pages: [], fields: [], action: .inspectPages
            ))
        }

        for issue in safety.issues {
            guard issue.id != "locked-document" else { continue }
            issues.append(PDFDoctorIssue(
                id: "safety-\(issue.id)",
                level: issue.level == .stop ? .critical : .attention,
                category: .access,
                title: issue.title,
                detail: issue.detail,
                pages: [],
                fields: [],
                action: issue.id == "restricted-permissions" ? .reviewPermissions : .runSafeShare
            ))
        }

        let searchablePages = (0..<pageCount).filter {
            !(document.page(at: $0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        if pageCount > 0, searchablePages == 0 {
            issues.append(PDFDoctorIssue(
                id: "no-searchable-text", level: .attention, category: .text,
                title: "No searchable text", detail: "The document may be a scan. OCR can add an on-device text layer.",
                pages: Array(1...pageCount), fields: [], action: .runOCR
            ))
        } else if searchablePages < pageCount {
            let pages = (0..<pageCount).compactMap { index -> Int? in
                let value = (document.page(at: index)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? index + 1 : nil
            }
            issues.append(PDFDoctorIssue(
                id: "partial-searchable-text", level: .attention, category: .text,
                title: "Some pages lack searchable text", detail: "OCR only the listed pages to complete text coverage.",
                pages: pages, fields: [], action: .runOCR
            ))
        }

        let rotations = (0..<pageCount).filter { normalizedDoctorRotation(document.page(at: $0)?.rotation ?? 0) != 0 }
        if !rotations.isEmpty {
            issues.append(PDFDoctorIssue(
                id: "rotated-pages", level: .attention, category: .pages,
                title: "Rotated pages", detail: "Confirm that these page rotations are intentional.",
                pages: rotations.map { $0 + 1 }, fields: [], action: .inspectPages
            ))
        }
        let sizes = Set((0..<pageCount).compactMap { index -> String? in
            guard let page = document.page(at: index) else { return nil }
            let bounds = page.bounds(for: .cropBox)
            return "\((Double(bounds.width) * 10).rounded())x\((Double(bounds.height) * 10).rounded())"
        })
        if sizes.count > 1 {
            issues.append(PDFDoctorIssue(
                id: "mixed-page-sizes", level: .attention, category: .pages,
                title: "Mixed page sizes", detail: "The PDF contains multiple crop-box sizes; check print and merge layout.",
                pages: [], fields: [], action: .inspectPages
            ))
        }

        let formReport = formReport(for: document)
        let formGate = formGate(for: formReport)
        for issue in formGate.issues {
            issues.append(PDFDoctorIssue(
                id: "form-\(issue.id)",
                level: issue.level == .stop ? .critical : .attention,
                category: .forms,
                title: issue.title,
                detail: issue.detail,
                pages: [],
                fields: issue.fields,
                action: issue.id == "orphan-widgets" ? .normalizeForms : .reviewForms
            ))
        }

        let share = safeShareAudit(for: document)
        let safetyFindingIDs: Set<String> = ["locked-document", "encrypted-document", "certificate-signatures"]
        for finding in share.findings where !safetyFindingIDs.contains(finding.id) {
            let action: PDFDoctorAction = finding.category == .review ? .reviewAnnotations : .runSafeShare
            issues.append(PDFDoctorIssue(
                id: "privacy-\(finding.id)", level: .attention, category: .privacy,
                title: finding.title, detail: finding.detail,
                pages: finding.pages,
                fields: finding.category == .forms ? share.filledFormFields : [],
                action: action
            ))
        }

        let level = issues.map(\.level).max() ?? .healthy
        var actions: [PDFDoctorAction] = []
        for action in issues.compactMap(\.action) where !actions.contains(action) { actions.append(action) }
        return PDFDoctorReport(
            level: level,
            pageCount: pageCount,
            searchablePages: searchablePages,
            rotatedPages: rotations.count,
            distinctPageSizes: sizes.count,
            formWidgets: formReport.widgetCount,
            reviewAnnotations: share.reviewAnnotationCount,
            issues: issues,
            recommendedActions: actions
        )
    }

    private static func normalizedDoctorRotation(_ value: Int) -> Int {
        ((value % 360) + 360) % 360
    }
}
