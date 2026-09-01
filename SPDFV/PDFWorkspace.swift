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
        pdfView.setAccessibilityIdentifier("document.pdf")
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
