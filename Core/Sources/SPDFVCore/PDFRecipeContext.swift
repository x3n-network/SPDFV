import Foundation

public struct PDFRecipeExecutionContext: Sendable {
    public let parameters: [String: String]
    public let references: [String: Data]
    public let formData: [String: PDFFormDataFile]
    public let inputName: String?

    public init(
        parameters: [String: String] = [:],
        references: [String: Data] = [:],
        formData: [String: PDFFormDataFile] = [:],
        inputName: String? = nil
    ) {
        self.parameters = parameters
        self.references = references
        self.formData = formData
        self.inputName = inputName
    }
}

