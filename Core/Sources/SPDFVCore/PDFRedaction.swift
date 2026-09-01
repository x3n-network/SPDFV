import AppKit
import CoreGraphics
import Foundation
import PDFKit

public struct PDFRedactionRegion: Codable, Equatable, Sendable {
    public let page: Int
    public let bounds: PDFRectReport

    public init(page: Int, bounds: CGRect) {
        self.page = page
        self.bounds = PDFRectReport(bounds)
    }
}

public struct PDFRedactionConfiguration: Codable, Equatable, Sendable {
    public var renderDPI: Double
    public var restoresSearchableText: Bool
    public var recognitionLevel: PDFOCRRecognitionLevel
    public var languages: [String]

    public init(
        renderDPI: Double = 216,
        restoresSearchableText: Bool = true,
        recognitionLevel: PDFOCRRecognitionLevel = .accurate,
        languages: [String] = []
    ) {
        self.renderDPI = min(max(renderDPI, 144), 400)
        self.restoresSearchableText = restoresSearchableText
        self.recognitionLevel = recognitionLevel
        self.languages = languages
    }
}

public struct PDFRedactionReport: Codable, Equatable, Sendable {
    public let pageCount: Int
    public let flattenedPages: [Int]
    public let regionCount: Int
    public let searchableTextRestored: Bool
    public let verifiedAbsentTerms: [String]

    public init(
        pageCount: Int,
        flattenedPages: [Int],
        regionCount: Int,
        searchableTextRestored: Bool,
        verifiedAbsentTerms: [String]
    ) {
        self.pageCount = pageCount
        self.flattenedPages = flattenedPages
        self.regionCount = regionCount
        self.searchableTextRestored = searchableTextRestored
        self.verifiedAbsentTerms = verifiedAbsentTerms
    }
}

public struct PDFRedactionResult: Sendable {
    public let data: Data
    public let report: PDFRedactionReport

    public init(data: Data, report: PDFRedactionReport) {
        self.data = data
        self.report = report
    }
}

public extension PDFOperations {
    static func sanitize(
        data: Data,
        regions: [PDFRedactionRegion],
        configuration: PDFRedactionConfiguration = PDFRedactionConfiguration(),
        verifyAbsentTerms: [String] = []
    ) throws -> PDFRedactionResult {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw PDFOperationError.invalidInput("Input is not a readable PDF")
        }
        try requirePermission(.contentCopying, for: document)
        guard !regions.isEmpty else {
            throw PDFOperationError.invalidInput("At least one redaction region is required")
        }

        let grouped = try Dictionary(grouping: regions) { region -> Int in
            let index = region.page - 1
            guard (0..<document.pageCount).contains(index) else {
                throw PDFOperationError.invalidPageSelection("Redaction page \(region.page) exceeds the document's \(document.pageCount) pages")
            }
            guard region.bounds.cgRect.width > 0, region.bounds.cgRect.height > 0 else {
                throw PDFOperationError.invalidInput("Redaction regions must have positive width and height")
            }
            return index
        }

        let flattened = grouped.keys.sorted()
        let visual = PDFDocument()
        visual.documentAttributes = [
            PDFDocumentAttribute.producerAttribute: "SPDFV Sanitizer"
        ]

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else {
                throw PDFOperationError.operationFailed("Could not read page \(index + 1)")
            }
            if let pageRegions = grouped[index] {
                let redacted = try rasterizedPage(
                    page,
                    regions: pageRegions.map(\.bounds.cgRect),
                    renderDPI: configuration.renderDPI
                )
                visual.insert(redacted, at: visual.pageCount)
            } else {
                guard let copy = page.copy() as? PDFPage else {
                    throw PDFOperationError.operationFailed("Could not copy page \(index + 1)")
                }
                visual.insert(copy, at: visual.pageCount)
            }
        }

        guard let visualData = visual.dataRepresentation() else {
            throw PDFOperationError.operationFailed("Could not serialize sanitized page artwork")
        }

        let outputData: Data
        if configuration.restoresSearchableText {
            outputData = try makeSearchable(
                data: visualData,
                pageIndices: flattened,
                configuration: PDFOCRConfiguration(
                    recognitionLevel: configuration.recognitionLevel,
                    languages: configuration.languages,
                    usesLanguageCorrection: true,
                    renderDPI: configuration.renderDPI
                )
            ).data
        } else {
            outputData = visualData
        }

        guard let reopened = PDFDocument(data: outputData), reopened.pageCount == document.pageCount else {
            throw PDFOperationError.operationFailed("Sanitized output failed PDF round-trip verification")
        }
        let normalizedTerms = Array(Set(verifyAbsentTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted()
        let extracted = (reopened.string ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if let leaked = normalizedTerms.first(where: {
            extracted.localizedCaseInsensitiveContains($0)
        }) {
            throw PDFOperationError.operationFailed("Verification failed: output still contains forbidden text \"\(leaked)\"")
        }

        return PDFRedactionResult(
            data: outputData,
            report: PDFRedactionReport(
                pageCount: document.pageCount,
                flattenedPages: flattened.map { $0 + 1 },
                regionCount: regions.count,
                searchableTextRestored: configuration.restoresSearchableText,
                verifiedAbsentTerms: normalizedTerms
            )
        )
    }

    static func write(
        _ result: PDFRedactionResult,
        to url: URL,
        overwrite: Bool = false
    ) throws {
        if FileManager.default.fileExists(atPath: url.path), !overwrite {
            throw PDFOperationError.outputExists("Output already exists; pass --force to replace it: \(url.path)")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try result.data.write(to: url, options: .atomic)
        guard let reopened = PDFDocument(url: url), reopened.pageCount == result.report.pageCount else {
            throw PDFOperationError.operationFailed("Sanitized output failed PDF round-trip verification")
        }
    }
}

private extension PDFOperations {
    static func rasterizedPage(
        _ page: PDFPage,
        regions: [CGRect],
        renderDPI: Double
    ) throws -> PDFPage {
        let sourceBox = page.bounds(for: .cropBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        let sideways = rotation == 90 || rotation == 270
        let outputSize = sideways
            ? CGSize(width: sourceBox.height, height: sourceBox.width)
            : sourceBox.size
        let outputBox = CGRect(origin: .zero, size: outputSize)
        let scale = CGFloat(renderDPI / 72)
        let width = max(1, Int((outputSize.width * scale).rounded()))
        let height = max(1, Int((outputSize.height * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let pageRef = page.pageRef else {
            throw PDFOperationError.operationFailed("Could not create a secure page raster")
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        let transform = pageRef.getDrawingTransform(
            .cropBox,
            rect: outputBox,
            rotate: 0,
            preserveAspectRatio: true
        )
        context.saveGState()
        context.concatenate(transform)
        context.drawPDFPage(pageRef)
        for annotation in page.annotations {
            annotation.draw(with: .cropBox, in: context)
        }
        context.restoreGState()

        context.setFillColor(NSColor.black.cgColor)
        for region in regions {
            let clipped = region.intersection(sourceBox)
            guard !clipped.isNull, !clipped.isEmpty else { continue }
            context.fill(clipped.applying(transform).standardized)
        }

        guard let image = context.makeImage() else {
            throw PDFOperationError.operationFailed("Could not finish a secure page raster")
        }
        let nsImage = NSImage(cgImage: image, size: outputSize)
        guard let outputPage = PDFPage(image: nsImage) else {
            throw PDFOperationError.operationFailed("Could not assemble a sanitized PDF page")
        }
        outputPage.setBounds(outputBox, for: .mediaBox)
        outputPage.setBounds(outputBox, for: .cropBox)
        return outputPage
    }
}
