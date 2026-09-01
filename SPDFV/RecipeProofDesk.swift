import SwiftUI
import SPDFVCore

struct RecipeProofDesk: View {
    @ObservedObject var session: DocumentSession
    let recipe: PDFRecipe

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { offset, step in
                        RecipeStepRow(index: offset + 1, step: step, isLast: offset == recipe.steps.count - 1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(height: min(CGFloat(recipe.steps.count * 48 + 16), 230))

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
            verificationPlate
            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            HStack(spacing: 8) {
                Button(session.isRunningRecipe ? "CHECKING…" : "DRY RUN") { session.validateLoadedRecipe() }
                    .buttonStyle(RecipePanelButtonStyle(prominent: false))
                    .disabled(session.isRunningRecipe)
                    .accessibilityIdentifier("recipe.dry-run")
                Button(session.isRunningRecipe ? "PROCESSING…" : "EXPORT PDF") { session.exportLoadedRecipe() }
                    .buttonStyle(RecipePanelButtonStyle(prominent: true))
                    .disabled(session.isRunningRecipe)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Button(session.isRunningRecipe ? "FEEDING FOLDER…" : "PROCESS FOLDER") {
                session.processRecipeFolder()
            }
            .buttonStyle(RecipePanelButtonStyle(prominent: false))
            .disabled(session.isRunningRecipe)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
    }

    private var verificationPlate: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(verificationColor)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(verificationTitle)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(SPDFVTheme.navigatorText)
                Text(verificationDetail)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }
            Spacer()
            if let batch = session.batchRecipeReport {
                Text("\(batch.passedCount) / \(batch.inputCount)")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.paleCobalt)
            } else if let report = session.recipeReport {
                Text("\(report.inputPageCount) → \(report.outputPageCount) PGS")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.paleCobalt)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(SPDFVTheme.navigatorInset)
    }

    private var verificationTitle: String {
        if let batch = session.batchRecipeReport {
            return batch.failedCount == 0 ? "BATCH VERIFIED" : "BATCH NEEDS REVIEW"
        }
        if session.lastRecipeOutputURL != nil { return "OUTPUT VERIFIED" }
        if session.recipeReport != nil { return "DRY RUN PASSED" }
        return "AWAITING PROOF"
    }

    private var verificationDetail: String {
        if let batch = session.batchRecipeReport {
            let directory = session.lastBatchOutputDirectory?.lastPathComponent ?? "OUTPUT FOLDER"
            return "\(batch.passedCount) passed · \(batch.failedCount) stopped · \(directory)"
        }
        if let url = session.lastRecipeOutputURL { return url.lastPathComponent }
        if let report = session.recipeReport {
            return "\(report.steps.count) steps · \(report.formGate == nil ? "PDF CHECK" : "FORM GATE PASS")"
        }
        return "Run without writing to validate every step"
    }

    private var verificationColor: Color {
        if let batch = session.batchRecipeReport {
            return batch.failedCount == 0 ? Color.green : Color.orange
        }
        return session.recipeReport == nil ? SPDFVTheme.navigatorFaint : Color.green
    }
}
