import PDFKit
import SPDFVCore
import SwiftUI

struct PDFWorkspace: NSViewRepresentable {
    @ObservedObject var session: DocumentSession
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = context.coordinator.pdfView
        pdfView.setAccessibilityLabel("PDF document")
        pdfView.backgroundColor = SPDFVTheme.canvasNSColor(for: colorScheme)
        context.coordinator.selectionColor = SPDFVTheme.selectionNSColor(for: colorScheme)
        context.coordinator.startObserving()
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        let coordinator = context.coordinator
        let canvasColor = SPDFVTheme.canvasNSColor(for: colorScheme)
        if pdfView.backgroundColor != canvasColor {
            pdfView.backgroundColor = canvasColor
        }
        coordinator.selectionColor = SPDFVTheme.selectionNSColor(for: colorScheme)
        coordinator.pdfView.annotationTool = session.activeAnnotationTool
        coordinator.pdfView.selectedAnnotation = session.selectedAnnotation?.annotation
        coordinator.pdfView.selectedFormWidget = session.selectedFormField?.annotation
        coordinator.pdfView.isCropEditing = session.isCropEditing
        coordinator.pdfView.isRedactionEditing = session.isRedactionEditing
        coordinator.pdfView.redactionMarks = session.pendingRedactions
        let displayBox: PDFDisplayBox = session.isCropEditing ? .mediaBox : .cropBox
        if pdfView.displayBox != displayBox {
            pdfView.displayBox = displayBox
            pdfView.layoutDocumentView()
        }

        if pdfView.document !== session.document {
            pdfView.document = session.document
            applyLayout(session.pageLayout, to: pdfView)
            pdfView.autoScales = true
            Task { @MainActor [weak coordinator] in
                coordinator?.reportState()
            }
        }

