import PDFKit
import SPDFVCore
import SwiftUI

struct FormFieldRow: View {
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

struct SidebarButtonStyle: ButtonStyle {
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
