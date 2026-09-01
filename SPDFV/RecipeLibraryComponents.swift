import SPDFVCore
import SwiftUI

enum RecipeLibraryFilter: String, CaseIterable, Identifiable {
    case all, favorites, personal, presets

    var id: Self { self }
    var label: String {
        switch self {
        case .all: "ALL"
        case .favorites: "STARRED"
        case .personal: "MINE"
        case .presets: "PRESETS"
        }
    }
    var icon: SPDFVIconName {
        switch self {
        case .all: .archive
        case .favorites: .favoriteFilled
        case .personal: .select
        case .presets: .check
        }
    }
}

struct RecipeCabinetRow: View {
    let index: Int
    let entry: PDFRecipeLibraryEntry
    let isSelected: Bool
    let isLoaded: Bool
    let select: () -> Void
    let favorite: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Button(action: select) {
                HStack(spacing: 8) {
                    Text(String(format: "%02d", index))
                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white : SPDFVTheme.navigatorMuted)
                        .frame(width: 25, height: 25)
                        .background(isSelected ? SPDFVTheme.cobalt : SPDFVTheme.navigatorInset)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(entry.recipe.name)
                                .font(.system(size: 9.5, weight: .semibold))
                                .lineLimit(1)
                            if isLoaded {
                                Circle().fill(Color.green).frame(width: 5, height: 5)
                            }
                        }
                        Text("\(entry.kind == .preset ? "PRESET" : "R\(entry.revision)") · \(entry.recipe.steps.count) STEPS")
                            .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                            .foregroundStyle(SPDFVTheme.navigatorFaint)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(entry.recipe.name)")

            Button(action: favorite) {
                SPDFVIcon(entry.isFavorite ? .favoriteFilled : .favorite, size: 9)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(entry.isFavorite ? Color.orange : SPDFVTheme.navigatorFaint)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isFavorite ? "Remove \(entry.recipe.name) from favorites" : "Add \(entry.recipe.name) to favorites")
        }
        .foregroundStyle(SPDFVTheme.navigatorText)
        .padding(.horizontal, 7)
        .frame(height: 45)
        .background(isSelected ? SPDFVTheme.controlPressed : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle().fill(isSelected ? SPDFVTheme.cobalt : Color.clear).frame(width: 2)
        }
    }
}

struct RecipeComposerStepRow: View {
    let index: Int
    let step: PDFRecipeStep
    let isSelected: Bool
    let canDelete: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let select: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 8) {
                    SPDFVIcon(.drag, size: 8)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(SPDFVTheme.navigatorFaint)
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white : SPDFVTheme.navigatorMuted)
                        .frame(width: 25, height: 25)
                        .background(isSelected ? SPDFVTheme.cobalt : SPDFVTheme.navigatorInset)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.operation.uppercased())
                            .font(.system(size: 7.5, weight: .black, design: .monospaced))
                            .foregroundStyle(isSelected ? SPDFVTheme.paleCobalt : SPDFVTheme.navigatorMuted)
                        Text(step.summary)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(SPDFVTheme.navigatorText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSelected && canDelete {
                Button(action: moveUp) {
                    SPDFVIcon(.up, size: 7)
                        .font(.system(size: 7, weight: .bold))
                        .frame(width: 16, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .disabled(!canMoveUp)

                Button(action: moveDown) {
                    SPDFVIcon(.down, size: 7)
                        .font(.system(size: 7, weight: .bold))
                        .frame(width: 16, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .disabled(!canMoveDown)

                Button(action: remove) {
                    SPDFVIcon(.delete, size: 9)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SPDFVTheme.redaction)
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 45)
        .background(isSelected ? SPDFVTheme.controlPressed : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle().fill(isSelected ? SPDFVTheme.cobalt : Color.clear).frame(width: 2)
        }
    }
}

struct RecipeStepDropDelegate: DropDelegate {
    let destination: Int
    @Binding var draggedStep: Int?
    @Binding var selectedStep: Int
    let move: (Int, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let source = draggedStep, source != destination else { return }
        move(source, destination)
        draggedStep = destination
        selectedStep = destination
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedStep = nil
        return true
    }
}

enum RecipeOperationKind: String, CaseIterable, Identifiable {
    case assertPageCount, assertText, assertFields, assertFormGate, assertSafeShare, assertCompare, assertDoctor
    case renameField, fillForm, importFormData, rotate, crop, extract, duplicatePages, deletePages, ocr, ifParameter

    var id: Self { self }
    var isAssertion: Bool { rawValue.hasPrefix("assert") }

    var title: String {
        switch self {
        case .assertPageCount: "PAGE COUNT"
        case .assertText: "TEXT CHECK"
        case .assertFields: "FIELD CHECK"
        case .assertFormGate: "FORM GATE"
        case .assertSafeShare: "SAFE SHARE"
        case .assertCompare: "COMPARE"
        case .assertDoctor: "DOCTOR"
        case .renameField: "RENAME FIELD"
        case .fillForm: "FILL FORM"
        case .importFormData: "IMPORT FORM DATA"
        case .rotate: "ROTATE"
        case .crop: "CROP"
        case .extract: "EXTRACT"
        case .duplicatePages: "DUPLICATE"
        case .deletePages: "DELETE"
        case .ocr: "OCR"
        case .ifParameter: "CONDITIONAL"
        }
    }

    var icon: SPDFVIconName {
        switch self {
        case .assertPageCount: .pageCount
        case .assertText: .search
        case .assertFields: .list
        case .assertFormGate: .check
        case .assertSafeShare: .secureCopy
        case .assertCompare: .copy
        case .assertDoctor: .warning
        case .renameField: .textCursor
        case .fillForm: .editField
        case .importFormData: .documentAdd
        case .rotate: .rotateRight
        case .crop: .crop
        case .extract: .extract
        case .duplicatePages: .duplicate
        case .deletePages: .delete
        case .ocr: .scanText
        case .ifParameter: .route
        }
    }

    var defaultStep: PDFRecipeStep {
        switch self {
        case .assertPageCount: .assertPageCount(minimum: 1, maximum: nil)
        case .assertText: .assertText(contains: ["Required text"], excludes: [])
        case .assertFields: .assertFields(names: ["field.name"])
        case .assertFormGate: .assertFormGate(maximum: .pass)
        case .assertSafeShare: .assertSafeShare(maximum: .warning)
        case .assertCompare: .assertCompare(reference: "baseline", maximumChangedPages: 0, options: PDFComparisonOptions())
        case .assertDoctor: .assertDoctor(maximum: .attention)
        case .renameField: .renameField(from: "old.name", to: "new.name")
        case .fillForm: .fillForm(values: ["field.name": "Value"])
        case .importFormData: .importFormData(source: "values")
        case .rotate: .rotate(pages: "all", degrees: 90)
        case .crop: .crop(pages: "all", insets: .zero)
        case .extract: .extract(pages: "all")
        case .duplicatePages: .duplicatePages(pages: "1")
        case .deletePages: .deletePages(pages: "1")
        case .ocr: .ocr(pages: "all", configuration: PDFOCRConfiguration())
        case .ifParameter: .ifParameter(name: "mode", equals: "production", steps: [.assertPageCount(minimum: 1, maximum: nil)])
        }
    }
}