        if let command = session.pendingCommand, command.id != coordinator.lastCommandID {
            coordinator.lastCommandID = command.id
            Task { @MainActor [weak coordinator] in
                coordinator?.perform(command.action)
            }
        }
    }

    private func applyLayout(_ layout: PageLayoutMode, to pdfView: PDFView) {
        pdfView.displayMode = layout.displayMode
        pdfView.displaysAsBook = layout.displaysAsBook
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator: NSObject {
        let pdfView = InstrumentPDFView()
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        var lastCommandID: UUID?
        var selectionColor = NSColor.selectedTextBackgroundColor

        private let session: DocumentSession
        private var observers: [NSObjectProtocol] = []

        init(session: DocumentSession) {
            self.session = session
            super.init()

            pdfView.displayMode = .singlePageContinuous
            pdfView.displayDirection = .vertical
            pdfView.displaysPageBreaks = true
            pdfView.pageShadowsEnabled = true
            pdfView.onPageClick = { [weak self] page, point in
                self?.handlePageClick(page: page, point: point) ?? false
            }
            pdfView.onInkStroke = { [weak self] page, points in
                self?.addInkAnnotation(to: page, points: points)
            }
            pdfView.onAnnotationTransformEnd = { [weak self] annotation, page, previousBounds in
                guard let self, let document = self.pdfView.document else { return }
                if annotation.isFormWidget {
                    self.session.registerFormFieldTransform(
                        annotation: annotation,
                        page: page,
                        pageIndex: document.index(for: page),
                        previousBounds: previousBounds
                    )
                } else {
                    self.session.registerAnnotationTransform(
                        annotation: annotation,
                        page: page,
                        pageIndex: document.index(for: page),
                        previousBounds: previousBounds
                    )
                }
            }
            pdfView.onCropTransformEnd = { [weak self] page, previousCropBox, newCropBox in
                self?.session.registerInteractiveCrop(
                    page: page,
                    previousCropBox: previousCropBox,
                    newCropBox: newCropBox
                )
            }
            pdfView.onRedactionRegion = { [weak self] page, bounds in
                self?.session.registerPendingRedaction(page: page, bounds: bounds)
            }
        }

        func startObserving() {
            let center = NotificationCenter.default
            observers = [
                center.addObserver(
                    forName: .PDFViewPageChanged,
                    object: pdfView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reportPage() }
                },
                center.addObserver(
                    forName: .PDFViewScaleChanged,
                    object: pdfView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reportScale() }
                },
                center.addObserver(
                    forName: .PDFViewSelectionChanged,
                    object: pdfView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reportSelection() }
                }
            ]
        }

        func stopObserving() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }

        func perform(_ action: ViewerAction) {
            switch action {
            case .previousPage:
                pdfView.goToPreviousPage(nil)
            case .nextPage:
                pdfView.goToNextPage(nil)
            case .zoomOut:
                pdfView.zoomOut(nil)
            case .zoomIn:
                pdfView.zoomIn(nil)
            case .actualSize:
                pdfView.autoScales = false
                pdfView.scaleFactor = 1
            case .fitPage:
                pdfView.autoScales = true
            case .pageSetup:
                showPageSetup()
            case .printDocument:
                guard pdfView.document?.allowsPrinting == true else { break }
                pdfView.print(with: printInfo, autoRotate: true)
            case .goToPage(let index):
                if let page = pdfView.document?.page(at: index) {
                    pdfView.go(to: page)
                }
            case .showSelection(let index):
                if let selection = session.searchSelection(at: index) {
                    selection.color = selectionColor
                    pdfView.highlightedSelections = [selection]
                    pdfView.setCurrentSelection(selection, animate: true)
                    pdfView.go(to: selection)
                }
            case .clearSelection:
                pdfView.highlightedSelections = nil
                pdfView.setCurrentSelection(nil, animate: false)
            case .setPageLayout(let layout):
                let currentPage = pdfView.currentPage
                pdfView.displayMode = layout.displayMode
                pdfView.displaysAsBook = layout.displaysAsBook
                if let currentPage {
                    pdfView.go(to: currentPage)
                }
                pdfView.autoScales = true
            case .addMarkup(let kind):
                addMarkup(kind)
            case .annotationsChanged(let pageIndices):
                for pageIndex in pageIndices {
                    if let page = pdfView.document?.page(at: pageIndex) {
                        pdfView.annotationsChanged(on: page)
                    }
                }
            case .documentStructureChanged(let pageIndex):
                let document = pdfView.document
                pdfView.document = nil
                pdfView.document = document
                if let page = document?.page(at: pageIndex) {
                    pdfView.go(to: page)
                }
                pdfView.autoScales = true
            }
            reportState()
        }

        private func showPageSetup() {
            let panel = NSPageLayout()
            if let window = pdfView.window {
                panel.beginSheet(using: printInfo, on: window)
            } else {
                panel.runModal(with: printInfo)
            }
        }

        func reportState() {
            reportPage()
            reportScale()
            reportSelection()
        }

        private func addMarkup(_ kind: MarkupKind) {
            guard
                let document = pdfView.document,
                let selection = pdfView.currentSelection
            else { return }

            let entries = selection.selectionsByLine().compactMap { line -> AnnotationEntry? in
                guard let page = line.pages.first else { return nil }
                let bounds = line.bounds(for: page)
                guard !bounds.isEmpty, !bounds.isNull else { return nil }

                let annotation = PDFAnnotation(
                    bounds: bounds.insetBy(dx: -1, dy: 0),
                    forType: kind.annotationSubtype,
                    withProperties: nil
                )
                annotation.color = SPDFVTheme.annotationNSColor(for: kind)
                annotation.userName = NSFullUserName()
                annotation.modificationDate = Date()
                page.addAnnotation(annotation)

                return AnnotationEntry(
                    page: page,
                    annotation: annotation,
                    pageIndex: document.index(for: page)
                )
            }

            guard !entries.isEmpty else { return }
            pdfView.clearSelection()
            session.registerAnnotationTransaction(entries)
        }

        private func handlePageClick(page: PDFPage, point: CGPoint) -> Bool {
            guard let document = pdfView.document else { return false }
            let pageIndex = document.index(for: page)

            switch session.activeAnnotationTool {
            case .select:
                let annotation = page.annotations.reversed().first { annotation in
                    !annotation.isFormWidget
                        && annotation.bounds.insetBy(dx: -4, dy: -4).contains(point)
                }
                session.selectAnnotation(annotation, page: annotation == nil ? nil : page, pageIndex: annotation == nil ? nil : pageIndex)
                pdfView.selectedAnnotation = annotation
                return annotation != nil

            case .note:
                let size = CGSize(width: 26, height: 26)
                let bounds = clampedBounds(
                    centeredAt: point,
                    size: size,
                    within: page.bounds(for: .cropBox)
                )
                let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
                annotation.contents = "New note"
                annotation.color = AnnotationColorPreset.amber.nsColor
                finishAdding(annotation, to: page, pageIndex: pageIndex)
                return true

            case .freeText:
                let bounds = clampedBounds(
                    centeredAt: point,
                    size: CGSize(width: 220, height: 64),
                    within: page.bounds(for: .cropBox)
                )
                let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
                annotation.contents = "Double-click the inspector text to edit"
                annotation.font = NSFont.systemFont(ofSize: 14, weight: .medium)
                annotation.fontColor = AnnotationColorPreset.graphite.nsColor
                annotation.color = NSColor.clear
                let border = PDFBorder()
                border.lineWidth = 1
                annotation.border = border
                finishAdding(annotation, to: page, pageIndex: pageIndex)
                return true

            case .rectangle:
                let bounds = clampedBounds(
                    centeredAt: point,
                    size: CGSize(width: 132, height: 76),
                    within: page.bounds(for: .cropBox)
                )
                let annotation = PDFAnnotation(bounds: bounds, forType: .square, withProperties: nil)
                annotation.color = AnnotationColorPreset.cobalt.nsColor
                annotation.interiorColor = .clear
                let border = PDFBorder()
                border.lineWidth = 2
                annotation.border = border
                finishAdding(annotation, to: page, pageIndex: pageIndex)
                return true

            case .signature:
                guard let draft = session.consumeSignatureDraft() else {
                    session.setAnnotationTool(.select)
                    return false
                }
                addSignature(draft, to: page, pageIndex: pageIndex, centeredAt: point)
                return true

            case .formField:
                guard let draft = session.consumeFormFieldDraft() else {
                    session.setAnnotationTool(.select)
                    return false
                }
                let size: CGSize = switch draft.kind {
                case .checkbox: CGSize(width: 22, height: 22)
                case .choice: CGSize(width: 190, height: 30)
                default: CGSize(width: 220, height: 32)
                }
                let bounds = clampedBounds(centeredAt: point, size: size, within: page.bounds(for: .cropBox))
                do {
                    let annotation = try PDFOperations.addFormField(
                        draft,
                        to: document,
                        pageIndex: pageIndex,
                        bounds: bounds
                    )
                    let entry = AnnotationEntry(page: page, annotation: annotation, pageIndex: pageIndex)
                    session.registerFormFieldTransaction(entry)
                    session.setAnnotationTool(.select)
                    pdfView.selectedAnnotation = nil
                } catch {
                    session.errorMessage = "The field could not be placed: \(error.localizedDescription)"
                    session.setAnnotationTool(.select)
                }
                return true

            case .ink:
                return true
            }
        }

        private func addSignature(
            _ draft: SignatureDraft,
            to page: PDFPage,
            pageIndex: Int,
            centeredAt point: CGPoint
        ) {
            let bounds = clampedBounds(
                centeredAt: point,
                size: CGSize(width: 190, height: 72),
                within: page.bounds(for: .cropBox)
            )
            let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
            annotation.color = NSColor(srgbRed: 0.08, green: 0.16, blue: 0.29, alpha: 0.96)
            annotation.contents = "Visual signature"
            for stroke in draft.strokes where stroke.count > 1 {
                let path = NSBezierPath()
                path.lineWidth = 2.25
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                let first = stroke[0]
                path.move(to: CGPoint(x: first.x * bounds.width, y: first.y * bounds.height))
                for point in stroke.dropFirst() {
                    path.line(to: CGPoint(x: point.x * bounds.width, y: point.y * bounds.height))
                }
                annotation.add(path)
            }
            finishAdding(annotation, to: page, pageIndex: pageIndex)
        }

        private func addInkAnnotation(to page: PDFPage, points: [CGPoint]) {
            guard let document = pdfView.document, points.count > 1 else { return }
            var bounds = CGRect(origin: points[0], size: .zero)
            for point in points.dropFirst() {
                bounds = bounds.union(CGRect(origin: point, size: .zero))
            }
            bounds = bounds.insetBy(dx: -5, dy: -5)
            guard bounds.width > 1, bounds.height > 1 else { return }

            let path = NSBezierPath()
            path.lineWidth = 2.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: CGPoint(x: points[0].x - bounds.minX, y: points[0].y - bounds.minY))
            for point in points.dropFirst() {
                path.line(to: CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY))
            }

            let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
            annotation.color = AnnotationColorPreset.cobalt.nsColor
            annotation.add(path)
            finishAdding(annotation, to: page, pageIndex: document.index(for: page))
        }

        private func finishAdding(_ annotation: PDFAnnotation, to page: PDFPage, pageIndex: Int) {
            annotation.userName = NSFullUserName()
            annotation.modificationDate = Date()
            page.addAnnotation(annotation)
            let entry = AnnotationEntry(page: page, annotation: annotation, pageIndex: pageIndex)
            session.registerAnnotationTransaction([entry])
            session.selectAnnotation(annotation, page: page, pageIndex: pageIndex)
            session.setAnnotationTool(.select)
            pdfView.selectedAnnotation = annotation
        }

        private func clampedBounds(centeredAt point: CGPoint, size: CGSize, within pageBounds: CGRect) -> CGRect {
            let origin = CGPoint(
                x: min(max(pageBounds.minX, point.x - size.width / 2), pageBounds.maxX - size.width),
                y: min(max(pageBounds.minY, point.y - size.height / 2), pageBounds.maxY - size.height)
            )
            return CGRect(origin: origin, size: size)
        }

        private func reportPage() {
            guard
                let document = pdfView.document,
                let page = pdfView.currentPage
            else { return }
            session.updatePage(index: document.index(for: page))
            pdfView.needsDisplay = true
        }

        private func reportScale() {
            session.updateScale(pdfView.scaleFactor)
            pdfView.needsDisplay = true
        }

        private func reportSelection() {
            let text = pdfView.currentSelection?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            session.updateSelection(hasText: text?.isEmpty == false)
        }
    }
}

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
