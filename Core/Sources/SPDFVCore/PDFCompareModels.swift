import Foundation

public enum PDFComparisonStatus: String, Codable, Sendable {
    case identical
    case changed
}

public enum PDFPageComparisonStatus: String, Codable, Sendable {
    case unchanged
    case changed
    case added
    case removed
}

public enum PDFPageDifference: String, Codable, CaseIterable, Sendable {
    case appearance
    case text
    case dimensions
    case rotation
    case annotations
    case formFields
}

public enum PDFComparisonAlignment: String, Codable, CaseIterable, Sendable {
    case intelligent
    case position
}

/// A normalized page region excluded from rendered-appearance comparison.
/// Coordinates use a top-left origin and values from zero through one.
public struct PDFComparisonIgnoredRegion: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct PDFComparisonOptions: Codable, Equatable, Sendable {
    public let alignment: PDFComparisonAlignment
    public let minimumAppearanceSimilarity: Double
    public let ignoredRegions: [PDFComparisonIgnoredRegion]

    public init(
        alignment: PDFComparisonAlignment = .intelligent,
        minimumAppearanceSimilarity: Double = 0.999,
        ignoredRegions: [PDFComparisonIgnoredRegion] = []
    ) {
        self.alignment = alignment
        self.minimumAppearanceSimilarity = min(max(minimumAppearanceSimilarity, 0), 1)
        self.ignoredRegions = ignoredRegions.filter {
            $0.width > 0 && $0.height > 0 && $0.x < 1 && $0.y < 1 && $0.x + $0.width > 0 && $0.y + $0.height > 0
        }
    }
}

public struct PDFPageDimensions: Codable, Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct PDFPageComparison: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { position }

    public let position: Int
    public let referencePage: Int?
    public let candidatePage: Int?
    public let status: PDFPageComparisonStatus
    public let differences: [PDFPageDifference]
    public let appearanceSimilarity: Double?
    public let referenceDimensions: PDFPageDimensions?
    public let candidateDimensions: PDFPageDimensions?
    public let referenceRotation: Int?
    public let candidateRotation: Int?
    public let referenceTextCharacters: Int
    public let candidateTextCharacters: Int
    public let referenceAnnotationCount: Int
    public let candidateAnnotationCount: Int
    public let referenceFormFieldCount: Int
    public let candidateFormFieldCount: Int
}

public struct PDFComparisonReport: Codable, Equatable, Sendable {
    public let status: PDFComparisonStatus
    public let referencePageCount: Int
    public let candidatePageCount: Int
    public let unchangedPages: Int
    public let changedPages: Int
    public let addedPages: Int
    public let removedPages: Int
    public let options: PDFComparisonOptions
    public let pages: [PDFPageComparison]

    public var hasChanges: Bool { status == .changed }
}
