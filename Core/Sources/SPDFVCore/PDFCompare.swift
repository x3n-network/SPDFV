import AppKit
import Foundation
import PDFKit

public extension PDFOperations {
    /// Aligns matching pages or compares them by position. Appearance is
    /// rasterized at a fixed size while text and structural signals remain
    /// independent so the report explains changes without exposing contents.
    static func compare(
        reference: PDFDocument,
        candidate: PDFDocument,
        options: PDFComparisonOptions = PDFComparisonOptions()
    ) throws -> PDFComparisonReport {
        guard !reference.isLocked, !candidate.isLocked else {
            throw PDFOperationError.invalidInput("Unlock both PDFs before comparing them")
        }

        let pairs = alignedPagePairs(reference: reference, candidate: candidate, alignment: options.alignment)
        let pages = pairs.enumerated().map { offset, pair in
            comparePages(
                pair.reference.map { reference.page(at: $0) } ?? nil,
                pair.candidate.map { candidate.page(at: $0) } ?? nil,
                position: offset + 1,
                referencePage: pair.reference.map { $0 + 1 },
                candidatePage: pair.candidate.map { $0 + 1 },
                options: options
            )
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
            options: options,
            pages: pages
        )
    }
}

private extension PDFOperations {
    typealias ComparisonPagePair = (reference: Int?, candidate: Int?)

