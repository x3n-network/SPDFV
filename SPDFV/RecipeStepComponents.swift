import SPDFVCore
import SwiftUI

private struct RecipeStepDraft: Equatable {
    var primary = ""
    var secondary = ""
    var tertiary = ""
    var quaternary = ""
    var pages = "all"
    var degree = "90"
    var gate = PDFFormGateLevel.pass.rawValue

    init(_ step: PDFRecipeStep) {
        switch step {
        case .renameField(let from, let to):
            primary = from; secondary = to
        case .fillForm(let values):
            primary = values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        case .rotate(let selection, let degrees):
            pages = selection; degree = String(degrees)
        case .crop(let selection, let insets):
            pages = selection
            primary = Self.number(insets.top); secondary = Self.number(insets.right)
            tertiary = Self.number(insets.bottom); quaternary = Self.number(insets.left)
        case .extract(let selection):
            pages = selection
        case .assertPageCount(let minimum, let maximum):
            primary = minimum.map(String.init) ?? ""; secondary = maximum.map(String.init) ?? ""
        case .assertText(let contains, let excludes):
            primary = contains.joined(separator: ", "); secondary = excludes.joined(separator: ", ")
        case .assertFields(let names):
            primary = names.joined(separator: ", ")
        case .assertFormGate(let maximum):
            gate = maximum.rawValue
        }
    }

    func resolved(for original: PDFRecipeStep) -> PDFRecipeStep? {
        switch original {
        case .renameField:
            guard !trim(primary).isEmpty, !trim(secondary).isEmpty else { return nil }
            return .renameField(from: trim(primary), to: trim(secondary))
        case .fillForm:
            guard let values = formValues, !values.isEmpty else { return nil }
            return .fillForm(values: values)
        case .rotate:
            guard !trim(pages).isEmpty, let degrees = Int(degree) else { return nil }
            return .rotate(pages: trim(pages), degrees: degrees)
        case .crop:
            guard !trim(pages).isEmpty,
                  let top = Double(primary), let right = Double(secondary),
                  let bottom = Double(tertiary), let left = Double(quaternary),
                  [top, right, bottom, left].min() ?? -1 >= 0 else { return nil }
            return .crop(pages: trim(pages), insets: PDFEdgeInsets(top: top, right: right, bottom: bottom, left: left))
        case .extract:
            guard !trim(pages).isEmpty else { return nil }
            return .extract(pages: trim(pages))
        case .assertPageCount:
            let minimumText = trim(primary), maximumText = trim(secondary)
            guard minimumText.isEmpty || Int(minimumText) != nil,
                  maximumText.isEmpty || Int(maximumText) != nil else { return nil }
            let minimum = minimumText.isEmpty ? nil : Int(minimumText)
            let maximum = maximumText.isEmpty ? nil : Int(maximumText)
            guard minimum != nil || maximum != nil,
                  minimum.map({ $0 >= 0 }) ?? true,
                  maximum.map({ $0 >= 0 }) ?? true,
                  minimum == nil || maximum == nil || minimum! <= maximum! else { return nil }
            return .assertPageCount(minimum: minimum, maximum: maximum)
        case .assertText:
            let contains = list(primary), excludes = list(secondary)
            guard !contains.isEmpty || !excludes.isEmpty else { return nil }
            return .assertText(contains: contains, excludes: excludes)
        case .assertFields:
            let names = list(primary)
            guard !names.isEmpty else { return nil }
            return .assertFields(names: names)
        case .assertFormGate:
            guard let level = PDFFormGateLevel(rawValue: gate) else { return nil }
            return .assertFormGate(maximum: level)
        }
    }

    func validationMessage(for original: PDFRecipeStep) -> String {
        guard resolved(for: original) == nil else { return "Parameters ready" }
        return switch original {
        case .renameField: "Both field names are required"
        case .fillForm: "Use one field=value pair per line"
        case .rotate: "Pages and an integer angle are required"
        case .crop: "Pages and four non-negative inset values are required"
        case .extract: "Enter all, a page, or a page range"
        case .assertPageCount: "Set a valid minimum, maximum, or both"
        case .assertText: "Enter required or forbidden text"
        case .assertFields: "Enter at least one field name"
        case .assertFormGate: "Choose the highest allowed gate level"
        }
    }

    private var formValues: [String: String]? {
        var values: [String: String] = [:]
        for line in primary.split(whereSeparator: \.isNewline) {
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, !trim(pair[0]).isEmpty else { return nil }
            values[trim(pair[0])] = trim(pair[1])
        }
        return values
    }

    private func list(_ value: String) -> [String] {
        value.split(whereSeparator: { $0 == "," || $0.isNewline }).map { trim(String($0)) }.filter { !$0.isEmpty }
    }

    private func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

struct RecipeStepEditor: View {
    let index: Int
    let step: PDFRecipeStep
    let update: (PDFRecipeStep) -> Void
    let validationChanged: (String?) -> Void
    @State private var draft: RecipeStepDraft

