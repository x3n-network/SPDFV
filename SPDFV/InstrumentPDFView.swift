import AppKit
import PDFKit

@MainActor
final class InstrumentPDFView: PDFView {
    var annotationTool: CanvasAnnotationTool = .select {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    var selectedAnnotation: PDFAnnotation? {
        didSet {
            if oldValue !== selectedAnnotation {
                needsDisplay = true
            }
        }
    }
    var selectedFormWidget: PDFAnnotation? {
        didSet {
            if oldValue !== selectedFormWidget { needsDisplay = true }
        }
    }
    var isCropEditing = false {
        didSet {
            guard oldValue != isCropEditing else { return }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }
    var isRedactionEditing = false {
        didSet {
            guard oldValue != isRedactionEditing else { return }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }
    var redactionMarks: [PendingRedaction] = [] {
        didSet { needsDisplay = true }
    }
    var onPageClick: ((PDFPage, CGPoint) -> Bool)?
    var onInkStroke: ((PDFPage, [CGPoint]) -> Void)?
    var onAnnotationTransformEnd: ((PDFAnnotation, PDFPage, CGRect) -> Void)?
    var onCropTransformEnd: ((PDFPage, CGRect, CGRect) -> Void)?
    var onRedactionRegion: ((PDFPage, CGRect) -> Void)?

    private var inkPage: PDFPage?
    private var inkPoints: [CGPoint] = []
    private var transformPage: PDFPage?
    private var transformStartPoint: CGPoint?
    private var transformOriginalBounds: CGRect?
    private var transformMode: AnnotationTransformMode?
    private var cropPage: PDFPage?
    private var cropHandle: CropHandle?
    private var cropOriginalBounds: CGRect?
    private var redactionPage: PDFPage?
    private var redactionStartPoint: CGPoint?
    private var redactionDraftBounds: CGRect?

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else {
            super.mouseDown(with: event)
            return
        }
        let pagePoint = convert(viewPoint, to: page)

        if isRedactionEditing {
            redactionPage = page
            redactionStartPoint = pagePoint
            redactionDraftBounds = CGRect(origin: pagePoint, size: .zero)
            go(to: page)
            needsDisplay = true
            return
        }

        if isCropEditing {
            if let handle = cropHandle(at: pagePoint, for: page) {
                cropPage = page
                cropHandle = handle
                cropOriginalBounds = page.bounds(for: .cropBox)
                go(to: page)
            }
            return
        }

        if annotationTool == .select,
           let transformAnnotation,
           transformAnnotation.page === page {
            let handle = resizeHandle(for: transformAnnotation.bounds)
            if handle.insetBy(dx: -4, dy: -4).contains(pagePoint) {
                beginTransform(.resize, page: page, point: pagePoint, bounds: transformAnnotation.bounds)
                return
            }
            if transformAnnotation.bounds.contains(pagePoint) {
                beginTransform(.move, page: page, point: pagePoint, bounds: transformAnnotation.bounds)
                return
            }
        }

        if annotationTool == .ink {
            inkPage = page
            inkPoints = [pagePoint]
            return
        }

        if onPageClick?(page, pagePoint) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let redactionPage, let redactionStartPoint {
            let viewPoint = convert(event.locationInWindow, from: nil)
            let point = convert(viewPoint, to: redactionPage)
            let pageBox = redactionPage.bounds(for: .cropBox)
            let start = CGPoint(
                x: min(max(redactionStartPoint.x, pageBox.minX), pageBox.maxX),
                y: min(max(redactionStartPoint.y, pageBox.minY), pageBox.maxY)
            )
            let end = CGPoint(
                x: min(max(point.x, pageBox.minX), pageBox.maxX),
                y: min(max(point.y, pageBox.minY), pageBox.maxY)
            )
            redactionDraftBounds = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            needsDisplay = true
            return
        }

        if let cropPage, let cropHandle, let cropOriginalBounds {
            let viewPoint = convert(event.locationInWindow, from: nil)
            let pagePoint = convert(viewPoint, to: cropPage)
            let mediaBox = cropPage.bounds(for: .mediaBox)
            cropPage.setBounds(
                cropHandle.adjustedBounds(
                    from: cropOriginalBounds,
                    toward: pagePoint,
                    within: mediaBox,
                    minimumDimension: 72
                ),
                for: .cropBox
            )
            needsDisplay = true
            return
        }

        if let transformPage,
           let transformStartPoint,
           let transformOriginalBounds,
           let transformMode,
           let transformAnnotation {
            let viewPoint = convert(event.locationInWindow, from: nil)
            let pagePoint = convert(viewPoint, to: transformPage)
            let pageBounds = transformPage.bounds(for: .cropBox)
            let delta = CGPoint(
                x: pagePoint.x - transformStartPoint.x,
                y: pagePoint.y - transformStartPoint.y
            )

            switch transformMode {
            case .move:
                let dx = min(
                    max(delta.x, pageBounds.minX - transformOriginalBounds.minX),
                    pageBounds.maxX - transformOriginalBounds.maxX
                )
                let dy = min(
                    max(delta.y, pageBounds.minY - transformOriginalBounds.minY),
                    pageBounds.maxY - transformOriginalBounds.maxY
                )
                transformAnnotation.bounds = transformOriginalBounds.offsetBy(dx: dx, dy: dy)
            case .resize:
                let width = min(
                    max(18, transformOriginalBounds.width + delta.x),
                    pageBounds.maxX - transformOriginalBounds.minX
                )
                let height = min(
                    max(18, transformOriginalBounds.height + delta.y),
                    pageBounds.maxY - transformOriginalBounds.minY
                )
                transformAnnotation.bounds = CGRect(
                    x: transformOriginalBounds.minX,
                    y: transformOriginalBounds.minY,
                    width: width,
                    height: height
                )
            }
            annotationsChanged(on: transformPage)
            needsDisplay = true
            return
        }

        guard annotationTool == .ink, let page = inkPage else {
            super.mouseDragged(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard self.page(for: viewPoint, nearest: true) === page else { return }
        inkPoints.append(convert(viewPoint, to: page))
    }

    override func mouseUp(with event: NSEvent) {
        if let page = redactionPage, let bounds = redactionDraftBounds {
            redactionPage = nil
            redactionStartPoint = nil
            redactionDraftBounds = nil
            if bounds.width >= 6, bounds.height >= 6 {
                onRedactionRegion?(page, bounds)
            }
            needsDisplay = true
            return
        }

        if let page = cropPage, let originalBounds = cropOriginalBounds {
            let newBounds = page.bounds(for: .cropBox)
            cropPage = nil
            cropHandle = nil
            cropOriginalBounds = nil
            onCropTransformEnd?(page, originalBounds, newBounds)
            needsDisplay = true
            return
        }

        if let page = transformPage,
           let originalBounds = transformOriginalBounds,
           let transformAnnotation {
            transformPage = nil
            transformStartPoint = nil
            transformOriginalBounds = nil
            transformMode = nil
            onAnnotationTransformEnd?(transformAnnotation, page, originalBounds)
            return
        }

        guard annotationTool == .ink, let page = inkPage else {
            super.mouseUp(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        if self.page(for: viewPoint, nearest: true) === page {
            inkPoints.append(convert(viewPoint, to: page))
        }
        let points = inkPoints
        inkPage = nil
        inkPoints = []
        onInkStroke?(page, points)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let cursor: NSCursor = isCropEditing || isRedactionEditing
            ? .crosshair
            : (annotationTool == .select ? .arrow : .crosshair)
        addCursorRect(bounds, cursor: cursor)
    }

    override func drawPagePost(_ page: PDFPage, to context: CGContext) {
        super.drawPagePost(page, to: context)
        if isCropEditing, currentPage === page {
            drawCropPlate(on: page, to: context)
        }
        drawRedactionMarks(on: page, to: context)
        guard let transformAnnotation, transformAnnotation.page === page else { return }
        context.saveGState()
        context.setStrokeColor((transformAnnotation.isFormWidget ? NSColor.systemPurple : NSColor.systemBlue).cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.stroke(transformAnnotation.bounds.insetBy(dx: -3, dy: -3))
        context.setLineDash(phase: 0, lengths: [])
        let handle = resizeHandle(for: transformAnnotation.bounds)
        context.setFillColor((transformAnnotation.isFormWidget ? NSColor.systemPurple : NSColor.systemBlue).cgColor)
        context.fill(handle)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.stroke(handle)
        context.restoreGState()
    }

    private func beginTransform(
        _ mode: AnnotationTransformMode,
        page: PDFPage,
        point: CGPoint,
        bounds: CGRect
    ) {
        transformMode = mode
        transformPage = page
        transformStartPoint = point
        transformOriginalBounds = bounds
    }

    private var transformAnnotation: PDFAnnotation? {
        selectedAnnotation ?? selectedFormWidget
    }

    private func resizeHandle(for bounds: CGRect) -> CGRect {
        CGRect(x: bounds.maxX - 4, y: bounds.maxY - 4, width: 8, height: 8)
    }

    private func cropHandle(at point: CGPoint, for page: PDFPage) -> CropHandle? {
        let cropBox = page.bounds(for: .cropBox)
        let hitSize = max(10, 14 / max(scaleFactor, 0.1))
        return CropHandle.allCases.first { handle in
            let center = handle.point(in: cropBox)
            return CGRect(
                x: center.x - hitSize / 2,
                y: center.y - hitSize / 2,
                width: hitSize,
                height: hitSize
            ).contains(point)
        }
    }

    private func drawCropPlate(on page: PDFPage, to context: CGContext) {
        let mediaBox = page.bounds(for: .mediaBox)
        let cropBox = page.bounds(for: .cropBox)
        let unit = 1 / max(scaleFactor, 0.1)

        context.saveGState()
        context.addRect(mediaBox)
        context.addRect(cropBox)
        context.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        context.drawPath(using: .eoFill)

        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2 * unit)
        context.setLineDash(phase: 0, lengths: [7 * unit, 4 * unit])
        context.stroke(cropBox)
        context.setLineDash(phase: 0, lengths: [])

        let handleSize = 10 * unit
        for handle in CropHandle.allCases {
            let cropPoint = handle.point(in: cropBox)
            let point = CGPoint(
                x: min(max(cropPoint.x, mediaBox.minX + handleSize / 2), mediaBox.maxX - handleSize / 2),
                y: min(max(cropPoint.y, mediaBox.minY + handleSize / 2), mediaBox.maxY - handleSize / 2)
            )
            let rect = CGRect(
                x: point.x - handleSize / 2,
                y: point.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.setFillColor(NSColor.systemBlue.cgColor)
            context.fill(rect)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(unit)
            context.stroke(rect)
        }
        context.restoreGState()
    }

    private func drawRedactionMarks(on page: PDFPage, to context: CGContext) {
        let marks = redactionMarks.filter { $0.page === page }.map(\.bounds)
        let draft = redactionPage === page ? redactionDraftBounds : nil
        guard !marks.isEmpty || draft != nil else { return }
        let unit = 1 / max(scaleFactor, 0.1)

        context.saveGState()
        for (index, bounds) in marks.enumerated() {
            context.setFillColor(NSColor.black.withAlphaComponent(0.82).cgColor)
            context.fill(bounds)
            context.setStrokeColor(NSColor.systemRed.cgColor)
            context.setLineWidth(1.5 * unit)
            context.stroke(bounds)

            context.saveGState()
            context.clip(to: bounds)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
            context.setLineWidth(unit)
            var x = bounds.minX - bounds.height
            while x < bounds.maxX {
                context.move(to: CGPoint(x: x, y: bounds.minY))
                context.addLine(to: CGPoint(x: x + bounds.height, y: bounds.maxY))
                x += 10 * unit
            }
            context.strokePath()
            context.restoreGState()

            let tab = CGRect(x: bounds.minX, y: bounds.maxY - 13 * unit, width: 25 * unit, height: 13 * unit)
            context.setFillColor(NSColor.systemRed.cgColor)
            context.fill(tab)
            let label = String(format: "%02d", index + 1)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 8 * unit, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            label.draw(at: CGPoint(x: tab.minX + 4 * unit, y: tab.minY + 2 * unit), withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
        }

        if let draft {
            context.setFillColor(NSColor.black.withAlphaComponent(0.48).cgColor)
            context.fill(draft)
            context.setStrokeColor(NSColor.systemRed.cgColor)
            context.setLineWidth(2 * unit)
            context.setLineDash(phase: 0, lengths: [5 * unit, 3 * unit])
            context.stroke(draft)
        }
        context.restoreGState()
    }
}

private enum AnnotationTransformMode {
    case move
    case resize
}

private enum CropHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    func point(in bounds: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: bounds.minX, y: bounds.maxY)
        case .top: CGPoint(x: bounds.midX, y: bounds.maxY)
        case .topRight: CGPoint(x: bounds.maxX, y: bounds.maxY)
        case .right: CGPoint(x: bounds.maxX, y: bounds.midY)
        case .bottomRight: CGPoint(x: bounds.maxX, y: bounds.minY)
        case .bottom: CGPoint(x: bounds.midX, y: bounds.minY)
        case .bottomLeft: CGPoint(x: bounds.minX, y: bounds.minY)
        case .left: CGPoint(x: bounds.minX, y: bounds.midY)
        }
    }

    func adjustedBounds(
        from original: CGRect,
        toward point: CGPoint,
        within media: CGRect,
        minimumDimension: CGFloat
    ) -> CGRect {
        var minX = original.minX
        var maxX = original.maxX
        var minY = original.minY
        var maxY = original.maxY

        switch self {
        case .topLeft, .left, .bottomLeft:
            minX = min(max(point.x, media.minX), maxX - minimumDimension)
        case .topRight, .right, .bottomRight:
            maxX = max(min(point.x, media.maxX), minX + minimumDimension)
        default: break
        }

        switch self {
        case .topLeft, .top, .topRight:
            maxY = max(min(point.y, media.maxY), minY + minimumDimension)
        case .bottomLeft, .bottom, .bottomRight:
            minY = min(max(point.y, media.minY), maxY - minimumDimension)
        default: break
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
