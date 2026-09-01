import Foundation

public enum PDFSignatureCryptographicStatus: String, Codable, Equatable, Sendable {
    case valid
    case invalid
    case unsigned
    case unsupported
    case error
}

public enum PDFSignatureTrustStatus: String, Codable, Equatable, Sendable {
    case trusted
    case untrusted
    case notEvaluated
}

public enum PDFSignatureCoverage: String, Codable, Equatable, Sendable {
    case entireFile
    case signedRevisionWithLaterChanges
    case invalid
}

public enum PDFSignatureOverallStatus: String, Codable, Equatable, Sendable {
    case none
    case validTrusted
    case validUntrusted
    case modifiedAfterSigning
    case unsigned
    case invalid
    case unsupported
}

public struct PDFSignatureVerificationItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let fieldName: String?
    public let subFilter: String?
    public let cryptographicStatus: PDFSignatureCryptographicStatus
    public let trustStatus: PDFSignatureTrustStatus
    public let coverage: PDFSignatureCoverage
    public let signedByteCount: Int
    public let unsignedTrailingByteCount: Int
    public let signerSummary: String?
    public let certificateSHA256: String?
    public let certificateChainLength: Int?
    public let signingTime: Date?
    public let authenticatedTimestamp: Date?
    public let message: String
}

public struct PDFSignatureVerificationReport: Codable, Equatable, Sendable {
    public let status: PDFSignatureOverallStatus
    public let signatureFieldCount: Int
    public let embeddedSignatureCount: Int
    public let verifiedAt: Date
    public let signatures: [PDFSignatureVerificationItem]
    public let warnings: [String]
}