    init(
        index: Int,
        step: PDFRecipeStep,
        update: @escaping (PDFRecipeStep) -> Void,
        validationChanged: @escaping (String?) -> Void
    ) {
        self.index = index
        self.step = step
        self.update = update
        self.validationChanged = validationChanged
        _draft = State(initialValue: RecipeStepDraft(step))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CALIBRATION \(String(format: "%02d", index + 1))")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                    Text(step.operation)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(SPDFVTheme.navigatorText)
                }
                Spacer()
                SPDFVIcon(RecipeOperationKind(rawValue: step.operation)?.icon ?? .controls, size: 18)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(SPDFVTheme.paleCobalt)
            }
            .padding(14)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            ScrollView {
                editorFields
                    .padding(14)
            }

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
            HStack(spacing: 8) {
                Circle()
                    .fill(draft.resolved(for: step) == nil ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                Text(draft.validationMessage(for: step).uppercased())
                    .font(.system(size: 7.5, weight: .black, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(SPDFVTheme.navigatorInset)
        }
        .onChange(of: draft) { _, value in
            if let resolved = value.resolved(for: step) {
                validationChanged(nil)
                update(resolved)
            } else {
                validationChanged(value.validationMessage(for: step))
            }
        }
        .onAppear {
            validationChanged(draft.resolved(for: step) == nil ? draft.validationMessage(for: step) : nil)
        }
    }

    @ViewBuilder private var editorFields: some View {
        switch step {
        case .renameField:
            RecipeField(label: "SOURCE FIELD", hint: "Exact existing field name") {
                recipeTextField("full_name", text: $draft.primary)
            }
            RecipeArrow()
            RecipeField(label: "DESTINATION FIELD", hint: "New canonical field name") {
                recipeTextField("review.owner", text: $draft.secondary)
            }
        case .fillForm:
            RecipeField(label: "FIELD VALUES", hint: "One field=value pair per line") {
                TextEditor(text: $draft.primary)
                    .font(.system(size: 10, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 116)
                    .background(SPDFVTheme.navigatorInset)
                    .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
            }
        case .rotate:
            pagesField
            RecipeField(label: "TURN", hint: "Clockwise degrees") {
                Picker("", selection: $draft.degree) {
                    ForEach(["0", "90", "180", "270"], id: \.self) { Text("\($0)°").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        case .crop:
            pagesField
            Text("INSETS · POINTS")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
            HStack(spacing: 7) {
                insetField("TOP", text: $draft.primary)
                insetField("RIGHT", text: $draft.secondary)
                insetField("BOTTOM", text: $draft.tertiary)
                insetField("LEFT", text: $draft.quaternary)
            }
        case .extract:
            pagesField
            RecipeNote("Only selected pages continue to later steps.")
        case .assertPageCount:
            HStack(spacing: 9) {
                RecipeField(label: "MINIMUM", hint: "Optional") { recipeTextField("1", text: $draft.primary) }
                RecipeField(label: "MAXIMUM", hint: "Optional") { recipeTextField("12", text: $draft.secondary) }
            }
        case .assertText:
            RecipeField(label: "MUST CONTAIN", hint: "Comma-separated phrases") {
                recipeTextField("Invoice, Approved", text: $draft.primary)
            }
            RecipeField(label: "MUST NOT CONTAIN", hint: "Comma-separated phrases") {
                recipeTextField("Draft, Confidential", text: $draft.secondary)
            }
        case .assertFields:
            RecipeField(label: "REQUIRED FIELDS", hint: "Comma-separated exact names") {
                recipeTextField("full_name, approved", text: $draft.primary)
            }
        case .assertFormGate:
            RecipeField(label: "HIGHEST ALLOWED LEVEL", hint: "The run stops above this level") {
                Picker("", selection: $draft.gate) {
                    ForEach(PDFFormGateLevel.allCases, id: \.rawValue) { Text($0.rawValue.uppercased()).tag($0.rawValue) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }

    private var pagesField: some View {
        RecipeField(label: "PAGES", hint: "all · 1,3,5 · 2-6") {
            recipeTextField("all", text: $draft.pages)
        }
    }

    private func insetField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 6.5, weight: .black, design: .monospaced)).foregroundStyle(SPDFVTheme.navigatorFaint)
            recipeTextField("0", text: text)
        }
    }

    private func recipeTextField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(SPDFVTheme.navigatorText)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(SPDFVTheme.navigatorInset)
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
    }
}

private struct RecipeField<Content: View>: View {
    let label: String
    let hint: String
    let content: Content

    init(label: String, hint: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                Spacer()
                Text(hint)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorFaint)
            }
            content
        }
        .padding(.bottom, 12)
    }
}

private struct RecipeArrow: View {
    var body: some View {
        HStack(spacing: 5) {
            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
            SPDFVIcon(.down, size: 8).foregroundStyle(SPDFVTheme.paleCobalt)
            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
        }
        .padding(.bottom, 12)
    }
}

private struct RecipeNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 9.5))
            .foregroundStyle(SPDFVTheme.navigatorMuted)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SPDFVTheme.navigatorInset)
            .overlay(alignment: .leading) { Rectangle().fill(SPDFVTheme.cobalt).frame(width: 2) }
    }
}

struct RecipeStepRow: View {
    let index: Int
    let step: PDFRecipeStep
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
                    .background(SPDFVTheme.cobalt)
                if !isLast {
                    Rectangle().fill(SPDFVTheme.cobalt.opacity(0.45)).frame(width: 1, height: 24)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(step.operation.uppercased())
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(SPDFVTheme.paleCobalt)
                Text(step.summary)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(SPDFVTheme.navigatorText)
                    .lineLimit(2)
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .frame(minHeight: isLast ? 34 : 48, alignment: .top)
    }
}

struct RecipePanelButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(prominent ? Color.white : SPDFVTheme.navigatorText)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(prominent ? SPDFVTheme.cobalt.opacity(configuration.isPressed ? 0.72 : 1) : Color.clear)
            .overlay { Rectangle().stroke(prominent ? SPDFVTheme.cobalt : SPDFVTheme.divider, lineWidth: 1) }
            .opacity(isEnabled ? 1 : 0.48)
    }
}