    static func comparePages(
        _ reference: PDFPage?,
        _ candidate: PDFPage?,
        position: Int,
        referencePage: Int?,
        candidatePage: Int?,
        options: PDFComparisonOptions
    ) -> PDFPageComparison {
        guard let reference else {
            return oneSidedPage(
                candidate,
                position: position,
                pageNumber: candidatePage,
                status: .added,
                isReference: false
            )
        }
        guard let candidate else {
            return oneSidedPage(
                reference,
                position: position,
                pageNumber: referencePage,
                status: .removed,
                isReference: true
            )
        }

        let referenceDimensions = dimensions(of: reference)
        let candidateDimensions = dimensions(of: candidate)
        let referenceText = normalizedText(reference.string)
        let candidateText = normalizedText(candidate.string)
        let referenceInventory = inventory(of: reference)
        let candidateInventory = inventory(of: candidate)
        let similarity = appearanceSimilarity(reference, candidate, ignoredRegions: options.ignoredRegions)
        var differences: [PDFPageDifference] = []

        if similarity.map({ $0 < options.minimumAppearanceSimilarity }) == true { differences.append(.appearance) }
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
            referencePage: referencePage,
            candidatePage: candidatePage,
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
        pageNumber: Int?,
        status: PDFPageComparisonStatus,
        isReference: Bool
    ) -> PDFPageComparison {
        let dimensions = page.map(dimensions(of:))
        let textCount = normalizedText(page?.string).count
        let inventory = page.map(inventory(of:)) ?? .empty
        return PDFPageComparison(
            position: position,
            referencePage: isReference ? pageNumber : nil,
            candidatePage: isReference ? nil : pageNumber,
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

    static func alignedPagePairs(
        reference: PDFDocument,
        candidate: PDFDocument,
        alignment: PDFComparisonAlignment
    ) -> [ComparisonPagePair] {
        guard alignment == .intelligent else {
            return positionalPairs(referenceCount: reference.pageCount, candidateCount: candidate.pageCount)
        }
        let referenceKeys = (0..<reference.pageCount).map { reference.page(at: $0).map(alignmentKey) ?? "" }
        let candidateKeys = (0..<candidate.pageCount).map { candidate.page(at: $0).map(alignmentKey) ?? "" }
        let anchors = longestCommonPageAnchors(referenceKeys, candidateKeys)
        guard !anchors.isEmpty else {
            return positionalPairs(referenceCount: reference.pageCount, candidateCount: candidate.pageCount)
        }

        var result: [ComparisonPagePair] = []
        var referenceStart = 0
        var candidateStart = 0
        for anchor in anchors {
            appendPositionalGap(
                to: &result,
                referenceRange: referenceStart..<anchor.reference,
                candidateRange: candidateStart..<anchor.candidate
            )
            result.append((anchor.reference, anchor.candidate))
            referenceStart = anchor.reference + 1
            candidateStart = anchor.candidate + 1
        }
        appendPositionalGap(
            to: &result,
            referenceRange: referenceStart..<reference.pageCount,
            candidateRange: candidateStart..<candidate.pageCount
        )
        return result
    }

    static func positionalPairs(referenceCount: Int, candidateCount: Int) -> [ComparisonPagePair] {
        var result: [ComparisonPagePair] = []
        appendPositionalGap(
            to: &result,
            referenceRange: 0..<referenceCount,
            candidateRange: 0..<candidateCount
        )
        return result
    }

    static func appendPositionalGap(
        to result: inout [ComparisonPagePair],
        referenceRange: Range<Int>,
        candidateRange: Range<Int>
    ) {
        let pairedCount = min(referenceRange.count, candidateRange.count)
        for offset in 0..<pairedCount {
            result.append((referenceRange.lowerBound + offset, candidateRange.lowerBound + offset))
        }
        for index in referenceRange.dropFirst(pairedCount) { result.append((index, nil)) }
        for index in candidateRange.dropFirst(pairedCount) { result.append((nil, index)) }
    }

    static func longestCommonPageAnchors(_ reference: [String], _ candidate: [String]) -> [(reference: Int, candidate: Int)] {
        guard !reference.isEmpty, !candidate.isEmpty else { return [] }
        // Keep memory bounded for very large documents. Unique fingerprints are
        // strong anchors and preserve order without allocating an O(n*m) table.
        if reference.count > 4_000_000 / candidate.count {
            return uniquePageAnchors(reference, candidate)
        }
        let columns = candidate.count + 1
        var lengths = [Int32](repeating: 0, count: (reference.count + 1) * columns)
        for referenceIndex in stride(from: reference.count - 1, through: 0, by: -1) {
            for candidateIndex in stride(from: candidate.count - 1, through: 0, by: -1) {
                let cell = referenceIndex * columns + candidateIndex
                if reference[referenceIndex] == candidate[candidateIndex] {
                    lengths[cell] = lengths[(referenceIndex + 1) * columns + candidateIndex + 1] + 1
                } else {
                    lengths[cell] = max(
                        lengths[(referenceIndex + 1) * columns + candidateIndex],
                        lengths[referenceIndex * columns + candidateIndex + 1]
                    )
                }
            }
        }

        var anchors: [(reference: Int, candidate: Int)] = []
        var referenceIndex = 0
        var candidateIndex = 0
        while referenceIndex < reference.count, candidateIndex < candidate.count {
            if reference[referenceIndex] == candidate[candidateIndex] {
                anchors.append((referenceIndex, candidateIndex))
                referenceIndex += 1
                candidateIndex += 1
            } else if lengths[(referenceIndex + 1) * columns + candidateIndex]
                        >= lengths[referenceIndex * columns + candidateIndex + 1] {
                referenceIndex += 1
            } else {
                candidateIndex += 1
            }
        }
        return anchors
    }

    static func uniquePageAnchors(_ reference: [String], _ candidate: [String]) -> [(reference: Int, candidate: Int)] {
        let referenceGroups = Dictionary(grouping: reference.indices, by: { reference[$0] })
        let candidateGroups = Dictionary(grouping: candidate.indices, by: { candidate[$0] })
        var lastCandidate = -1
        var anchors: [(reference: Int, candidate: Int)] = []
        for referenceIndex in reference.indices {
            let key = reference[referenceIndex]
            guard referenceGroups[key]?.count == 1,
                  let matches = candidateGroups[key], matches.count == 1,
                  let candidateIndex = matches.first,
                  candidateIndex > lastCandidate else { continue }
            anchors.append((referenceIndex, candidateIndex))
            lastCandidate = candidateIndex
        }
        return anchors
    }

    static func alignmentKey(_ page: PDFPage) -> String {
        let size = dimensions(of: page)
        let pageInventory = inventory(of: page)
        return [
            normalizedText(page.string),
            rounded(CGFloat(size.width)),
            rounded(CGFloat(size.height)),
            String(normalizedRotation(page.rotation)),
            pageInventory.annotationSignatures.joined(separator: "~"),
            pageInventory.formSignatures.joined(separator: "~")
        ].joined(separator: "|")
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

    static func appearanceSimilarity(
        _ reference: PDFPage,
        _ candidate: PDFPage,
        ignoredRegions: [PDFComparisonIgnoredRegion]
    ) -> Double? {
        guard let first = rasterBytes(reference), let second = rasterBytes(candidate), first.count == second.count else {
            return nil
        }
        var delta: UInt64 = 0
        var comparedBytes = 0
        let bytesPerPixel = 4
        let width = 128
        for index in stride(from: 0, to: first.count, by: bytesPerPixel) {
            let pixel = index / bytesPerPixel
            let x = pixel % width
            let y = pixel / width
            guard !isIgnored(x: x, y: y, width: width, height: 128, regions: ignoredRegions) else { continue }
            for channel in 0..<bytesPerPixel {
                delta += UInt64(abs(Int(first[index + channel]) - Int(second[index + channel])))
                comparedBytes += 1
            }
        }
        let maximum = Double(comparedBytes * 255)
        guard maximum > 0 else { return 1 }
        return ((1 - Double(delta) / maximum) * 10_000).rounded() / 10_000
    }

    static func isIgnored(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        regions: [PDFComparisonIgnoredRegion]
    ) -> Bool {
        let normalizedX = (Double(x) + 0.5) / Double(width)
        let normalizedY = (Double(y) + 0.5) / Double(height)
        return regions.contains { region in
            normalizedX >= region.x && normalizedX <= region.x + region.width
                && normalizedY >= region.y && normalizedY <= region.y + region.height
        }
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
