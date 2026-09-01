import AppKit
import Foundation
import PDFKit

struct ViewerCommand: Identifiable, Equatable {
    let id = UUID()
    let action: ViewerAction
}

enum ViewerAction: Equatable {
    case previousPage
    case nextPage
    case zoomOut
    case zoomIn
    case actualSize
    case fitPage
    case pageSetup
    case printDocument
    case goToPage(Int)
    case showSelection(Int)
    case clearSelection
    case setPageLayout(PageLayoutMode)
    case addMarkup(MarkupKind)
    case annotationsChanged([Int])
    case documentStructureChanged(Int)
}

enum MarkupKind: String, CaseIterable, Identifiable {
    case highlight
    case underline
    case strikeOut

    var id: Self { self }

    var label: String {
        switch self {
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .strikeOut: "Strike"
        }
    }

    var icon: SPDFVIconName {
        switch self {
        case .highlight: .highlighter
        case .underline: .underline
        case .strikeOut: .strike
        }
    }

    var annotationSubtype: PDFAnnotationSubtype {
        switch self {
        case .highlight: .highlight
        case .underline: .underline
        case .strikeOut: .strikeOut
        }
    }
}

struct AnnotationEntry {
    let page: PDFPage
    let annotation: PDFAnnotation
    let pageIndex: Int
}

struct EditHistoryEntry {
    let actionName: String
    let operation: AnnotationUndoOperation
}

enum AnnotationUndoOperation {
    case added([AnnotationEntry])
    case removed([AnnotationEntry])
    case modified(AnnotationEntry, AnnotationSnapshot)
    case pagesRotated([PageRotation])
    case pagesRemoved([PageRemoval])
    case pagesInserted(indices: [Int])
    case pagesCropped([PageCrop])
    case pageMoved(from: Int, to: Int)
    case formFieldAdded(AnnotationEntry)
    case formFieldRemoved(AnnotationEntry)
    case formFieldModified(AnnotationEntry, AnnotationSnapshot)
    case formFieldsModified([FormFieldModification])

    var actionName: String {
        switch self {
        case .added(let entries):
            entries.count == 1 ? "Add Annotation" : "Add Annotations"
        case .removed(let entries):
            entries.count == 1 ? "Delete Annotation" : "Delete Annotations"
        case .modified:
            "Edit Annotation"
        case .pagesRotated(let rotations):
            rotations.count == 1 ? "Rotate Page" : "Rotate Pages"
        case .pagesRemoved(let removals):
            removals.count == 1 ? "Delete Page" : "Delete Pages"
        case .pagesInserted(let indices):
            indices.count == 1 ? "Insert Page" : "Insert Pages"
        case .pagesCropped(let crops):
            crops.count == 1 ? "Crop Page" : "Crop Pages"
        case .pageMoved:
            "Move Page"
        case .formFieldAdded:
            "Add Form Field"
        case .formFieldRemoved:
            "Delete Form Field"
        case .formFieldModified:
            "Edit Form Field"
        case .formFieldsModified(let modifications):
            modifications.count == 1 ? "Edit Form Field" : "Edit Form Fields"
        }
    }
}

struct FormFieldModification {
    let entry: AnnotationEntry
    let snapshot: AnnotationSnapshot
}

struct PageRotation {
    let page: PDFPage
    let previousRotation: Int
}

struct PageRemoval {
    let page: PDFPage
    let index: Int
}

struct PageCrop {
    let page: PDFPage
    let previousCropBox: CGRect
}

struct AnnotationSnapshot {
    var bounds: CGRect
    let fieldName: String?
    let contents: String?
    let color: NSColor
    let borderLineWidth: CGFloat?
    let font: NSFont?
    let fontColor: NSColor?
    let widgetStringValue: String?
    let pathLineWidths: [CGFloat]

    init(_ annotation: PDFAnnotation) {
        bounds = annotation.bounds
        fieldName = annotation.fieldName
        contents = annotation.contents
        color = annotation.color
        borderLineWidth = annotation.border?.lineWidth
        font = annotation.font
        fontColor = annotation.fontColor
        widgetStringValue = annotation.widgetStringValue
        pathLineWidths = annotation.paths?.map(\.lineWidth) ?? []
    }

    func apply(to annotation: PDFAnnotation) {
        annotation.bounds = bounds
        annotation.contents = contents
        annotation.color = color
        if let borderLineWidth {
            let border = annotation.border ?? PDFBorder()
            border.lineWidth = borderLineWidth
            annotation.border = border
        }
        annotation.font = font
        annotation.fontColor = fontColor
        annotation.fieldName = fieldName
        if annotation.isFormWidget {
            annotation.widgetStringValue = widgetStringValue
        }
        if let paths = annotation.paths {
            for (index, path) in paths.enumerated() where pathLineWidths.indices.contains(index) {
                path.lineWidth = pathLineWidths[index]
            }
        }
    }
}

