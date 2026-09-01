import AppKit
import PDFKit
import SPDFVCore
import UniformTypeIdentifiers

enum ComparisonVisualizationMode: String, CaseIterable, Identifiable {
    case sideBySide
    case overlay
    case heatmap

    var id: Self { self }
}

extension DocumentSession {
    func compareWithPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the reference PDF to compare with the open document"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        compare(with: url, options: comparisonOptions)
    }

    func compare(with referenceURL: URL, options: PDFComparisonOptions = PDFComparisonOptions()) {
        guard let candidateData = document?.dataRepresentation() else {
            errorMessage = "The open PDF could not be prepared for comparison."
            return
        }

        let accessed = referenceURL.startAccessingSecurityScopedResource()
        defer { if accessed { referenceURL.stopAccessingSecurityScopedResource() } }

        do {
            let referenceData = try Data(contentsOf: referenceURL)
            let referenceName = referenceURL.lastPathComponent
            let requestID = UUID()
            comparisonRequestID = requestID
            isComparing = true
            comparisonReport = nil
            comparisonReferenceName = referenceName
            comparisonReferenceDocument = nil
            comparisonOptions = options
            selectedComparisonPosition = nil

            Task {
                do {
                    let report = try await Task.detached(priority: .userInitiated) {
                        guard let reference = PDFDocument(data: referenceData),
                              let candidate = PDFDocument(data: candidateData) else {
                            throw PDFOperationError.invalidInput("Both files must be readable PDFs")
                        }
                        return try PDFOperations.compare(reference: reference, candidate: candidate, options: options)
                    }.value
                    guard comparisonRequestID == requestID else { return }
                    comparisonReport = report
                    comparisonReferenceDocument = PDFDocument(data: referenceData)
                    selectedComparisonPosition = report.pages.first(where: { $0.status != .unchanged })?.position
                        ?? report.pages.first?.position
                } catch {
                    guard comparisonRequestID == requestID else { return }
                    comparisonReferenceName = nil
                    comparisonReferenceDocument = nil
                    errorMessage = (error as? PDFOperationError)?.description ?? error.localizedDescription
                }
                guard comparisonRequestID == requestID else { return }
                isComparing = false
                comparisonRequestID = nil
            }
        } catch {
            comparisonReferenceName = nil
            comparisonReferenceDocument = nil
            errorMessage = "Could not read “\(referenceURL.lastPathComponent)”: \(error.localizedDescription)"
        }
    }

    func clearComparison() {
        comparisonReport = nil
        comparisonReferenceName = nil
        comparisonReferenceDocument = nil
        selectedComparisonPosition = nil
        isComparing = false
        comparisonRequestID = nil
    }

    func rerunComparison(options: PDFComparisonOptions) {
        guard let referenceData = comparisonReferenceDocument?.dataRepresentation(),
              let candidateData = document?.dataRepresentation() else { return }
        let requestID = UUID()
        comparisonRequestID = requestID
        comparisonOptions = options
        comparisonReport = nil
        selectedComparisonPosition = nil
        isComparing = true
        Task {
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    guard let reference = PDFDocument(data: referenceData),
                          let candidate = PDFDocument(data: candidateData) else {
                        throw PDFOperationError.invalidInput("Both files must be readable PDFs")
                    }
                    return try PDFOperations.compare(reference: reference, candidate: candidate, options: options)
                }.value
                guard comparisonRequestID == requestID else { return }
                comparisonReport = report
                selectedComparisonPosition = report.pages.first(where: { $0.status != .unchanged })?.position
                    ?? report.pages.first?.position
            } catch {
                guard comparisonRequestID == requestID else { return }
                errorMessage = (error as? PDFOperationError)?.description ?? error.localizedDescription
            }
            guard comparisonRequestID == requestID else { return }
            isComparing = false
            comparisonRequestID = nil
        }
    }

    func showComparisonPage(_ comparison: PDFPageComparison) {
        selectedComparisonPosition = comparison.position
        guard let page = comparison.candidatePage else { return }
        goToPage(page - 1)
    }

    func comparisonPage(at position: Int?) -> PDFPageComparison? {
        guard let position else { return nil }
        return comparisonReport?.pages.first { $0.position == position }
    }

    func comparisonImages(for page: PDFPageComparison, size: NSSize) -> (reference: NSImage?, candidate: NSImage?) {
        let referenceImage = page.referencePage.flatMap { pageNumber in
            comparisonReferenceDocument?.page(at: pageNumber - 1)?.thumbnail(of: size, for: .cropBox)
        }
        let candidateImage = page.candidatePage.flatMap { pageNumber in
            document?.page(at: pageNumber - 1)?.thumbnail(of: size, for: .cropBox)
        }
        return (referenceImage, candidateImage)
    }

    func comparisonHeatmap(for page: PDFPageComparison, size: NSSize) -> NSImage? {
        let images = comparisonImages(for: page, size: size)
        guard let reference = images.reference, let candidate = images.candidate,
              let referenceBytes = Self.bitmapBytes(reference, size: size),
              let candidateBytes = Self.bitmapBytes(candidate, size: size),
              referenceBytes.bytes.count == candidateBytes.bytes.count,
              let output = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: referenceBytes.width,
                pixelsHigh: referenceBytes.height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [],
                bytesPerRow: referenceBytes.width * 4,
                bitsPerPixel: 32
              ), let outputData = output.bitmapData else { return nil }

        for index in stride(from: 0, to: referenceBytes.bytes.count, by: 4) {
            let pixel = index / 4
            let x = pixel % referenceBytes.width
            let y = pixel / referenceBytes.width
            let isIgnored = comparisonOptions.ignoredRegions.contains { region in
                let normalizedX = (Double(x) + 0.5) / Double(referenceBytes.width)
                let normalizedY = (Double(y) + 0.5) / Double(referenceBytes.height)
                return normalizedX >= region.x && normalizedX <= region.x + region.width
                    && normalizedY >= region.y && normalizedY <= region.y + region.height
            }
            let difference = isIgnored ? 0 : max(
                abs(Int(referenceBytes.bytes[index]) - Int(candidateBytes.bytes[index])),
                abs(Int(referenceBytes.bytes[index + 1]) - Int(candidateBytes.bytes[index + 1])),
                abs(Int(referenceBytes.bytes[index + 2]) - Int(candidateBytes.bytes[index + 2]))
            )
            let luminance = UInt8((
                Int(candidateBytes.bytes[index]) + Int(candidateBytes.bytes[index + 1]) + Int(candidateBytes.bytes[index + 2])
            ) / 3)
            if difference > 8 {
                outputData[index] = 255
                outputData[index + 1] = UInt8(max(0, 220 - difference))
                outputData[index + 2] = 0
            } else {
                let muted = UInt8((Int(luminance) + 220) / 2)
                outputData[index] = muted
                outputData[index + 1] = muted
                outputData[index + 2] = muted
            }
            outputData[index + 3] = 255
        }
        let image = NSImage(size: size)
        image.addRepresentation(output)
        return image
    }

    func exportComparisonReport() {
        guard let comparisonReport else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = comparisonExportName
        panel.message = "Export a privacy-conscious comparison report"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(comparisonReport).write(to: url, options: .atomic)
        } catch {
            errorMessage = "Could not export the comparison report: \(error.localizedDescription)"
        }
    }

    private var comparisonExportName: String {
        let stem = fileURL?.deletingPathExtension().lastPathComponent ?? "comparison"
        return "\(stem)-comparison.json"
    }


    private static func bitmapBytes(_ image: NSImage, size: NSSize) -> (bytes: [UInt8], width: Int, height: Int)? {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
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
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(origin: .zero, size: size))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = representation.bitmapData else { return nil }
        return (Array(UnsafeBufferPointer(start: data, count: representation.bytesPerRow * height)), width, height)
    }
}
