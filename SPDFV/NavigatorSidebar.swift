import AppKit
import PDFKit
import SPDFVCore
import SwiftUI
import UniformTypeIdentifiers

struct NavigatorSidebar: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        VStack(spacing: 0) {
            modeSwitcher

            Rectangle()
                .fill(SPDFVTheme.divider)
                .frame(height: 1)

            Group {
                switch session.navigatorMode {
                case .pages:
                    PagesNavigator(session: session)
                case .outline:
                    OutlineNavigator(session: session)
                case .search:
                    SearchNavigator(session: session)
                case .forms:
                    FormsNavigator(session: session)
                case .annotations:
                    AnnotationsNavigator(session: session)
                case .info:
                    DocumentInfoNavigator(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SPDFVTheme.navigator)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(NavigatorMode.allCases) { mode in
                Button {
                    session.navigatorMode = mode
                } label: {
                    VStack(spacing: 5) {
                        SPDFVIcon(mode.icon, size: 12)
                            .font(.system(size: 12, weight: .semibold))
                        Text(mode.label.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                    }
                    .foregroundStyle(
                        session.navigatorMode == mode
                            ? SPDFVTheme.navigatorText
                            : SPDFVTheme.navigatorMuted
                    )
                    .frame(maxWidth: .infinity, minHeight: 51)
                    .overlay(alignment: .bottom) {
                        if session.navigatorMode == mode {
                            Rectangle().fill(SPDFVTheme.cobalt).frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FormsNavigator: View {
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
    var id: Self { self }
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

private struct FormFieldRow: View {
    let field: PDFFormFieldReport
    @ObservedObject var session: DocumentSession
    let isSelected: Bool
    let onDelete: () -> Void
    @State private var value: String
    @State private var editedName: String
    @State private var x: Double
    @State private var y: Double
    @State private var width: Double
    @State private var height: Double

    init(field: PDFFormFieldReport, session: DocumentSession, isSelected: Bool, onDelete: @escaping () -> Void) {
        self.field = field
        self.session = session
        self.isSelected = isSelected
        self.onDelete = onDelete
        _value = State(initialValue: field.value)
        _editedName = State(initialValue: field.name)
        _x = State(initialValue: field.bounds.x)
        _y = State(initialValue: field.bounds.y)
        _width = State(initialValue: field.bounds.width)
        _height = State(initialValue: field.bounds.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { session.showFormField(field) } label: {
                HStack(spacing: 8) {
                    Text(String(format: "%02d", field.page))
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(SPDFVTheme.paleCobalt)
                    Text(field.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SPDFVTheme.navigatorText)
                        .lineLimit(1)
                    Spacer()
                    Text(field.kind.rawValue.uppercased())
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(SPDFVTheme.navigatorFaint)
                }
            }
            .buttonStyle(.plain)

            editor

            if isSelected {
                precisionPlate
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(isSelected ? SPDFVTheme.cobalt.opacity(0.09) : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(SPDFVTheme.cobalt).frame(width: 2) }
        }
        .onChange(of: field.value) { _, newValue in value = newValue }
        .onChange(of: field.name) { _, newValue in editedName = newValue }
        .onChange(of: field.bounds) { _, bounds in
            x = bounds.x
            y = bounds.y
            width = bounds.width
            height = bounds.height
        }
    }

    private var precisionPlate: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text("FIELD NAME")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(SPDFVTheme.navigatorFaint)
                TextField("Unique field name", text: $editedName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorText)
                    .onSubmit { commitName() }
                Button("RENAME") { commitName() }
                    .buttonStyle(.plain)
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.paleCobalt)
                    .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editedName == field.name)
            }
            .padding(.horizontal, 8)
            .frame(height: 27)
            .background(SPDFVTheme.navigator)
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }

            HStack(spacing: 5) {
                GeometryValueCell(label: "X", value: $x, onCommit: commitGeometry)
                GeometryValueCell(label: "Y", value: $y, onCommit: commitGeometry)
                GeometryValueCell(label: "W", value: $width, onCommit: commitGeometry)
                GeometryValueCell(label: "H", value: $height, onCommit: commitGeometry)
            }

            HStack(spacing: 5) {
                Text("MOVE")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(SPDFVTheme.navigatorFaint)
                ForEach(FormNudgeDirection.allCases) { direction in
                    Button {
                        session.nudgeSelectedObject(horizontal: direction.dx, vertical: direction.dy)
                    } label: {
                        SPDFVIcon(direction.icon, size: 8)
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 21, height: 19)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SPDFVTheme.navigatorText)
                    .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
                    .help("Move field 1 point \(direction.label.lowercased())")
                    .accessibilityLabel("Move field \(direction.label.lowercased()) one point")
                }
                Spacer()
                Text("⌘ ARROWS · 1 PT")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorFaint)
                Button(action: onDelete) {
                    SPDFVIcon(.delete)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SPDFVTheme.redaction)
                        .frame(width: 22, height: 19)
                        .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .help("Remove this form field")
            }
        }
        .padding(8)
        .background(SPDFVTheme.navigatorInset)
        .overlay {
            Rectangle()
                .stroke(SPDFVTheme.paleCobalt.opacity(0.35), lineWidth: 1)
        }
    }

    private func commitName() {
        let proposed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proposed.isEmpty, proposed != field.name else { return }
        session.renameFormField(from: field.name, to: proposed)
    }

    private func commitGeometry() {
        session.updateSelectedFormFieldBounds(CGRect(x: x, y: y, width: width, height: height))
    }

    @ViewBuilder
    private var editor: some View {
        if field.readOnly || field.kind == .signature || field.kind == .pushButton {
            Text(field.readOnly ? "READ ONLY" : field.kind == .signature ? "CERTIFICATE FIELD" : "ACTION BUTTON")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
        } else if field.kind == .checkbox || field.kind == .radio {
            Button {
                value = value == "true" ? "false" : "true"
                session.applyFormValue(value, to: field)
            } label: {
                HStack(spacing: 7) {
                    SPDFVIcon(value == "true" ? .checkboxOn : .checkboxOff)
                    Text(value == "true" ? "MARKED" : "OPEN")
                }
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(value == "true" ? SPDFVTheme.paleCobalt : SPDFVTheme.navigatorMuted)
            }
            .buttonStyle(.plain)
        } else if field.kind == .choice, !field.choices.isEmpty {
            Picker(field.name, selection: $value) {
                ForEach(field.choices, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .onChange(of: value) { _, newValue in session.applyFormValue(newValue, to: field) }
        } else {
            TextField("Enter value", text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(SPDFVTheme.navigatorText)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(SPDFVTheme.navigator)
                .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
                .onSubmit { session.applyFormValue(value, to: field) }
        }
    }
}

private struct GeometryValueCell: View {
    let label: String
    @Binding var value: Double
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundStyle(SPDFVTheme.paleCobalt)
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.plain)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(SPDFVTheme.navigatorText)
                .onSubmit(onCommit)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 25)
        .background(SPDFVTheme.navigator)
        .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
    }
}

private enum FormNudgeDirection: CaseIterable, Identifiable {
    case left, right, up, down

    var id: Self { self }
    var dx: CGFloat { self == .left ? -1 : self == .right ? 1 : 0 }
    var dy: CGFloat { self == .down ? -1 : self == .up ? 1 : 0 }
    var icon: SPDFVIconName {
        switch self {
        case .left: .left
        case .right: .right
        case .up: .up
        case .down: .down
        }
    }
    var label: String { String(describing: self) }
}

private struct SidebarButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(prominent ? Color.white : SPDFVTheme.navigatorText)
            .frame(maxWidth: .infinity, minHeight: 27)
            .background(prominent ? SPDFVTheme.cobalt.opacity(configuration.isPressed ? 0.72 : 1) : Color.clear)
            .overlay { Rectangle().stroke(prominent ? SPDFVTheme.cobalt : SPDFVTheme.divider, lineWidth: 1) }
            .opacity(isEnabled ? 1 : 0.38)
    }
}

