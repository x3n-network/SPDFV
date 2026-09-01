import AppKit
import PDFKit
import SPDFVCore
import SwiftUI

struct FormsNavigator: View {
    @ObservedObject var session: DocumentSession
    @State private var signatureStrokes: [[CGPoint]] = []
    @State private var workbench: FieldWorkbenchMode = .fill
    @State private var fieldKind: PDFFormFieldKind = .text
    @State private var fieldName = ""
    @State private var fieldValue = ""
    @State private var fieldChoices = "Draft,Review,Approved"
    @State private var pendingDeleteField: PDFFormFieldReport?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(FieldWorkbenchMode.allCases) { mode in
                    Button {
                        workbench = mode
                    } label: {
                        Text(mode.rawValue.uppercased())
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .tracking(0.9)
                            .foregroundStyle(workbench == mode ? Color.white : SPDFVTheme.navigatorMuted)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(workbench == mode ? SPDFVTheme.cobalt : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("forms.workbench.\(mode.rawValue)")
                    .accessibilityValue(workbench == mode ? "Selected" : "Not selected")
                }
            }
            .background(SPDFVTheme.navigatorInset)
            .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider).frame(height: 1) }

            if workbench == .fill, let gate = session.formGate {
                FormGatePlate(gate: gate)
            } else if workbench == .build {
                FieldDraftingPlate(
                    session: session,
                    kind: $fieldKind,
                    name: $fieldName,
                    value: $fieldValue,
                    choices: $fieldChoices
                )
            } else if workbench == .sign {
                signaturePlate
            } else if workbench == .data {
                FormDataStudioPlate(session: session)
            }

            HStack {
                Text("FIELDS")
                Spacer()
                Text("\(session.formFields.count) WIDGET\(session.formFields.count == 1 ? "" : "S")")
            }
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(SPDFVTheme.navigatorFaint)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider).frame(height: 1) }

            if session.formFields.isEmpty {
                NavigatorEmptyState(
                    icon: .editField,
                    title: "No form fields",
                    detail: "Choose Build to draft a field, or Sign to place a visual signature."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.formFields) { field in
                            FormFieldRow(
                                field: field,
                                session: session,
                                isSelected: session.selectedFormField?.annotation.fieldName == field.name
                                    && session.selectedFormField?.pageIndex == field.page - 1
                                    && PDFRectReport(session.selectedFormField?.annotation.bounds ?? .zero) == field.bounds,
                                onDelete: { pendingDeleteField = field }
                            )
                            Rectangle().fill(SPDFVTheme.divider).frame(height: 1).padding(.leading, 13)
                        }
                    }
                }
            }
        }
        .onAppear {
            if fieldName.isEmpty { fieldName = "field_\(session.formFields.count + 1)" }
        }
        .alert("Remove form field?", isPresented: deleteFieldIsPresented) {
            Button("Remove Field", role: .destructive) {
                guard let field = pendingDeleteField else { return }
                session.showFormField(field)
                session.deleteSelectedFormField()
                pendingDeleteField = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteField = nil }
        } message: {
            Text("The interactive field “\(pendingDeleteField?.name ?? "")” will be removed. You can undo this edit until the document is saved.")
        }
    }

    private var deleteFieldIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteField != nil },
            set: { if !$0 { pendingDeleteField = nil } }
        )
    }

    private var signaturePlate: some View {
        VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("SIGNATURE TRAY")
                    Spacer()
                    Text("VISUAL MARK")
                }
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(SPDFVTheme.navigatorFaint)

                SignaturePad(strokes: $signatureStrokes)
                    .frame(height: 78)

                HStack(spacing: 7) {
                    Button("CLEAR") { signatureStrokes = [] }
                        .buttonStyle(SidebarButtonStyle(prominent: false))
                        .disabled(signatureStrokes.isEmpty)
                    Button("PLACE ON PAGE") { prepareSignature() }
                        .buttonStyle(SidebarButtonStyle(prominent: true))
                        .disabled(signatureStrokes.isEmpty)
                }

                Text(session.activeAnnotationTool == .signature
                     ? "Placement armed - click the page"
                     : "Draw once, then place and resize like any mark")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(session.activeAnnotationTool == .signature ? SPDFVTheme.paleCobalt : SPDFVTheme.navigatorMuted)
        }
        .padding(12)
        .background(SPDFVTheme.navigatorInset)
        .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider).frame(height: 1) }
    }

    private func prepareSignature() {
        let allPoints = signatureStrokes.flatMap { $0 }
        guard
            let minX = allPoints.map(\.x).min(), let maxX = allPoints.map(\.x).max(),
            let minY = allPoints.map(\.y).min(), let maxY = allPoints.map(\.y).max(),
            maxX > minX, maxY > minY
        else { return }
        let normalized = signatureStrokes.map { stroke in
            stroke.map {
                CGPoint(
                    x: min(1, max(0, ($0.x - minX) / (maxX - minX))),
                    y: min(1, max(0, 1 - ($0.y - minY) / (maxY - minY)))
                )
            }
        }
        session.prepareSignature(SignatureDraft(strokes: normalized))
    }
}

