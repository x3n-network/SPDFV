import AppKit
import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Vision

public enum PDFOCRRecognitionLevel: String, Codable, CaseIterable, Sendable {
    case fast
    case accurate
}

public struct PDFOCRConfiguration: Codable, Equatable, Sendable {
    public var recognitionLevel: PDFOCRRecognitionLevel
    public var languages: [String]
    public var usesLanguageCorrection: Bool
    public var renderDPI: Double

    public init(
        recognitionLevel: PDFOCRRecognitionLevel = .accurate,
        languages: [String] = [],
        usesLanguageCorrection: Bool = true,
        renderDPI: Double = 216
    ) {
        self.recognitionLevel = recognitionLevel
        self.languages = languages
        self.usesLanguageCorrection = usesLanguageCorrection
        self.renderDPI = min(max(renderDPI, 72), 400)
    }
}

public struct PDFOCRPageReport: Codable, Equatable, Sendable {
    public let page: Int
    public let recognizedLines: Int
    public let recognizedCharacters: Int

    public init(page: Int, recognizedLines: Int, recognizedCharacters: Int) {
        self.page = page
        self.recognizedLines = recognizedLines
        self.recognizedCharacters = recognizedCharacters
    }
}

public struct PDFOCRReport: Codable, Equatable, Sendable {
    public let pages: [Int]
    public let pageCount: Int
    public let recognizedLines: Int
    public let recognizedCharacters: Int
    public let recognitionLevel: PDFOCRRecognitionLevel
    public let languages: [String]
    public let pageDetails: [PDFOCRPageReport]

    public init(
        pages: [Int],
        pageCount: Int,
        recognizedLines: Int,
        recognizedCharacters: Int,
        recognitionLevel: PDFOCRRecognitionLevel,
        languages: [String],
        pageDetails: [PDFOCRPageReport]
    ) {
        self.pages = pages
        self.pageCount = pageCount
        self.recognizedLines = recognizedLines
        self.recognizedCharacters = recognizedCharacters
        self.recognitionLevel = recognitionLevel
        self.languages = languages
        self.pageDetails = pageDetails
    }
}

public struct PDFOCRResult: Sendable {
    public let data: Data
    public let report: PDFOCRReport

    public init(data: Data, report: PDFOCRReport) {
        self.data = data
        self.report = report
    }
}

public extension PDFOperations {
    static func makeSearchable(
        data: Data,
        pageIndices: [Int]? = nil,
        configuration: PDFOCRConfiguration = PDFOCRConfiguration()
    ) throws -> PDFOCRResult {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw PDFOperationError.invalidInput("Input is not a readable PDF")
        }
        let indices = try PDFPageSelection.validate(
            pageIndices ?? Array(0..<document.pageCount),
            pageCount: document.pageCount
        )
        let selected = Set(indices)
        let output = PDFDocument()
        output.documentAttributes = document.documentAttributes
        var reports: [PDFOCRPageReport] = []

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else {
                throw PDFOperationError.operationFailed("Could not read page \(index + 1)")
            }
            if selected.contains(index) {
                let processed = try searchablePage(from: page, configuration: configuration)
                output.insert(processed.page, at: output.pageCount)
                reports.append(PDFOCRPageReport(
                    page: index + 1,
                    recognizedLines: processed.lines.count,
                    recognizedCharacters: processed.lines.reduce(0) { $0 + $1.text.count }
                ))
            } else {
                guard let copy = page.copy() as? PDFPage else {
                    throw PDFOperationError.operationFailed("Could not copy page \(index + 1)")
                }
                output.insert(copy, at: output.pageCount)
            }
        }

        guard let outputData = output.dataRepresentation(),
              let reopened = PDFDocument(data: outputData),
              reopened.pageCount == document.pageCount else {
            throw PDFOperationError.operationFailed("OCR output failed PDF round-trip verification")
        }

        let report = PDFOCRReport(
            pages: indices.map { $0 + 1 },
            pageCount: document.pageCount,
            recognizedLines: reports.reduce(0) { $0 + $1.recognizedLines },
            recognizedCharacters: reports.reduce(0) { $0 + $1.recognizedCharacters },
            recognitionLevel: configuration.recognitionLevel,
            languages: configuration.languages,
            pageDetails: reports
        )
        return PDFOCRResult(data: outputData, report: report)
    }

    static func write(
        _ result: PDFOCRResult,
        to url: URL,
        overwrite: Bool = false
    ) throws {
        if FileManager.default.fileExists(atPath: url.path), !overwrite {
            throw PDFOperationError.outputExists("Output already exists; pass --force to replace it: \(url.path)")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try result.data.write(to: url, options: .atomic)
        guard let reopened = PDFDocument(url: url), reopened.pageCount == result.report.pageCount else {
            throw PDFOperationError.operationFailed("OCR output failed PDF round-trip verification")
        }
    }
}

private extension PDFOperations {
    struct RecognizedLine {
        let text: String
        let normalizedBounds: CGRect
    }

