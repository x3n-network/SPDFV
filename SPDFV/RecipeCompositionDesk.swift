import SwiftUI
import UniformTypeIdentifiers
import SPDFVCore

struct RecipeCompositionDesk: View {
    @ObservedObject var session: DocumentSession
    let recipe: PDFRecipe
    @Binding var selectedStep: Int
    @Binding var isChoosingOperation: Bool
    @Binding var draggedStep: Int?
    @Binding var stepDraftError: String?
    @Binding var isComposing: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                stepList
                    .frame(width: 278, height: 360)

                Rectangle().fill(SPDFVTheme.divider).frame(width: 1, height: 360)

                editor
                    .frame(width: 381, height: 360)
            }

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
            compositionStatus
        }
    }

    private var stepList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("STEPS")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                Spacer()
                Text("DRAG TO REORDER")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorFaint)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            if recipe.steps.isEmpty {
                emptySteps
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { offset, step in
                            stepRow(offset: offset, step: step)
                        }
                    }
                    .padding(8)
                }
            }

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
            addOperationButton
        }
    }

    private var emptySteps: some View {
        VStack(spacing: 8) {
            SPDFVIcon(.noteAdd)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(SPDFVTheme.paleCobalt)
            Text("No steps yet")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            Text("Add the first operation to begin.")
                .font(.system(size: 9))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(SPDFVTheme.navigatorText)
    }

    private func stepRow(offset: Int, step: PDFRecipeStep) -> some View {
        RecipeComposerStepRow(
            index: offset,
            step: step,
            isSelected: selectedStep == offset,
            canDelete: true,
            canMoveUp: offset > 0,
            canMoveDown: offset < recipe.steps.count - 1,
            select: {
                selectedStep = offset
                isChoosingOperation = false
                stepDraftError = nil
            },
            moveUp: {
                session.moveRecipeStep(from: offset, to: offset - 1)
                selectedStep = offset - 1
            },
            moveDown: {
                session.moveRecipeStep(from: offset, to: offset + 1)
                selectedStep = offset + 1
            },
            remove: { session.removeRecipeStep(at: offset) }
        )
        .onDrag {
            draggedStep = offset
            return NSItemProvider(object: String(offset) as NSString)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: RecipeStepDropDelegate(
                destination: offset,
                draggedStep: $draggedStep,
                selectedStep: $selectedStep,
                move: session.moveRecipeStep
            )
        )
    }

    private var addOperationButton: some View {
        Button {
            isChoosingOperation.toggle()
        } label: {
            HStack {
                SPDFVIcon(isChoosingOperation ? .close : .add)
                Text(isChoosingOperation ? "CANCEL PLATE" : "ADD OPERATION")
                Spacer()
                Text("\(recipe.steps.count) / 100")
                    .foregroundStyle(SPDFVTheme.navigatorFaint)
            }
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundStyle(SPDFVTheme.paleCobalt)
            .padding(.horizontal, 12)
            .frame(height: 38)
        }
        .buttonStyle(.plain)
        .disabled(recipe.steps.count >= 100)
    }

    @ViewBuilder
    private var editor: some View {
        if isChoosingOperation {
            operationPalette
        } else if recipe.steps.indices.contains(selectedStep) {
            RecipeStepEditor(
                index: selectedStep,
                step: recipe.steps[selectedStep],
                update: { session.updateRecipeStep(at: selectedStep, to: $0) },
                validationChanged: { stepDraftError = $0 }
            )
            .id("\(selectedStep)-\(recipe.steps[selectedStep].operation)")
        } else {
            Text("Choose an operation from the plate catalog.")
                .font(.system(size: 10))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var operationPalette: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PLATE CATALOG")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(0.9)
                Text("Assertions stop a run. Actions change the PDF.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 2), spacing: 7) {
                ForEach(RecipeOperationKind.allCases) { operation in
                    Button {
                        let insertion = recipe.steps.isEmpty ? nil : selectedStep
                        session.addRecipeStep(operation.defaultStep, after: insertion)
                        selectedStep = recipe.steps.isEmpty ? 0 : min(selectedStep + 1, recipe.steps.count)
                        isChoosingOperation = false
                        stepDraftError = nil
                    } label: {
                        HStack(spacing: 8) {
                            SPDFVIcon(operation.icon, size: 12)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(operation.isAssertion ? Color.orange : SPDFVTheme.paleCobalt)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(operation.title)
                                    .font(.system(size: 8, weight: .black, design: .monospaced))
                                Text(operation.isAssertion ? "ASSERTION" : "ACTION")
                                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(SPDFVTheme.navigatorFaint)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(SPDFVTheme.navigatorText)
                        .padding(.horizontal, 9)
                        .frame(height: 44)
                        .background(SPDFVTheme.navigatorInset)
                        .overlay { Rectangle().stroke(SPDFVTheme.divider.opacity(0.75), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .foregroundStyle(SPDFVTheme.navigatorText)
    }

    private var compositionStatus: some View {
        let error = stepDraftError ?? recipeValidationError
        return HStack(spacing: 9) {
            Circle()
                .fill(error == nil ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(error == nil ? "COMPOSITION VALID" : "COMPOSITION NEEDS INPUT")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.6)
                Text(error ?? "Ready to save, share, validate, or run")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                    .lineLimit(1)
            }
            Spacer()
            Button("PROOF IT") { isComposing = false }
                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                .buttonStyle(.plain)
                .foregroundStyle(SPDFVTheme.paleCobalt)
                .disabled(error != nil)
        }
        .foregroundStyle(SPDFVTheme.navigatorText)
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(SPDFVTheme.navigatorInset)
    }

    private var recipeValidationError: String? {
        do {
            try PDFRecipeRunner.validate(recipe)
            return nil
        } catch {
            return (error as? PDFOperationError)?.description ?? error.localizedDescription
        }
    }
}