private struct FormGatePlate: View {
    let gate: PDFFormGateReport

    private var gateColor: Color {
        switch gate.level {
        case .pass: Color(nsColor: AnnotationColorPreset.jade.nsColor)
        case .warning: Color(nsColor: AnnotationColorPreset.amber.nsColor)
        case .stop: SPDFVTheme.redaction
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle().fill(gateColor).frame(width: 8, height: 8)
                Text("FORM GATE / \(gate.level.rawValue.uppercased())")
                Spacer()
                Text("\(gate.canonicalFieldCount) TREE · \(gate.widgetCount) PAGE")
            }
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(SPDFVTheme.navigatorText)

            if gate.issues.isEmpty {
                Text(gate.widgetCount == 0
                     ? "No interactive fields to inspect."
                     : "Field tree, page widgets, values, and appearances agree.")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(gate.issues.prefix(2)) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title.uppercased())
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(issue.level == .stop ? SPDFVTheme.redaction : gateColor)
                        Text(issue.fields.prefix(3).joined(separator: ", "))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(SPDFVTheme.navigatorMuted)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(12)
        .background(SPDFVTheme.navigatorInset)
        .overlay(alignment: .leading) { Rectangle().fill(gateColor).frame(width: 3) }
        .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider).frame(height: 1) }
    }
}

private enum FieldWorkbenchMode: String, CaseIterable, Identifiable {
    case fill
    case build
    case sign
    case data
    var id: Self { self }
}

private struct FormDataStudioPlate: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("FORM DATA STUDIO")
                Spacer()
                Text("JSON V1")
            }
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .tracking(0.9)
            .foregroundStyle(SPDFVTheme.navigatorFaint)

            if let validation = session.formDataValidation {
                Text(session.formDataFileName ?? "Imported data")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorText)
                    .lineLimit(1)
                Text("\(validation.matchedFields) MATCHED · \(validation.updatedFields.count) UPDATE · \(validation.unchangedFields.count) SAME")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(validation.canApply ? SPDFVTheme.paleCobalt : SPDFVTheme.redaction)
                ForEach(validation.issues.prefix(3)) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(issue.kind.rawValue.uppercased()) / \(issue.name)")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(SPDFVTheme.redaction)
                        Text(issue.detail)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(SPDFVTheme.navigatorMuted)
                    }
                }
                HStack(spacing: 7) {
                    Button("CLEAR", action: session.clearPendingFormData)
                        .buttonStyle(SidebarButtonStyle(prominent: false))
                    Button("APPLY DATA", action: session.applyPendingFormData)
                        .buttonStyle(SidebarButtonStyle(prominent: true))
                        .disabled(!validation.canApply || validation.updatedFields.isEmpty)
                        .accessibilityIdentifier("form-data.apply")
                }
            } else {
                Text("Import validates every field before editing. Export writes current values and may contain private information.")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 7) {
                Button("IMPORT JSON", action: session.importFormDataFromPicker)
                    .buttonStyle(SidebarButtonStyle(prominent: true))
                    .accessibilityIdentifier("form-data.import")
                Button("EXPORT VALUES", action: session.exportFormDataFromPicker)
                    .buttonStyle(SidebarButtonStyle(prominent: false))
                    .disabled(session.formFields.isEmpty)
                    .accessibilityIdentifier("form-data.export")
            }
        }
        .padding(12)
        .background(SPDFVTheme.navigatorInset)
        .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider).frame(height: 1) }
    }
}

private struct FieldDraftingPlate: View {
    @ObservedObject var session: DocumentSession
    @Binding var kind: PDFFormFieldKind
    @Binding var name: String
    @Binding var value: String
    @Binding var choices: String

