import Foundation
import PDFKit

public enum PDFOperationError: Error, CustomStringConvertible, Sendable {
    case invalidInput(String)
    case invalidPageSelection(String)
    case outputExists(String)
    case operationFailed(String)

    public var description: String {
        switch self {
        case .invalidInput(let message),
             .invalidPageSelection(let message),
             .outputExists(let message),
             .operationFailed(let message): message
        }
    }
}

public enum PDFPageSelection {
    public static func parse(_ specification: String, pageCount: Int) throws -> [Int] {
        guard pageCount > 0 else { throw PDFOperationError.invalidPageSelection("The PDF contains no pages") }
        if specification.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "all" {
            return Array(0..<pageCount)
        }

        var indices = Set<Int>()
        for rawComponent in specification.split(separator: ",") {
            let component = rawComponent.trimmingCharacters(in: .whitespaces)
            if component.contains("-") {
                let bounds = component.split(separator: "-", omittingEmptySubsequences: false)
                guard
                    bounds.count == 2,
                    let first = Int(bounds[0]),
                    let last = Int(bounds[1]),
                    first > 0,
                    first <= last
                else { throw PDFOperationError.invalidPageSelection("Invalid page range: \(component)") }
                for page in first...last { indices.insert(page - 1) }
            } else {
                guard let page = Int(component), page > 0 else {
                    throw PDFOperationError.invalidPageSelection("Invalid page number: \(component)")
                }
                indices.insert(page - 1)
            }
        }

        let sorted = indices.sorted()
        guard !sorted.isEmpty else { throw PDFOperationError.invalidPageSelection("Page selection is empty") }
        guard let last = sorted.last, last < pageCount else {
            throw PDFOperationError.invalidPageSelection("Page selection exceeds the document's \(pageCount) pages")
        }
        return sorted
    }

    public static func validate(_ indices: [Int], pageCount: Int) throws -> [Int] {
        let sorted = Array(Set(indices)).sorted()
        guard !sorted.isEmpty else { throw PDFOperationError.invalidPageSelection("Page selection is empty") }
        guard sorted.allSatisfy({ (0..<pageCount).contains($0) }) else {
            throw PDFOperationError.invalidPageSelection("Page selection exceeds the document's \(pageCount) pages")
        }
        return sorted
    }
}

public struct PDFEdgeInsets: Codable, Equatable, Sendable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public init(top: Double, right: Double, bottom: Double, left: Double) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public static let zero = PDFEdgeInsets(top: 0, right: 0, bottom: 0, left: 0)

    public func clamped(to pageSize: CGSize, minimumPageDimension: Double = 72) -> NSEdgeInsets {
        var horizontal = [max(0, left), max(0, right)]
        var vertical = [max(0, top), max(0, bottom)]
        let maximumHorizontal = max(0, Double(pageSize.width) - minimumPageDimension)
        let maximumVertical = max(0, Double(pageSize.height) - minimumPageDimension)
        if horizontal.reduce(0, +) > maximumHorizontal {
            let scale = maximumHorizontal / max(1, horizontal.reduce(0, +))
            horizontal = horizontal.map { $0 * scale }
        }
        if vertical.reduce(0, +) > maximumVertical {
            let scale = maximumVertical / max(1, vertical.reduce(0, +))
            vertical = vertical.map { $0 * scale }
        }
        return NSEdgeInsets(
            top: CGFloat(vertical[0]),
            left: CGFloat(horizontal[0]),
            bottom: CGFloat(vertical[1]),
            right: CGFloat(horizontal[1])
        )
    }
}

public struct PDFRectReport: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.width)
        height = Double(rect.height)
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct PDFPageReport: Codable, Equatable, Sendable {
    public let page: Int
    public let rotation: Int
    public let annotations: Int
    public let mediaBox: PDFRectReport
    public let cropBox: PDFRectReport
}

public struct PDFInspectionReport: Codable, Equatable, Sendable {
    public let path: String?
    public let bytes: Int64?
    public let pages: Int
    public let encrypted: Bool
    public let locked: Bool
    public let allowsCopying: Bool
    public let allowsPrinting: Bool
    public let metadata: [String: String]
    public let pageDetails: [PDFPageReport]
}

