import AppKit
import Foundation
import PDFKit

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
    public let pages: [PDFPageComparison]

    public var hasChanges: Bool { status == .changed }
}

public extension PDFOperations {
    /// Compares pages by their one-based position. Appearance is rasterized at a
    /// fixed size while text and structural signals remain independent so the
    /// report can explain why a page changed without exposing its contents.
    static func compare(reference: PDFDocument, candidate: PDFDocument) throws -> PDFComparisonReport {
        guard !reference.isLocked, !candidate.isLocked else {
            throw PDFOperationError.invalidInput("Unlock both PDFs before comparing them")
        }

        let count = max(reference.pageCount, candidate.pageCount)
        let pages = (0..<count).map { index in
            comparePages(reference.page(at: index), candidate.page(at: index), position: index + 1)
        }
        let unchanged = pages.filter { $0.status == .unchanged }.count
        let changed = pages.filter { $0.status == .changed }.count
        let added = pages.filter { $0.status == .added }.count
        let removed = pages.filter { $0.status == .removed }.count

        return PDFComparisonReport(
            status: changed + added + removed == 0 ? .identical : .changed,
            referencePageCount: reference.pageCount,
            candidatePageCount: candidate.pageCount,
            unchangedPages: unchanged,
            changedPages: changed,
            addedPages: added,
            removedPages: removed,
            pages: pages
        )
    }
}

private extension PDFOperations {
    static func comparePages(_ reference: PDFPage?, _ candidate: PDFPage?, position: Int) -> PDFPageComparison {
        guard let reference else {
            return oneSidedPage(candidate, position: position, status: .added, isReference: false)
        }
        guard let candidate else {
            return oneSidedPage(reference, position: position, status: .removed, isReference: true)
        }

        let referenceDimensions = dimensions(of: reference)
        let candidateDimensions = dimensions(of: candidate)
        let referenceText = normalizedText(reference.string)
        let candidateText = normalizedText(candidate.string)
        let referenceInventory = inventory(of: reference)
        let candidateInventory = inventory(of: candidate)
        let similarity = appearanceSimilarity(reference, candidate)
        var differences: [PDFPageDifference] = []

        if similarity.map({ $0 < 0.999 }) == true { differences.append(.appearance) }
        if referenceText != candidateText { differences.append(.text) }
        if referenceDimensions != candidateDimensions { differences.append(.dimensions) }
        if normalizedRotation(reference.rotation) != normalizedRotation(candidate.rotation) { differences.append(.rotation) }
        if referenceInventory.annotationSignatures != candidateInventory.annotationSignatures {
            differences.append(.annotations)
        }
        if referenceInventory.formSignatures != candidateInventory.formSignatures {
            differences.append(.formFields)
        }

        return PDFPageComparison(
            position: position,
            referencePage: position,
            candidatePage: position,
            status: differences.isEmpty ? .unchanged : .changed,
            differences: differences,
            appearanceSimilarity: similarity,
            referenceDimensions: referenceDimensions,
            candidateDimensions: candidateDimensions,
            referenceRotation: normalizedRotation(reference.rotation),
            candidateRotation: normalizedRotation(candidate.rotation),
            referenceTextCharacters: referenceText.count,
            candidateTextCharacters: candidateText.count,
            referenceAnnotationCount: referenceInventory.annotationCount,
            candidateAnnotationCount: candidateInventory.annotationCount,
            referenceFormFieldCount: referenceInventory.formCount,
            candidateFormFieldCount: candidateInventory.formCount
        )
    }

    static func oneSidedPage(
        _ page: PDFPage?,
        position: Int,
        status: PDFPageComparisonStatus,
        isReference: Bool
    ) -> PDFPageComparison {
        let dimensions = page.map(dimensions(of:))
        let textCount = normalizedText(page?.string).count
        let inventory = page.map(inventory(of:)) ?? .empty
        return PDFPageComparison(
            position: position,
            referencePage: isReference ? position : nil,
            candidatePage: isReference ? nil : position,
            status: status,
            differences: [],
            appearanceSimilarity: nil,
            referenceDimensions: isReference ? dimensions : nil,
            candidateDimensions: isReference ? nil : dimensions,
            referenceRotation: isReference ? page.map { normalizedRotation($0.rotation) } : nil,
            candidateRotation: isReference ? nil : page.map { normalizedRotation($0.rotation) },
            referenceTextCharacters: isReference ? textCount : 0,
            candidateTextCharacters: isReference ? 0 : textCount,
            referenceAnnotationCount: isReference ? inventory.annotationCount : 0,
            candidateAnnotationCount: isReference ? 0 : inventory.annotationCount,
            referenceFormFieldCount: isReference ? inventory.formCount : 0,
            candidateFormFieldCount: isReference ? 0 : inventory.formCount
        )
    }

    static func normalizedText(_ text: String?) -> String {
        (text ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func dimensions(of page: PDFPage) -> PDFPageDimensions {
        let bounds = page.bounds(for: .cropBox)
        return PDFPageDimensions(
            width: (Double(bounds.width) * 100).rounded() / 100,
            height: (Double(bounds.height) * 100).rounded() / 100
        )
    }

    static func normalizedRotation(_ value: Int) -> Int {
        ((value % 360) + 360) % 360
    }

    static func inventory(of page: PDFPage) -> PDFComparisonInventory {
        var annotations: [String] = []
        var forms: [String] = []
        for annotation in page.annotations {
            let bounds = annotation.bounds
            let signature = [
                annotation.type ?? "",
                rounded(bounds.origin.x), rounded(bounds.origin.y),
                rounded(bounds.width), rounded(bounds.height),
                annotation.fieldName ?? "",
                annotation.widgetStringValue ?? "",
                normalizedText(annotation.contents),
                annotation.userName ?? ""
            ].joined(separator: "|")
            if annotation.type?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "Widget" {
                forms.append(signature)
            } else {
                annotations.append(signature)
            }
        }
        return PDFComparisonInventory(
            annotationSignatures: annotations.sorted(),
            formSignatures: forms.sorted()
        )
    }

    static func rounded(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }

    static func appearanceSimilarity(_ reference: PDFPage, _ candidate: PDFPage) -> Double? {
        guard let first = rasterBytes(reference), let second = rasterBytes(candidate), first.count == second.count else {
            return nil
        }
        var delta: UInt64 = 0
        for index in first.indices {
            delta += UInt64(abs(Int(first[index]) - Int(second[index])))
        }
        let maximum = Double(first.count * 255)
        guard maximum > 0 else { return 1 }
        return ((1 - Double(delta) / maximum) * 10_000).rounded() / 10_000
    }

    static func rasterBytes(_ page: PDFPage) -> [UInt8]? {
        let width = 128
        let height = 128
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: representation) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        page.thumbnail(of: NSSize(width: width, height: height), for: .cropBox)
            .draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = representation.bitmapData else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: representation.bytesPerRow * height))
    }
}

private struct PDFComparisonInventory {
    static let empty = PDFComparisonInventory(annotationSignatures: [], formSignatures: [])

    let annotationSignatures: [String]
    let formSignatures: [String]

    var annotationCount: Int { annotationSignatures.count }
    var formCount: Int { formSignatures.count }
}