private struct AnnotationsNavigator: View {
    @ObservedObject var session: DocumentSession
    @State private var category: AnnotationCategory = .all
    @State private var currentPageOnly = false

    private var filteredRecords: [AnnotationRecord] {
        session.annotationRecords.filter { record in
            (category == .all || record.category == category)
                && (!currentPageOnly || record.pageIndex == session.pageIndex)
        }
    }

    var body: some View {
        Group {
            if session.annotationRecords.isEmpty {
                NavigatorEmptyState(
                    icon: .annotations,
                    title: "No marks yet",
                    detail: "Highlights, notes, drawings, and shapes will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(filteredRecords.count) / \(session.annotationRecords.count) MARKS")
                        Spacer()
                        Text("DOCUMENT REGISTER")
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(SPDFVTheme.navigatorFaint)
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
                    }

                    HStack(spacing: 6) {
                        Menu {
                            Picker("Annotation type", selection: $category) {
                                ForEach(AnnotationCategory.allCases) { category in
                                    Text(category.label).tag(category)
                                }
                            }
                        } label: {
                            RegisterFilterLabel(
                                icon: .filter,
                                text: category == .all ? "ALL TYPES" : category.label.uppercased(),
                                isActive: category != .all
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()

                        Button {
                            currentPageOnly.toggle()
                        } label: {
                            RegisterFilterLabel(
                                icon: .document,
                                text: "PAGE \(session.pageIndex + 1)",
                                isActive: currentPageOnly
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show current page annotations only")
                        .accessibilityValue(currentPageOnly ? "On" : "Off")

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(SPDFVTheme.navigatorInset)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
                    }

                    if filteredRecords.isEmpty {
                        NavigatorEmptyState(
                            icon: .filter,
                            title: "No matching marks",
                            detail: "Change the type or page scope to widen the register."
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredRecords) { record in
                                    AnnotationRegisterRow(
                                        record: record,
                                        isSelected: session.selectedAnnotation?.id == record.id
                                    ) {
                                        session.showAnnotation(record)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct RegisterFilterLabel: View {
    let icon: SPDFVIconName
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            SPDFVIcon(icon, size: 10)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(0.5)
        }
        .foregroundStyle(isActive ? Color.white : SPDFVTheme.navigatorText)
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(isActive ? SPDFVTheme.cobalt : Color.clear)
        .overlay {
            Rectangle().stroke(isActive ? SPDFVTheme.cobalt : SPDFVTheme.divider, lineWidth: 1)
        }
    }
}

private struct AnnotationRegisterRow: View {
    let record: AnnotationRecord
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color(nsColor: record.color))
                    .frame(width: 4, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(record.typeLabel.uppercased())
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(0.7)
                        Spacer()
                        Text(String(format: "P%02d", record.pageIndex + 1))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    Text(record.preview)
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(isSelected ? SPDFVTheme.navigatorText : SPDFVTheme.navigatorMuted)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(isSelected ? SPDFVTheme.controlPressed : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(record.typeLabel), page \(record.pageIndex + 1), \(record.preview)")
    }
}

private struct DocumentInfoNavigator: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        ScrollView {
            if let details = session.documentDetails {
                VStack(alignment: .leading, spacing: 22) {
                    InspectorSection(title: "FILE") {
                        InspectorRow(label: "Name", value: details.fileName)
                        InspectorRow(label: "Size", value: details.fileSize)
                        InspectorRow(label: "Pages", value: "\(session.pageCount)")
                        InspectorRow(label: "Page size", value: details.pageSize)
                    }

                    InspectorSection(title: "METADATA") {
                        InspectorRow(label: "Title", value: details.title ?? "—")
                        InspectorRow(label: "Author", value: details.author ?? "—")
                        InspectorRow(label: "Subject", value: details.subject ?? "—")
                    }

                    InspectorSection(title: "PERMISSIONS") {
                        InspectorRow(label: "Encrypted", value: details.encrypted ? "Yes" : "No")
                        InspectorRow(label: "Copy text", value: details.allowsCopying ? "Allowed" : "Restricted")
                        InspectorRow(label: "Print", value: details.allowsPrinting ? "Allowed" : "Restricted")
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(SPDFVTheme.navigatorFaint)

            VStack(spacing: 0) {
                content
            }
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
    }
}

private struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .foregroundStyle(SPDFVTheme.navigatorText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
        }
    }
}

private struct PagesNavigator: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        VStack(spacing: 0) {
            BinderyRail(session: session)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 17) {
                        ForEach(0..<session.pageCount, id: \.self) { index in
                            PageThumbnail(session: session, index: index)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
                .onChange(of: session.pageIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }
}

private struct BinderyRail: View {
    @ObservedObject var session: DocumentSession
    @State private var showsImpositionTray = false
    @State private var showsCropPlate = false
    @State private var showsMergePlate = false

    var body: some View {
        HStack(spacing: 2) {
            BinderyButton(icon: .up, help: "Move page earlier") {
                session.moveCurrentPage(by: -1)
            }
            .disabled(session.pageIndex == 0)

            BinderyButton(icon: .down, help: "Move page later") {
                session.moveCurrentPage(by: 1)
            }
            .disabled(session.pageIndex >= session.pageCount - 1)

            BinderyButton(icon: .rotateLeft, help: "Rotate page left") {
                session.rotateCurrentPage(clockwise: false)
            }

            BinderyButton(icon: .rotateRight, help: "Rotate page right") {
                session.rotateCurrentPage(clockwise: true)
            }

            BinderyButton(icon: .duplicate, help: "Duplicate page") {
                session.duplicateCurrentPage()
            }

            BinderyButton(icon: .delete, help: "Delete page", destructive: true) {
                session.deleteCurrentPage()
            }
            .disabled(session.pageCount <= 1)

            BinderyButton(icon: .scissors, help: "Open page selection tray") {
                showsImpositionTray.toggle()
            }
            .popover(isPresented: $showsImpositionTray, arrowEdge: .trailing) {
                ImpositionTray(session: session, isPresented: $showsImpositionTray)
            }

            BinderyButton(icon: .crop, help: "Open crop plate") {
                showsCropPlate.toggle()
            }
            .popover(isPresented: $showsCropPlate, arrowEdge: .trailing) {
                CropPlate(session: session, isPresented: $showsCropPlate)
            }

            BinderyButton(icon: .documentAdd, help: "Append another PDF") {
                showsMergePlate.toggle()
            }
            .popover(isPresented: $showsMergePlate, arrowEdge: .trailing) {
                MergePlate(session: session, isPresented: $showsMergePlate)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(SPDFVTheme.navigatorInset)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
        }
    }
}

private struct MergePlate: View {
    @ObservedObject var session: DocumentSession
    @Binding var isPresented: Bool
    @State private var sourceDocument: PDFDocument?
    @State private var sourceName = ""
    @State private var selectedSourcePages: Set<Int> = []
    @State private var placement: PDFInsertionPlacement = .afterSelection

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ASSEMBLY GATE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.3)
                    Text(sourceDocument == nil ? "AWAITING SOURCE PDF" : "\(selectedSourcePages.count) INCOMING SHEETS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
                Spacer()
                SPDFVIcon(.route)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(SPDFVTheme.paleCobalt)
            }
            .padding(14)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            if let sourceDocument {
                sourceControls(sourceDocument)
            } else {
                Button(action: chooseSource) {
                    VStack(spacing: 9) {
                        SPDFVIcon(.documentAdd)
                            .font(.system(size: 25, weight: .light))
                            .foregroundStyle(SPDFVTheme.paleCobalt)
                        Text("CHOOSE SOURCE PDF")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(0.9)
                        Text("Select sheets and place them into the current document.")
                            .font(.system(size: 10))
                            .foregroundStyle(SPDFVTheme.navigatorMuted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 370)
        .background(SPDFVTheme.navigatorInset)
    }

    @ViewBuilder
    private func sourceControls(_ source: PDFDocument) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sourceName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text("\(source.pageCount) PAGES AVAILABLE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
                Spacer()
                Button("CHANGE", action: chooseSource)
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.paleCobalt)
            }
            .padding(12)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 9) {
                    ForEach(0..<source.pageCount, id: \.self) { index in
                        SourcePageTile(
                            image: source.page(at: index)?.thumbnail(of: NSSize(width: 76, height: 98), for: .cropBox),
                            pageNumber: index + 1,
                            isSelected: selectedSourcePages.contains(index)
                        ) {
                            if selectedSourcePages.contains(index) {
                                selectedSourcePages.remove(index)
                            } else {
                                selectedSourcePages.insert(index)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 128)

            HStack(spacing: 6) {
                TraySelectionButton(label: "ALL") {
                    selectedSourcePages = Set(0..<source.pageCount)
                }
                TraySelectionButton(label: "CLEAR") {
                    selectedSourcePages.removeAll()
                }
                Spacer()
                Text("\(selectedSourcePages.count) / \(source.pageCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            VStack(alignment: .leading, spacing: 7) {
                Text("INSERT RELATIVE TO CURRENT SELECTION")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                HStack(spacing: 6) {
                    ForEach(PDFInsertionPlacement.allCases) { option in
                        Button {
                            placement = option
                        } label: {
                            Text(option.label)
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .frame(maxWidth: .infinity, minHeight: 27)
                                .foregroundStyle(placement == option ? Color.white : SPDFVTheme.navigatorText)
                                .background(placement == option ? SPDFVTheme.cobalt : Color.clear)
                                .overlay { Rectangle().stroke(placement == option ? SPDFVTheme.cobalt : SPDFVTheme.divider, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            Button {
                session.insertPages(source, pageIndices: selectedSourcePages.sorted(), placement: placement)
                isPresented = false
            } label: {
                    SPDFVIconLabel(
                        title:
                        selectedSourcePages.count == 1 ? "Insert 1 page" : "Insert \(selectedSourcePages.count) pages",
                        icon: .insertPages
                    )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(TrayActionButtonStyle(isPrimary: true))
            .disabled(selectedSourcePages.isEmpty)
            .padding(12)
        }
    }

    private func chooseSource() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a PDF to assemble into this document"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let loaded = try PDFOperations.open(url)
            guard let data = loaded.dataRepresentation(), let detached = PDFDocument(data: data) else {
                throw PDFOperationError.operationFailed("Could not prepare source pages")
            }
            sourceDocument = detached
            sourceName = url.lastPathComponent
            selectedSourcePages = Set(0..<detached.pageCount)
        } catch {
            session.errorMessage = "The source PDF could not be prepared: \(error.localizedDescription)"
        }
    }
}

private struct SourcePageTile: View {
    let image: NSImage?
    let pageNumber: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Rectangle().fill(Color.white)
                    }
                    if isSelected {
                        SPDFVIcon(.check)
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(Color.white)
                            .frame(width: 17, height: 17)
                            .background(SPDFVTheme.cobalt)
                    }
                }
                .frame(width: 66, height: 88)
                .background(Color.white)
                .overlay { Rectangle().stroke(isSelected ? SPDFVTheme.paleCobalt : SPDFVTheme.pageBorder, lineWidth: isSelected ? 2 : 1) }

                Text(String(format: "%02d", pageNumber))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? SPDFVTheme.navigatorText : SPDFVTheme.navigatorMuted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Source page \(pageNumber)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct CropPlate: View {
    @ObservedObject var session: DocumentSession
    @Binding var isPresented: Bool
    @State private var insets = PageCropInsets.zero

    private var targetCount: Int { max(1, session.selectedPageIndices.count) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CROP PLATE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.3)
                    Text(targetCount == 1 ? "1 PAGE ON THE BED" : "\(targetCount) PAGES ON THE BED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
                Spacer()
                SPDFVIcon(.crop)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(SPDFVTheme.paleCobalt)
            }
            .padding(14)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            HStack(spacing: 6) {
                ForEach(PageCropPreset.allCases) { preset in
                    TraySelectionButton(label: preset.label) {
                        insets = preset.insets
                    }
                }
            }
            .padding(12)

            HStack(spacing: 18) {
                CropSchematic(insets: insets)

                VStack(spacing: 8) {
                    CropEdgeField(label: "TOP", value: $insets.top)
                    HStack(spacing: 7) {
                        CropEdgeField(label: "LEFT", value: $insets.left)
                        CropEdgeField(label: "RIGHT", value: $insets.right)
                    }
                    CropEdgeField(label: "BOTTOM", value: $insets.bottom)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)

            Text("Measurements are points from the original media edge. Cropping stays reversible until export.")
                .font(.system(size: 10))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 13)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            VStack(spacing: 8) {
                Button {
                    session.setCropEditing(true)
                    isPresented = false
                } label: {
                    SPDFVIconLabel(title: "Edit directly on page", icon: .scan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(TrayActionButtonStyle(isPrimary: false))

                Button {
                    insets.top = max(0, insets.top)
                    insets.right = max(0, insets.right)
                    insets.bottom = max(0, insets.bottom)
                    insets.left = max(0, insets.left)
                    session.applyCropInsets(insets)
                    isPresented = false
                } label: {
                    SPDFVIconLabel(title: targetCount == 1 ? "Apply crop" : "Apply crop to \(targetCount) pages", icon: .crop)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(TrayActionButtonStyle(isPrimary: true))
            }
            .padding(12)
        }
        .frame(width: 312)
        .background(SPDFVTheme.navigatorInset)
        .onAppear { insets = session.cropInsetsForSelection() }
    }
}

private struct CropSchematic: View {
    let insets: PageCropInsets

    private func displayInset(_ value: Double) -> CGFloat {
        CGFloat(min(22, max(0, value) / 2.5))
    }

    var body: some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 86, height: 116)
            .overlay(alignment: .top) {
                Rectangle().fill(SPDFVTheme.cobalt.opacity(0.24)).frame(height: displayInset(insets.top))
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(SPDFVTheme.cobalt.opacity(0.24)).frame(width: displayInset(insets.right))
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(SPDFVTheme.cobalt.opacity(0.24)).frame(height: displayInset(insets.bottom))
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(SPDFVTheme.cobalt.opacity(0.24)).frame(width: displayInset(insets.left))
            }
            .overlay {
                Rectangle().stroke(SPDFVTheme.navigatorFaint, lineWidth: 1)
                Rectangle()
                    .strokeBorder(SPDFVTheme.paleCobalt, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .padding(6)
            }
            .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
    }
}

private struct CropEdgeField: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(SPDFVTheme.navigatorMuted)
            HStack(spacing: 4) {
                TextField("0", value: $value, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text("PT")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorFaint)
            }
            .padding(.horizontal, 7)
            .frame(height: 28)
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ImpositionTray: View {
    @ObservedObject var session: DocumentSession
    @Binding var isPresented: Bool

    private var selectedCount: Int { session.selectedPageIndices.count }
    private var selectionLabel: String {
        let pages = session.selectedPageIndices.sorted().map { $0 + 1 }
        guard let first = pages.first else { return "CURRENT PAGE WILL BE USED" }
        if pages.count == 1 { return "PAGE \(first) SELECTED" }
        if pages == Array(first...(pages.last ?? first)) {
            return "PAGES \(first)–\(pages.last ?? first) SELECTED"
        }
        return "\(pages.count) NONCONTIGUOUS PAGES"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("IMPOSITION TRAY")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.3)
                    Text(selectionLabel)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
                Spacer()
                Text("\(selectedCount == 0 ? 1 : selectedCount) / \(session.pageCount)")
                    .font(.system(size: 17, weight: .light, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.paleCobalt)
            }
            .padding(14)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            HStack(spacing: 6) {
                TraySelectionButton(label: "ALL") { session.selectAllPages() }
                TraySelectionButton(label: "ODD") { session.selectPages(matching: .odd) }
                TraySelectionButton(label: "EVEN") { session.selectPages(matching: .even) }
                TraySelectionButton(label: "CLEAR") { session.clearPageSelection() }
            }
            .padding(12)

            Text("Click a page to start again. Hold ⌘ to toggle pages or ⇧ to select a range.")
                .font(.system(size: 10))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 13)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            VStack(spacing: 7) {
                Button {
                    session.extractCurrentPageFromPicker()
                    isPresented = false
                } label: {
                    SPDFVIconLabel(title: selectedCount > 1 ? "Extract selected pages…" : "Extract page…", icon: .extract)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(TrayActionButtonStyle(isPrimary: true))

                Button {
                    session.deleteCurrentPage()
                    isPresented = false
                } label: {
                    SPDFVIconLabel(title: selectedCount > 1 ? "Delete selected pages" : "Delete page", icon: .delete)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(TrayActionButtonStyle(isDestructive: true))
                .disabled(max(1, selectedCount) >= session.pageCount)
            }
            .padding(12)
        }
        .frame(width: 286)
        .background(SPDFVTheme.navigatorInset)
    }
}

private struct TraySelectionButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(0.7)
                .frame(maxWidth: .infinity, minHeight: 25)
                .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

private struct TrayActionButtonStyle: ButtonStyle {
    var isPrimary = false
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isPrimary ? Color.white : (isDestructive ? Color.red : SPDFVTheme.navigatorText))
            .padding(.horizontal, 11)
            .frame(minHeight: 34)
            .background(isPrimary ? SPDFVTheme.cobalt : (configuration.isPressed ? SPDFVTheme.controlPressed : Color.clear))
            .overlay { Rectangle().stroke(isPrimary ? SPDFVTheme.cobalt : SPDFVTheme.divider, lineWidth: 1) }
    }
}

private struct BinderyButton: View {
    let icon: SPDFVIconName
    let help: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SPDFVIcon(icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(destructive ? Color.red : SPDFVTheme.navigatorText)
                .frame(maxWidth: .infinity, minHeight: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct PageThumbnail: View {
    @ObservedObject var session: DocumentSession
    let index: Int
    @State private var isDropTarget = false

    private var isCurrent: Bool { session.pageIndex == index }
    private var isSelected: Bool { session.selectedPageIndices.contains(index) }
    private var selectionOrdinal: Int? {
        guard isSelected, session.selectedPageIndices.count > 1 else { return nil }
        return session.selectedPageIndices.sorted().firstIndex(of: index).map { $0 + 1 }
    }

    var body: some View {
        Button {
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            session.selectPage(
                index,
                extendingRange: modifiers.contains(.shift),
                toggling: modifiers.contains(.command)
            )
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if let thumbnail = session.thumbnail(for: index) {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 150, maxHeight: 182)
                            .background(.white)
                    } else {
                        Rectangle()
                            .fill(.white.opacity(0.9))
                            .aspectRatio(0.72, contentMode: .fit)
                    }

                    if isCurrent {
                        Rectangle()
                            .fill(SPDFVTheme.cobalt)
                            .frame(width: 4)
                    }

                    if let selectionOrdinal {
                        Text(String(format: "%02d", selectionOrdinal))
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 5)
                            .frame(height: 18)
                            .background(SPDFVTheme.cobalt)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(5)
                    }
                }
                .overlay {
                    Rectangle()
                        .stroke(
                            isSelected ? SPDFVTheme.paleCobalt : SPDFVTheme.pageBorder,
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .shadow(color: .black.opacity(0.28), radius: 8, y: 4)

                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(isSelected ? SPDFVTheme.navigatorText : SPDFVTheme.navigatorMuted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .draggable("\(index)")
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first, let sourceIndex = Int(value) else { return false }
            session.movePage(from: sourceIndex, to: index)
            return true
        } isTargeted: { isDropTarget = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
            return session.insertPDF(from: url, before: index)
        } isTargeted: { isDropTarget = $0 }
        .overlay {
            if isDropTarget {
                Rectangle()
                    .strokeBorder(SPDFVTheme.paleCobalt, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .padding(-6)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct OutlineNavigator: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        Group {
            if session.outlineEntries.isEmpty {
                NavigatorEmptyState(
                    icon: .outline,
                    title: "No contents",
                    detail: "This PDF doesn’t include an outline."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.outlineEntries) { entry in
                            Button {
                                if let pageIndex = entry.pageIndex {
                                    session.goToPage(pageIndex)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Rectangle()
                                        .fill(entry.pageIndex == session.pageIndex ? SPDFVTheme.cobalt : Color.clear)
                                        .frame(width: 2, height: 28)

                                    Text(entry.label)
                                        .font(.system(size: 12, weight: entry.depth == 0 ? .semibold : .regular))
                                        .lineLimit(2)
                                        .foregroundStyle(
                                            entry.pageIndex == nil
                                                ? SPDFVTheme.navigatorFaint
                                                : SPDFVTheme.navigatorText
                                        )

                                    Spacer(minLength: 4)

                                    if let page = entry.pageIndex {
                                        Text("\(page + 1)")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(SPDFVTheme.navigatorFaint)
                                    }
                                }
                                .padding(.leading, CGFloat(entry.depth) * 12 + 12)
                                .padding(.trailing, 13)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 9)
                }
            }
        }
    }
}

private struct SearchNavigator: View {
    @ObservedObject var session: DocumentSession
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SPDFVIcon(.search)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)

                TextField("Find in document", text: $session.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(SPDFVTheme.navigatorText)
                    .focused($searchIsFocused)
                    .onSubmit(session.runSearch)

                if !session.searchText.isEmpty {
                    Button {
                        session.searchText = ""
                        session.clearSearch()
                    } label: {
                        SPDFVIcon(.closeFilled)
                            .foregroundStyle(SPDFVTheme.navigatorMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear document search")
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(SPDFVTheme.navigatorInset)
            .overlay {
                Rectangle().stroke(
                    searchIsFocused ? SPDFVTheme.cobalt : SPDFVTheme.divider,
                    lineWidth: searchIsFocused ? 2 : 1
                )
            }
            .padding(12)
            .onAppear { searchIsFocused = true }

            if session.searchResults.isEmpty {
                NavigatorEmptyState(
                    icon: .search,
                    title: session.searchText.isEmpty ? "Find text" : "No matches",
                    detail: session.searchText.isEmpty
                        ? "Search every page in this PDF."
                        : "Try a different word or phrase."
                )
            } else {
                HStack {
                    Text("\(session.searchResults.count) MATCH\(session.searchResults.count == 1 ? "" : "ES")")
                    Spacer()
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(SPDFVTheme.navigatorFaint)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.searchResults) { result in
                            Button {
                                session.showSearchResult(at: result.selectionIndex)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text(String(format: "%02d", result.pageIndex + 1))
                                        .font(.system(size: 9, weight: .black, design: .monospaced))
                                        .foregroundStyle(SPDFVTheme.paleCobalt)
                                        .padding(.top, 2)

                                    Text(result.excerpt)
                                        .font(.system(size: 11))
                                        .foregroundStyle(SPDFVTheme.navigatorText)
                                        .lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 13)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Rectangle()
                                .fill(SPDFVTheme.divider)
                                .frame(height: 1)
                                .padding(.leading, 41)
                        }
                    }
                }
            }
        }
    }
}

private struct NavigatorEmptyState: View {
    let icon: SPDFVIconName
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            SPDFVIcon(icon, size: 24)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(SPDFVTheme.navigatorFaint)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(SPDFVTheme.navigatorText)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 170)
            Spacer()
        }
        .padding(18)
    }
}
