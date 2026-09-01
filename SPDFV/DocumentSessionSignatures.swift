import Foundation
import SPDFVCore

extension DocumentSession {
    func verifyDocumentSignatures() {
        guard let fileURL, !isVerifyingSignatures else { return }
        do {
            let accessed = fileURL.startAccessingSecurityScopedResource()
            defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
            let sourceData = try Data(contentsOf: fileURL)
            isVerifyingSignatures = true
            signatureVerificationReport = nil
            Task { @MainActor in
                let report = await Task.detached(priority: .userInitiated) {
                    PDFOperations.verifySignatures(in: sourceData)
                }.value
                signatureVerificationReport = report
                isVerifyingSignatures = false
            }
        } catch {
            errorMessage = "Signatures could not be read: \(error.localizedDescription)"
        }
    }
}