public struct PDFAnnotationReport: Codable, Equatable, Sendable {
    public let page: Int
    public let index: Int
    public let type: String
    public let contents: String?
    public let author: String?
    public let bounds: PDFRectReport
}

public struct PDFRotationChange {
    public let page: PDFPage
    public let previousRotation: Int
}

public struct PDFCropChange {
    public let page: PDFPage
    public let previousCropBox: CGRect
    public let cropBox: CGRect
}

public enum PDFOperations {
    public static func open(_ url: URL) throws -> PDFDocument {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PDFOperationError.invalidInput("Input PDF does not exist: \(url.path)")
        }
        guard url.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: url) else {
            throw PDFOperationError.invalidInput("Input is not a readable PDF: \(url.path)")
        }
        return document
    }

    public static func inspect(_ document: PDFDocument, sourceURL: URL? = nil) -> PDFInspectionReport {
        let attributes = document.documentAttributes ?? [:]
        var metadata: [String: String] = [:]
        for (name, key) in [
            ("title", PDFDocumentAttribute.titleAttribute),
            ("author", PDFDocumentAttribute.authorAttribute),
            ("subject", PDFDocumentAttribute.subjectAttribute),
            ("creator", PDFDocumentAttribute.creatorAttribute),
            ("producer", PDFDocumentAttribute.producerAttribute)
        ] {
            if let value = attributes[key] as? String, !value.isEmpty { metadata[name] = value }
        }
        let details = (0..<document.pageCount).compactMap { index -> PDFPageReport? in
            guard let page = document.page(at: index) else { return nil }
            return PDFPageReport(
                page: index + 1,
                rotation: page.rotation,
                annotations: page.annotations.count,
                mediaBox: PDFRectReport(page.bounds(for: .mediaBox)),
                cropBox: PDFRectReport(page.bounds(for: .cropBox))
            )
        }
        let bytes = sourceURL.flatMap { url in
            (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
        }
        return PDFInspectionReport(
            path: sourceURL?.path,
            bytes: bytes,
            pages: document.pageCount,
            encrypted: document.isEncrypted,
            locked: document.isLocked,
            allowsCopying: document.allowsCopying,
            allowsPrinting: document.allowsPrinting,
            metadata: metadata,
            pageDetails: details
        )
    }

    public static func annotations(in document: PDFDocument, pageIndices: [Int]? = nil) throws -> [PDFAnnotationReport] {
        let indices = try PDFPageSelection.validate(pageIndices ?? Array(0..<document.pageCount), pageCount: document.pageCount)
        return indices.flatMap { pageIndex -> [PDFAnnotationReport] in
            guard let page = document.page(at: pageIndex) else { return [] }
            return page.annotations.enumerated().map { annotationIndex, annotation in
                PDFAnnotationReport(
                    page: pageIndex + 1,
                    index: annotationIndex + 1,
                    type: annotation.type ?? "Annotation",
                    contents: annotation.contents,
                    author: annotation.userName,
                    bounds: PDFRectReport(annotation.bounds)
                )
            }
        }
    }

    public static func extract(_ document: PDFDocument, pageIndices: [Int]) throws -> PDFDocument {
        try requirePermission(.contentCopying, for: document)
        let indices = try PDFPageSelection.validate(pageIndices, pageCount: document.pageCount)
        let result = PDFDocument()
        result.documentAttributes = document.documentAttributes
        for index in indices {
            guard let page = document.page(at: index)?.copy() as? PDFPage else {
                throw PDFOperationError.operationFailed("Could not copy page \(index + 1)")
            }
            result.insert(page, at: result.pageCount)
        }
        return result
    }

    @discardableResult
    public static func insert(
        source: PDFDocument,
        pageIndices: [Int],
        into destination: PDFDocument,
        at insertionIndex: Int
    ) throws -> [Int] {
        try requirePermission(.contentCopying, for: source)
        try requirePermission(.pageAssembly, for: destination)
        let indices = try PDFPageSelection.validate(pageIndices, pageCount: source.pageCount)
        let insertionIndex = min(max(0, insertionIndex), destination.pageCount)
        var inserted: [Int] = []
        for (offset, sourceIndex) in indices.enumerated() {
            guard let page = source.page(at: sourceIndex)?.copy() as? PDFPage else {
                throw PDFOperationError.operationFailed("Could not copy page \(sourceIndex + 1)")
            }
            let destinationIndex = insertionIndex + offset
            destination.insert(page, at: destinationIndex)
            inserted.append(destinationIndex)
        }
        return inserted
    }

    public static func merge(_ documents: [PDFDocument]) throws -> PDFDocument {
        guard !documents.isEmpty else { throw PDFOperationError.invalidInput("No input PDFs were provided") }
        let result = PDFDocument()
        result.documentAttributes = documents.first?.documentAttributes
        for document in documents {
            _ = try insert(
                source: document,
                pageIndices: Array(0..<document.pageCount),
                into: result,
                at: result.pageCount
            )
        }
        return result
    }

    @discardableResult
    public static func duplicatePages(_ document: PDFDocument, pageIndices: [Int]) throws -> Int {
        try requirePermission(.contentCopying, for: document)
        try requirePermission(.pageAssembly, for: document)
        let indices = try PDFPageSelection.validate(pageIndices, pageCount: document.pageCount)
        for index in indices.reversed() {
            guard let copy = document.page(at: index)?.copy() as? PDFPage else {
                throw PDFOperationError.operationFailed("Could not duplicate page \(index + 1)")
            }
            document.insert(copy, at: index + 1)
        }
        return indices.count
    }

    @discardableResult
    public static func deletePages(_ document: PDFDocument, pageIndices: [Int]) throws -> Int {
        try requirePermission(.pageAssembly, for: document)
        let indices = try PDFPageSelection.validate(pageIndices, pageCount: document.pageCount)
        guard indices.count < document.pageCount else {
            throw PDFOperationError.invalidInput("A PDF must retain at least one page")
        }
        for index in indices.reversed() { document.removePage(at: index) }
        return indices.count
    }

    @discardableResult
    public static func rotate(_ document: PDFDocument, pageIndices: [Int], degrees: Int) throws -> [PDFRotationChange] {
        try requirePermission(.pageAssembly, for: document)
        guard degrees.isMultiple(of: 90) else {
            throw PDFOperationError.invalidInput("Rotation must be a multiple of 90 degrees")
        }
        let indices = try PDFPageSelection.validate(pageIndices, pageCount: document.pageCount)
        return indices.compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let change = PDFRotationChange(page: page, previousRotation: page.rotation)
            page.rotation = normalizedRotation(page.rotation + degrees)
            return change
        }
    }

    @discardableResult
    public static func crop(_ document: PDFDocument, pageIndices: [Int], insets: PDFEdgeInsets) throws -> [PDFCropChange] {
        try requirePermission(.pageAssembly, for: document)
        let indices = try PDFPageSelection.validate(pageIndices, pageCount: document.pageCount)
        return indices.compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let media = page.bounds(for: .mediaBox)
            let safe = insets.clamped(to: media.size)
            let cropBox = CGRect(
                x: media.minX + safe.left,
                y: media.minY + safe.bottom,
                width: media.width - safe.left - safe.right,
                height: media.height - safe.top - safe.bottom
            )
            let previous = page.bounds(for: .cropBox)
            guard !previous.approximatelyEquals(cropBox) else { return nil }
            page.setBounds(cropBox, for: .cropBox)
            return PDFCropChange(page: page, previousCropBox: previous, cropBox: cropBox)
        }
    }

    public static func write(_ document: PDFDocument, to url: URL, overwrite: Bool = false) throws {
        if FileManager.default.fileExists(atPath: url.path), !overwrite {
            throw PDFOperationError.outputExists("Output already exists; pass --force to replace it: \(url.path)")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = document.dataRepresentation() else {
            throw PDFOperationError.operationFailed("Could not serialize PDF")
        }
        try data.write(to: url, options: .atomic)
        guard let reopened = PDFDocument(url: url), reopened.pageCount == document.pageCount else {
            throw PDFOperationError.operationFailed("Output failed PDF round-trip verification")
        }
    }

    private static func normalizedRotation(_ value: Int) -> Int {
        let remainder = value % 360
        return remainder >= 0 ? remainder : remainder + 360
    }
}

private extension CGRect {
    func approximatelyEquals(_ other: CGRect) -> Bool {
        abs(minX - other.minX) < 0.01
            && abs(minY - other.minY) < 0.01
            && abs(width - other.width) < 0.01
            && abs(height - other.height) < 0.01
    }
}