    private let authoredKinds: [PDFFormFieldKind] = [.text, .checkbox, .choice]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FIELD DRAFT")
                Spacer()
                Text("PAGE \(session.pageIndex + 1)")
            }
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .tracking(0.9)
            .foregroundStyle(SPDFVTheme.navigatorFaint)

            HStack(spacing: 5) {
                ForEach(authoredKinds, id: \.self) { option in
                    Button {
                        kind = option
                    } label: {
                        VStack(spacing: 4) {
                            SPDFVIcon(icon(for: option), size: 11)
                            Text(shortLabel(for: option))
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                        }
                        .foregroundStyle(kind == option ? Color.white : SPDFVTheme.navigatorMuted)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(kind == option ? SPDFVTheme.cobalt : SPDFVTheme.navigator)
                        .overlay { Rectangle().stroke(kind == option ? SPDFVTheme.cobalt : SPDFVTheme.divider, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }

            DraftField(label: "NAME", prompt: "field_name", text: $name)

            if kind == .text {
                DraftField(label: "INITIAL VALUE", prompt: "Optional", text: $value)
            } else if kind == .choice {
                DraftField(label: "OPTIONS", prompt: "Draft,Review,Approved", text: $choices)
            } else if kind == .checkbox {
                Button {
                    value = value == "true" ? "false" : "true"
                } label: {
                    HStack {
                        SPDFVIcon(value == "true" ? .checkboxOn : .checkboxOff)
                        Text(value == "true" ? "START MARKED" : "START OPEN")
                        Spacer()
                    }
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(value == "true" ? SPDFVTheme.paleCobalt : SPDFVTheme.navigatorMuted)
                }
                .buttonStyle(.plain)
            }

            Button(session.activeAnnotationTool == .formField ? "PLACEMENT ARMED" : "PLACE FIELD") {
                let parsedChoices = choices.split(separator: ",").map(String.init)
                session.prepareFormField(PDFFormFieldDraft(name: name, kind: kind, value: value, choices: parsedChoices))
            }
            .buttonStyle(SidebarButtonStyle(prominent: true))

            Text(session.activeAnnotationTool == .formField
                 ? "Click the page to set the field anchor"
                 : "The field lands at a type-specific production size")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(session.activeAnnotationTool == .formField ? SPDFVTheme.paleCobalt : SPDFVTheme.navigatorMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(SPDFVTheme.navigatorInset)
        .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider).frame(height: 1) }
    }

    private func icon(for kind: PDFFormFieldKind) -> SPDFVIconName {
        switch kind {
        case .text: .textCursor
        case .checkbox: .checkboxOn
        case .choice: .choiceField
        default: .unknownField
        }
    }

    private func shortLabel(for kind: PDFFormFieldKind) -> String {
        switch kind {
        case .text: "TEXT"
        case .checkbox: "CHECK"
        case .choice: "CHOICE"
        default: "FIELD"
        }
    }
}

private struct DraftField: View {
    let label: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(SPDFVTheme.navigatorFaint)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SPDFVTheme.navigatorText)
                .padding(.horizontal, 7)
                .frame(height: 27)
                .background(SPDFVTheme.navigator)
                .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
    }
}

private struct SignaturePad: View {
    @Binding var strokes: [[CGPoint]]
    @State private var activeStroke: [CGPoint] = []

    var body: some View {
        Canvas { context, size in
            let baselineY = size.height * 0.72
            var baseline = Path()
            baseline.move(to: CGPoint(x: 10, y: baselineY))
            baseline.addLine(to: CGPoint(x: size.width - 10, y: baselineY))
            context.stroke(baseline, with: .color(SPDFVTheme.divider), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            for stroke in strokes + (activeStroke.isEmpty ? [] : [activeStroke]) where stroke.count > 1 {
                var path = Path()
                path.move(to: stroke[0])
                for point in stroke.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(SPDFVTheme.navigatorText), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        }
        .background(SPDFVTheme.navigator)
        .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        .overlay(alignment: .topLeading) {
            Text(strokes.isEmpty && activeStroke.isEmpty ? "DRAW HERE" : "ORIGINAL")
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .tracking(1)
                .foregroundStyle(SPDFVTheme.navigatorFaint)
                .padding(7)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in activeStroke.append(value.location) }
                .onEnded { _ in
                    if activeStroke.count > 1 { strokes.append(activeStroke) }
                    activeStroke = []
                }
        )
        .accessibilityLabel("Signature drawing pad")
    }
}
