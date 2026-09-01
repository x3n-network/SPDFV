import AppKit
import PDFKit
import SPDFVCore
import UniformTypeIdentifiers

extension DocumentSession {
    func compareWithPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the reference PDF to compare with the open document"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        compare(with: url)
    }

    func compare(with referenceURL: URL) {
        guard let candidateData = document?.dataRepresentation() else {
            errorMessage = "The open PDF could not be prepared for comparison."
            return
        }

        let accessed = referenceURL.startAccessingSecurityScopedResource()
        defer { if accessed { referenceURL.stopAccessingSecurityScopedResource() } }

        do {
            let referenceData = try Data(contentsOf: referenceURL)
            let referenceName = referenceURL.lastPathComponent
            let requestID = UUID()
            comparisonRequestID = requestID
            isComparing = true
            comparisonReport = nil
            comparisonReferenceName = referenceName

            Task {
                do {
                    let report = try await Task.detached(priority: .userInitiated) {
                        guard let reference = PDFDocument(data: referenceData),
                              let candidate = PDFDocument(data: candidateData) else {
                            throw PDFOperationError.invalidInput("Both files must be readable PDFs")
                        }
                        return try PDFOperations.compare(reference: reference, candidate: candidate)
                    }.value
                    guard comparisonRequestID == requestID else { return }
                    comparisonReport = report
                } catch {
                    guard comparisonRequestID == requestID else { return }
                    comparisonReferenceName = nil
                    errorMessage = (error as? PDFOperationError)?.description ?? error.localizedDescription
                }
                guard comparisonRequestID == requestID else { return }
                isComparing = false
                comparisonRequestID = nil
            }
        } catch {
            comparisonReferenceName = nil
            errorMessage = "Could not read “\(referenceURL.lastPathComponent)”: \(error.localizedDescription)"
        }
    }

    func clearComparison() {
        comparisonReport = nil
        comparisonReferenceName = nil
        isComparing = false
        comparisonRequestID = nil
    }

    func showComparisonPage(_ comparison: PDFPageComparison) {
        guard let page = comparison.candidatePage else { return }
        goToPage(page - 1)
    }
}
