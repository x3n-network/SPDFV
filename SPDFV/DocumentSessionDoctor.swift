import AppKit
import PDFKit
import SPDFVCore
import UniformTypeIdentifiers

extension DocumentSession {
    func runDocumentDoctor() {
        guard let document else {
            doctorReport = nil
            doctorRepairPlan = nil
            return
        }
        let plan = PDFOperations.doctorRepairPlan(for: document)
        doctorReport = plan.before
        doctorRepairPlan = plan
        doctorRepairVerification = nil
        lastDoctorRepairOutputURL = nil
        doctorRepairStatusMessage = nil
    }

    func createDoctorRepairCopy() {
        guard let document,
              let sourceData = document.dataRepresentation(),
              let plan = doctorRepairPlan,
              !plan.items.isEmpty,
              !isRepairingDocument else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(displayName)-repaired.pdf"
        panel.message = "Apply \(plan.items.count) verified repair\(plan.items.count == 1 ? "" : "s") to a new copy"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        isRepairingDocument = true
        doctorRepairVerification = nil
        lastDoctorRepairOutputURL = nil
        doctorRepairStatusMessage = "Applying repairs to a copy…"
        let activityID = ActivityCenterStore.shared.begin(
            kind: .doctor,
            title: "Repair PDF copy",
            detail: "Applying \(plan.items.count) planned repair\(plan.items.count == 1 ? "" : "s")",
            documentName: displayName
        )

        Task { @MainActor in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let repaired = try PDFOperations.applyDoctorRepairs(data: sourceData)
                    try PDFOperations.write(repaired, to: outputURL, overwrite: true)
                    return repaired
                }.value
                doctorRepairVerification = result.verification
                lastDoctorRepairOutputURL = outputURL
                let removed = result.verification.before.issues.count - result.verification.after.issues.count
                doctorRepairStatusMessage = "Verified the repaired copy; resolved \(max(0, removed)) finding\(removed == 1 ? "" : "s")."
                ActivityCenterStore.shared.finish(
                    activityID,
                    detail: "Verified \(result.verification.appliedActions.count) repair\(result.verification.appliedActions.count == 1 ? "" : "s") with page count preserved",
                    outputURL: outputURL
                )
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } catch {
                errorMessage = "The repaired copy could not be created: \(error.localizedDescription)"
                doctorRepairStatusMessage = "Repair stopped before a verified copy was written."
                ActivityCenterStore.shared.fail(activityID, detail: error.localizedDescription)
            }
            isRepairingDocument = false
        }
    }

    func revealDoctorRepairCopy() {
        guard let lastDoctorRepairOutputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastDoctorRepairOutputURL])
    }

    func performDoctorAction(_ issue: PDFDoctorIssue) {
        guard let action = issue.action else { return }
        thumbnailsVisible = true
        switch action {
        case .unlockDocument, .reviewPermissions:
            navigatorMode = .info
        case .inspectPages:
            navigatorMode = .pages
            if let first = issue.pages.first { goToPage(first - 1) }
        case .runOCR:
            navigatorMode = .pages
            if !issue.pages.isEmpty { selectedPageIndices = Set(issue.pages.map { $0 - 1 }) }
        case .normalizeForms, .reviewForms:
            navigatorMode = .forms
        case .runSafeShare:
            runSafeShareAudit()
            navigatorMode = .info
        case .reviewAnnotations:
            navigatorMode = .annotations
        }
    }
}