    struct SearchablePage {
        let page: PDFPage
        let lines: [RecognizedLine]
    }

    static func searchablePage(
        from sourcePage: PDFPage,
        configuration: PDFOCRConfiguration
    ) throws -> SearchablePage {
        let sourceBox = sourcePage.bounds(for: .cropBox)
        let quarterTurns = ((sourcePage.rotation % 360) + 360) % 360
        let isSideways = quarterTurns == 90 || quarterTurns == 270
        let outputSize = isSideways
            ? CGSize(width: sourceBox.height, height: sourceBox.width)
            : sourceBox.size
        let outputBox = CGRect(origin: .zero, size: outputSize)
        let scale = CGFloat(configuration.renderDPI / 72)

        guard let image = render(
            sourcePage,
            sourceBox: sourceBox,
            outputBox: outputBox,
            pixelWidth: max(1, Int((outputBox.width * scale).rounded())),
            pixelHeight: max(1, Int((outputBox.height * scale).rounded()))
        ) else {
            throw PDFOperationError.operationFailed("Could not render a page for OCR")
        }
        let lines = try recognize(image, configuration: configuration)

        let data = NSMutableData()
        var mediaBox = outputBox
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PDFOperationError.operationFailed("Could not create OCR PDF context")
        }
        context.beginPDFPage(nil)
        draw(sourcePage, sourceBox: sourceBox, into: outputBox, context: context)
        drawInvisibleText(lines, in: outputBox, context: context)
        context.endPDFPage()
        context.closePDF()

        guard let pageDocument = PDFDocument(data: data as Data),
              let page = pageDocument.page(at: 0)?.copy() as? PDFPage else {
            throw PDFOperationError.operationFailed("Could not assemble OCR page")
        }
        copyAnnotations(from: sourcePage, to: page, outputBox: outputBox)
        return SearchablePage(page: page, lines: lines)
    }

    static func copyAnnotations(from source: PDFPage, to destination: PDFPage, outputBox: CGRect) {
        guard let pageRef = source.pageRef else { return }
        let transform = pageRef.getDrawingTransform(
            .cropBox,
            rect: outputBox,
            rotate: 0,
            preserveAspectRatio: true
        )
        for annotation in source.annotations {
            guard let copy = annotation.copy() as? PDFAnnotation else { continue }
            copy.bounds = annotation.bounds.applying(transform).standardized
            destination.addAnnotation(copy)
        }
    }

    static func render(
        _ page: PDFPage,
        sourceBox: CGRect,
        outputBox: CGRect,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(
            x: CGFloat(pixelWidth) / outputBox.width,
            y: CGFloat(pixelHeight) / outputBox.height
        )
        draw(page, sourceBox: sourceBox, into: outputBox, context: context)
        return context.makeImage()
    }

    static func draw(
        _ page: PDFPage,
        sourceBox: CGRect,
        into outputBox: CGRect,
        context: CGContext
    ) {
        context.saveGState()
        if let pageRef = page.pageRef {
            let transform = pageRef.getDrawingTransform(
                .cropBox,
                rect: outputBox,
                rotate: 0,
                preserveAspectRatio: true
            )
            context.concatenate(transform)
            context.drawPDFPage(pageRef)
        } else {
            context.translateBy(x: -sourceBox.minX, y: -sourceBox.minY)
            page.draw(with: .cropBox, to: context)
        }
        context.restoreGState()
    }

    static func recognize(
        _ image: CGImage,
        configuration: PDFOCRConfiguration
    ) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = configuration.recognitionLevel == .accurate ? .accurate : .fast
        request.usesLanguageCorrection = configuration.usesLanguageCorrection
        request.automaticallyDetectsLanguage = configuration.languages.isEmpty
        if !configuration.languages.isEmpty {
            request.recognitionLanguages = configuration.languages
        }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RecognizedLine(text: text, normalizedBounds: observation.boundingBox)
        }
    }

    static func drawInvisibleText(
        _ lines: [RecognizedLine],
        in pageBox: CGRect,
        context: CGContext
    ) {
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        for item in lines {
            let rect = CGRect(
                x: pageBox.minX + item.normalizedBounds.minX * pageBox.width,
                y: pageBox.minY + item.normalizedBounds.minY * pageBox.height,
                width: item.normalizedBounds.width * pageBox.width,
                height: item.normalizedBounds.height * pageBox.height
            )
            guard rect.width > 0.5, rect.height > 0.5 else { continue }
            let font = CTFontCreateWithName("Helvetica" as CFString, max(4, rect.height * 0.82), nil)
            let attributes = [kCTFontAttributeName: font] as CFDictionary
            let attributed = CFAttributedStringCreate(nil, item.text as CFString, attributes)!
            let line = CTLineCreateWithAttributedString(attributed)
            let lineWidth = max(0.1, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))

            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.minY + max(0, (rect.height - CTFontGetAscent(font)) * 0.5))
            context.scaleBy(x: rect.width / lineWidth, y: 1)
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
        }
        context.restoreGState()
    }
}
