import AppKit
import PDFKit
import SPDFVCore
import UniformTypeIdentifiers

extension DocumentSession {
    func importFormDataFromPicker() {
        guard let document else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose SPDFV form data to validate before applying"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let file = try PDFOperations.decodeFormData(Data(contentsOf: url))
            pendingFormData = file
            formDataValidation = PDFOperations.validateFormData(file, for: document)
            formDataFileName = url.lastPathComponent
        } catch {
            pendingFormData = nil
            formDataValidation = nil
            formDataFileName = nil
            errorMessage = (error as? PDFOperationError)?.description ?? error.localizedDescription
        }
    }

    func exportFormDataFromPicker() {
        guard let document else { return }
        do {
            let file = try PDFOperations.formData(for: document)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "\(displayName)-form-data.json"
            panel.message = "Export current form values. This JSON may contain private information."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try PDFOperations.encodeFormData(file).write(to: url, options: .atomic)
        } catch {
            errorMessage = (error as? PDFOperationError)?.description ?? error.localizedDescription
        }
    }

    func applyPendingFormData() {
        guard let document, let file = pendingFormData, permit(.formEntry) else { return }
        let names = Set(formDataValidation?.updatedFields ?? [])
        let matching = (0..<document.pageCount).flatMap { pageIndex -> [AnnotationEntry] in
            guard let page = document.page(at: pageIndex) else { return [] }
            return page.annotations
                .filter { $0.isFormWidget && names.contains($0.fieldName ?? "") }
                .map { AnnotationEntry(page: page, annotation: $0, pageIndex: pageIndex) }
        }
        let modifications = matching.map {
            FormFieldModification(entry: $0, snapshot: AnnotationSnapshot($0.annotation))
        }
        do {
            _ = try PDFOperations.applyFormData(file, to: document)
            if !modifications.isEmpty {
                recordEdit(.formFieldsModified(modifications), actionName: "Import Form Data")
                markDirty()
                let pages = Array(Set(matching.map(\.pageIndex))).sorted()
                for index in pages { cachedThumbnails.removeObject(forKey: NSNumber(value: index)) }
                perform(.annotationsChanged(pages))
            }
            refreshFormFields()
            formDataValidation = PDFOperations.validateFormData(file, for: document)
        } catch {
            errorMessage = (error as? PDFOperationError)?.description ?? error.localizedDescription
        }
    }

    func clearPendingFormData() {
        pendingFormData = nil
        formDataValidation = nil
        formDataFileName = nil
    }
}
