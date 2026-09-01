import AppKit
import PDFKit
import SPDFVCore
import UniformTypeIdentifiers

extension DocumentSession {
func createSearchableCopy(
    scope: OCRPageScope,
    quality: PDFOCRRecognitionLevel,
    languages: [String]
) {
    guard let document, let sourceData = document.dataRepresentation(), !isPerformingOCR else { return }
    let indices: [Int]
    switch scope {
    case .current:
        indices = [pageIndex]
    case .selection:
        indices = pageOperationIndices
    case .all:
        indices = Array(0..<pageCount)
    }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.pdf]
    panel.nameFieldStringValue = "\(displayName)-searchable.pdf"
    panel.message = indices.count == pageCount
        ? "Create a searchable copy of the complete PDF"
        : "Create a searchable copy with OCR on \(indices.count) page\(indices.count == 1 ? "" : "s")"
    guard panel.runModal() == .OK, let outputURL = panel.url else { return }

    isPerformingOCR = true
    ocrStatusMessage = "Reading \(indices.count) page\(indices.count == 1 ? "" : "s") on this Mac…"
    lastOCRReport = nil
    lastOCROutputURL = nil
    let activityID = ActivityCenterStore.shared.begin(
        kind: .ocr,
        title: "Create searchable PDF",
        detail: "Reading \(indices.count) page\(indices.count == 1 ? "" : "s") on this Mac",
        documentName: displayName
    )
    let configuration = PDFOCRConfiguration(
        recognitionLevel: quality,
        languages: languages,
        usesLanguageCorrection: true,
        renderDPI: quality == .accurate ? 216 : 144
    )

    Task { @MainActor in
        do {
            let report = try await Task.detached(priority: .userInitiated) {
                let result = try PDFOperations.makeSearchable(
                    data: sourceData,
                    pageIndices: indices,
                    configuration: configuration
                )
                try PDFOperations.write(result, to: outputURL, overwrite: true)
                return result.report
            }.value
            lastOCRReport = report
            lastOCROutputURL = outputURL
            ocrStatusMessage = "Added \(report.recognizedLines) searchable lines to the copy."
            ActivityCenterStore.shared.finish(
                activityID,
                detail: "Added \(report.recognizedLines) searchable lines across \(report.pages.count) page\(report.pages.count == 1 ? "" : "s")",
                outputURL: outputURL
            )
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        } catch {
            errorMessage = "The searchable copy could not be created: \(error.localizedDescription)"
            ocrStatusMessage = "OCR stopped before the copy was written."
            ActivityCenterStore.shared.fail(activityID, detail: error.localizedDescription)
        }
        isPerformingOCR = false
    }
}

func setRedactionEditing(_ enabled: Bool) {
    guard document != nil else { return }
    activeAnnotationTool = .select
    selectedAnnotation = nil
    isCropEditing = false
    isRedactionEditing = enabled
}

func registerPendingRedaction(page: PDFPage, bounds: CGRect) {
    guard bounds.width >= 6, bounds.height >= 6 else { return }
    pendingRedactions.append(PendingRedaction(page: page, bounds: bounds.standardized))
    redactionStatusMessage = "\(pendingRedactions.count) region\(pendingRedactions.count == 1 ? "" : "s") staged for secure export."
}

func removePendingRedaction(_ id: UUID) {
    pendingRedactions.removeAll { $0.id == id }
    redactionStatusMessage = pendingRedactions.isEmpty
        ? nil
        : "\(pendingRedactions.count) region\(pendingRedactions.count == 1 ? "" : "s") staged for secure export."
}

func clearPendingRedactions(currentPageOnly: Bool = false) {
    if currentPageOnly, let current = document?.page(at: pageIndex) {
        pendingRedactions.removeAll { $0.page === current }
    } else {
        pendingRedactions = []
    }
    redactionStatusMessage = pendingRedactions.isEmpty
        ? nil
        : "\(pendingRedactions.count) region\(pendingRedactions.count == 1 ? "" : "s") staged for secure export."
}

func createSanitizedCopy(
    restoresSearchableText: Bool,
    forbiddenTerms: [String]
) {
    guard
        let document,
        let sourceData = document.dataRepresentation(),
        !isSanitizingRedactions
    else { return }
    let regions = pendingRedactions.compactMap { mark -> PDFRedactionRegion? in
        let index = document.index(for: mark.page)
        guard index != NSNotFound else { return nil }
        return PDFRedactionRegion(page: index + 1, bounds: mark.bounds)
    }
    guard !regions.isEmpty else {
        errorMessage = "Draw at least one redaction region before creating a sanitized copy."
        return
    }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.pdf]
    panel.nameFieldStringValue = "\(displayName)-sanitized.pdf"
    panel.message = "Create a flattened, sanitized copy with \(regions.count) burned-in redaction\(regions.count == 1 ? "" : "s")"
    guard panel.runModal() == .OK, let outputURL = panel.url else { return }

    isSanitizingRedactions = true
    isRedactionEditing = false
    lastRedactionReport = nil
    redactionStatusMessage = "Flattening affected pages and removing hidden objects…"
    let activityID = ActivityCenterStore.shared.begin(
        kind: .redaction,
        title: "Create sanitized PDF",
        detail: "Flattening \(regions.count) redaction region\(regions.count == 1 ? "" : "s") and removing hidden objects",
        documentName: displayName
    )
    Task { @MainActor in
        do {
            let report = try await Task.detached(priority: .userInitiated) {
                let result = try PDFOperations.sanitize(
                    data: sourceData,
                    regions: regions,
                    configuration: PDFRedactionConfiguration(
                        renderDPI: 216,
                        restoresSearchableText: restoresSearchableText,
                        recognitionLevel: .accurate,
                        languages: []
                    ),
                    verifyAbsentTerms: forbiddenTerms
                )
                try PDFOperations.write(result, to: outputURL, overwrite: true)
                return result.report
            }.value
            lastRedactionReport = report
            redactionStatusMessage = "Sanitized \(report.flattenedPages.count) page\(report.flattenedPages.count == 1 ? "" : "s"); \(report.verifiedAbsentTerms.count) forbidden term\(report.verifiedAbsentTerms.count == 1 ? "" : "s") verified absent."
            ActivityCenterStore.shared.finish(
                activityID,
                detail: "Sanitized \(report.flattenedPages.count) page\(report.flattenedPages.count == 1 ? "" : "s") · verified \(report.verifiedAbsentTerms.count) forbidden term\(report.verifiedAbsentTerms.count == 1 ? "" : "s") absent",
                outputURL: outputURL
            )
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        } catch {
            errorMessage = "The sanitized copy could not be created: \(error.localizedDescription)"
            redactionStatusMessage = "Secure export stopped before a verified copy was written."
            ActivityCenterStore.shared.fail(activityID, detail: error.localizedDescription)
        }
        isSanitizingRedactions = false
    }
}
}
