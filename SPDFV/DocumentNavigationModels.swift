import AppKit
import Foundation
import PDFKit

enum PageLayoutMode: String, CaseIterable, Identifiable {
    case single
    case continuous
    case spread

    var id: Self { self }
    var label: String {
        switch self {
        case .single: "Single"
        case .continuous: "Continuous"
        case .spread: "Spread"
        }
    }
    var displayMode: PDFDisplayMode {
        switch self {
        case .single: .singlePage
        case .continuous: .singlePageContinuous
        case .spread: .twoUpContinuous
        }
    }
    var displaysAsBook: Bool { self == .spread }
}

enum PageParity: String, CaseIterable, Identifiable {
    case odd
    case even

    var id: Self { self }
    var label: String { rawValue.capitalized }
    func matches(pageNumber: Int) -> Bool {
        switch self {
        case .odd: pageNumber.isMultiple(of: 2) == false
        case .even: pageNumber.isMultiple(of: 2)
        }
    }
}

enum PDFInsertionPlacement: String, CaseIterable, Identifiable {
    case beforeSelection
    case afterSelection
    case end

    var id: Self { self }
    var label: String {
        switch self {
        case .beforeSelection: "BEFORE"
        case .afterSelection: "AFTER"
        case .end: "END"
        }
    }
}

struct PageCropInsets: Equatable {
    var top: Double
    var right: Double
    var bottom: Double
    var left: Double

    static let zero = PageCropInsets(top: 0, right: 0, bottom: 0, left: 0)
}

enum PageCropPreset: String, CaseIterable, Identifiable {
    case full
    case trim18
    case trim36

    var id: Self { self }
    var label: String {
        switch self {
        case .full: "FULL"
        case .trim18: "18 PT"
        case .trim36: "36 PT"
        }
    }
    var insets: PageCropInsets {
        switch self {
        case .full: .zero
        case .trim18: PageCropInsets(top: 18, right: 18, bottom: 18, left: 18)
        case .trim36: PageCropInsets(top: 36, right: 36, bottom: 36, left: 36)
        }
    }
}

enum NavigatorMode: String, CaseIterable, Identifiable {
    case pages
    case outline
    case search
    case forms
    case annotations
    case info

    var id: Self { self }
    var label: String {
        switch self {
        case .pages: "Pages"
        case .outline: "Contents"
        case .search: "Find"
        case .forms: "Fields"
        case .annotations: "Marks"
        case .info: "Info"
        }
    }
    var icon: SPDFVIconName {
        switch self {
        case .pages: .pages
        case .outline: .outline
        case .search: .search
        case .forms: .textCursor
        case .annotations: .annotations
        case .info: .info
        }
    }
}

struct SignatureDraft: Equatable {
    let strokes: [[CGPoint]]
}

extension PDFAnnotation {
    var isFormWidget: Bool {
        type?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "Widget"
    }
}

enum OCRPageScope: String, CaseIterable, Identifiable {
    case current
    case selection
    case all

    var id: Self { self }
    var label: String {
        switch self {
        case .current: "CURRENT"
        case .selection: "SELECTION"
        case .all: "ALL"
        }
    }
}

struct PendingRedaction: Identifiable {
    let id = UUID()
    let page: PDFPage
    let bounds: CGRect
}

enum OCRLanguagePreset: String, CaseIterable, Identifiable {
    case automatic
    case english = "en-US"
    case spanish = "es-ES"
    case french = "fr-FR"
    case german = "de-DE"

    var id: Self { self }
    var languages: [String] { self == .automatic ? [] : [rawValue] }
    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .english: "English"
        case .spanish: "Spanish"
        case .french: "French"
        case .german: "German"
        }
    }
}

struct DocumentDetails {
    let fileName: String
    let fileSize: String
    let pageSize: String
    let title: String?
    let author: String?
    let subject: String?
    let encrypted: Bool
    let allowsCopying: Bool
    let allowsPrinting: Bool
}

struct SearchResult: Identifiable {
    let id = UUID()
    let selectionIndex: Int
    let pageIndex: Int
    let excerpt: String
}

struct OutlineEntry: Identifiable {
    let id = UUID()
    let label: String
    let pageIndex: Int?
    let depth: Int
}