enum CanvasAnnotationTool: String, CaseIterable, Identifiable {
    case select
    case note
    case freeText
    case ink
    case rectangle
    case signature
    case formField

    var id: Self { self }

    static let quickTools: [Self] = [.select, .note, .freeText, .ink, .rectangle]

    var label: String {
        switch self {
        case .select: "Select"
        case .note: "Note"
        case .freeText: "Text"
        case .ink: "Draw"
        case .rectangle: "Shape"
        case .signature: "Sign"
        case .formField: "Field"
        }
    }

    var icon: SPDFVIconName {
        switch self {
        case .select: .select
        case .note: .noteAdd
        case .freeText: .text
        case .ink: .draw
        case .rectangle: .region
        case .signature: .signature
        case .formField: .editField
        }
    }

    var help: String {
        switch self {
        case .select: "Select and inspect annotations"
        case .note: "Click a page to place a note"
        case .freeText: "Click a page to place editable text"
        case .ink: "Draw directly on the page"
        case .rectangle: "Click a page to place a rectangle"
        case .signature: "Click a page to place the prepared signature"
        case .formField: "Click a page to place the prepared form field"
        }
    }
}

enum AnnotationColorPreset: String, CaseIterable, Identifiable {
    case amber
    case cobalt
    case coral
    case jade
    case graphite

    var id: Self { self }

    var label: String { rawValue.capitalized }

    var nsColor: NSColor {
        switch self {
        case .amber: NSColor(srgbRed: 1.0, green: 0.78, blue: 0.20, alpha: 0.72)
        case .cobalt: NSColor(srgbRed: 0.18, green: 0.38, blue: 0.85, alpha: 0.92)
        case .coral: NSColor(srgbRed: 0.86, green: 0.25, blue: 0.24, alpha: 0.9)
        case .jade: NSColor(srgbRed: 0.16, green: 0.62, blue: 0.45, alpha: 0.9)
        case .graphite: NSColor(srgbRed: 0.22, green: 0.25, blue: 0.30, alpha: 0.9)
        }
    }
}

struct AnnotationSelection: Identifiable {
    let annotation: PDFAnnotation
    let page: PDFPage
    let pageIndex: Int

    var id: ObjectIdentifier { ObjectIdentifier(annotation) }
    var entry: AnnotationEntry {
        AnnotationEntry(page: page, annotation: annotation, pageIndex: pageIndex)
    }
    var typeLabel: String {
        (annotation.type ?? "Annotation")
            .replacingOccurrences(of: "StrikeOut", with: "Strikeout")
            .replacingOccurrences(of: "FreeText", with: "Text")
    }
    var author: String { annotation.userName?.isEmpty == false ? annotation.userName! : "Unknown" }
    var contents: String { annotation.contents ?? "" }
    var opacity: Double { Double(annotation.color.alphaComponent) }
    var strokeWidth: Double {
        Double(annotation.paths?.first?.lineWidth ?? annotation.border?.lineWidth ?? 1)
    }
    var fontSize: Double { Double(annotation.font?.pointSize ?? 14) }
    var hasAdjustableFont: Bool { annotation.font != nil }
    var hasAdjustableStroke: Bool {
        annotation.border != nil || annotation.paths?.isEmpty == false
    }
}

struct FormFieldSelection: Identifiable {
    let annotation: PDFAnnotation
    let page: PDFPage
    let pageIndex: Int

    var id: ObjectIdentifier { ObjectIdentifier(annotation) }
    var entry: AnnotationEntry {
        AnnotationEntry(page: page, annotation: annotation, pageIndex: pageIndex)
    }
}

struct AnnotationRecord: Identifiable {
    let annotation: PDFAnnotation
    let page: PDFPage
    let pageIndex: Int

    var id: ObjectIdentifier { ObjectIdentifier(annotation) }
    var typeLabel: String {
        (annotation.type ?? "Annotation")
            .replacingOccurrences(of: "StrikeOut", with: "Strikeout")
            .replacingOccurrences(of: "FreeText", with: "Text")
    }
    var preview: String {
        let value = annotation.contents?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : "No attached text"
    }
    var color: NSColor { annotation.color }
    var category: AnnotationCategory {
        let normalized = (annotation.type ?? "").lowercased()
        if normalized.contains("highlight") || normalized.contains("underline") || normalized.contains("strike") {
            return .markup
        }
        if normalized.contains("ink") {
            return .drawing
        }
        if normalized.contains("square") || normalized.contains("circle") || normalized.contains("line") {
            return .shape
        }
        return .note
    }
}

enum AnnotationCategory: String, CaseIterable, Identifiable {
    case all
    case markup
    case note
    case drawing
    case shape

    var id: Self { self }
    var label: String { rawValue.capitalized }
}
