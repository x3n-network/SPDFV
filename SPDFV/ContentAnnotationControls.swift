import AppKit
import PDFKit
import SwiftUI

struct MarkupToolButton: View {
    let kind: MarkupKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                SPDFVIcon(kind.icon, size: 11)
                    .font(.system(size: 11, weight: .semibold))
                Text(kind.label.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(SPDFVTheme.primaryText)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(nsColor: SPDFVTheme.annotationNSColor(for: kind)))
                    .frame(height: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.label)
        .help("Add \(kind.label.lowercased()) to selected text")
    }
}

struct CanvasToolButton: View {
    let tool: CanvasAnnotationTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                SPDFVIcon(tool.icon, size: 11)
                    .font(.system(size: 11, weight: .semibold))
                Text(tool.label.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? Color.white : SPDFVTheme.primaryText)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(isSelected ? SPDFVTheme.cobalt : Color.clear)
            .overlay {
                Rectangle().stroke(isSelected ? SPDFVTheme.cobalt : SPDFVTheme.divider, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tool.help)
        .accessibilityLabel(tool.label)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct AnnotationInspectorStrip: View {
    @ObservedObject var session: DocumentSession
    @State private var contents = ""
    @State private var opacity = 1.0
    @State private var strokeWidth = 1.0
    @State private var fontSize = 14.0

    private var selection: AnnotationSelection? { session.selectedAnnotation }

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(selection.map { Color(nsColor: $0.annotation.color) } ?? SPDFVTheme.cobalt)
                .frame(width: 5)

            VStack(spacing: 7) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((selection?.typeLabel ?? "ANNOTATION").uppercased())
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(SPDFVTheme.primaryText)
                        Text("PAGE \((selection?.pageIndex ?? 0) + 1) · \(selection?.author ?? "Unknown")")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SPDFVTheme.secondaryText)
                    }
                    .frame(width: 150, alignment: .leading)

                    TextField("Annotation text or note", text: $contents)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SPDFVTheme.primaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(SPDFVTheme.navigatorInset)
                        .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
                        .onSubmit(commitContents)
                        .accessibilityLabel("Annotation contents")

                    HStack(spacing: 6) {
                        duplicateButton
                        deleteButton
                    }
                }

                HStack(spacing: 10) {
                    Text("INK")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(SPDFVTheme.secondaryText)

                    HStack(spacing: 4) {
                        ForEach(AnnotationColorPreset.allCases) { preset in
                            colorButton(preset)
                        }
                    }

                    Rectangle().fill(SPDFVTheme.divider).frame(width: 1, height: 18)

                    InspectorMetricSlider(
                        label: "OPACITY",
                        value: $opacity,
                        range: 0.12...1,
                        displayValue: "\(Int((opacity * 100).rounded()))%",
                        onEditingChanged: editStyle
                    ) { session.updateSelectedAnnotationOpacity($0) }

                    if selection?.hasAdjustableStroke == true {
                        InspectorMetricSlider(
                            label: "STROKE",
                            value: $strokeWidth,
                            range: 0.5...8,
                            displayValue: String(format: "%.1f", strokeWidth),
                            onEditingChanged: editStyle
                        ) { session.updateSelectedAnnotationStrokeWidth($0) }
                    }

                    if selection?.hasAdjustableFont == true {
                        InspectorMetricSlider(
                            label: "TYPE",
                            value: $fontSize,
                            range: 8...48,
                            displayValue: "\(Int(fontSize.rounded()))",
                            onEditingChanged: editStyle
                        ) { session.updateSelectedAnnotationFontSize($0) }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.trailing, 14)
        .frame(height: 74)
        .background(SPDFVTheme.folio)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
        }
        .onAppear(perform: loadContents)
        .onChange(of: session.selectedAnnotation?.id) { _, _ in loadContents() }
    }

    private func loadContents() {
        contents = session.selectedAnnotation?.contents ?? ""
        opacity = session.selectedAnnotation?.opacity ?? 1
        strokeWidth = session.selectedAnnotation?.strokeWidth ?? 1
        fontSize = session.selectedAnnotation?.fontSize ?? 14
    }

    private func commitContents() {
        session.updateSelectedAnnotation(contents: contents)
    }

    private func editStyle(_ isEditing: Bool) {
        if isEditing {
            session.beginSelectedAnnotationStyleEdit()
        } else {
            session.commitSelectedAnnotationStyleEdit()
        }
    }

    private func colorButton(_ preset: AnnotationColorPreset) -> some View {
        Button {
            session.recolorSelectedAnnotation(preset)
            opacity = session.selectedAnnotation?.opacity ?? opacity
        } label: {
            Rectangle()
                .fill(Color(nsColor: preset.nsColor))
                .frame(width: 16, height: 16)
                .overlay { Rectangle().stroke(SPDFVTheme.primaryText.opacity(0.22), lineWidth: 1) }
                .padding(2)
                .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .help("Use \(preset.label.lowercased())")
        .accessibilityLabel("\(preset.label) annotation color")
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            session.deleteSelectedAnnotation()
        } label: {
            HStack(spacing: 6) {
                SPDFVIcon(.delete)
                Text("DELETE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.6)
            }
            .foregroundStyle(Color.red)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .overlay { Rectangle().stroke(Color.red.opacity(0.7), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete selected annotation")
    }

    private var duplicateButton: some View {
        Button {
            session.duplicateSelectedAnnotation()
        } label: {
            SPDFVIcon(.duplicate)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SPDFVTheme.primaryText)
                .frame(width: 30, height: 30)
                .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .help("Duplicate selected annotation (⌘D)")
        .accessibilityLabel("Duplicate selected annotation")
    }
}

private struct InspectorMetricSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let displayValue: String
    let onEditingChanged: (Bool) -> Void
    let update: (Double) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(SPDFVTheme.secondaryText)
            Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
                .controlSize(.mini)
                .frame(width: 70)
                .onChange(of: value) { _, newValue in update(newValue) }
            Text(displayValue)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(SPDFVTheme.primaryText)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label.capitalized)
        .accessibilityValue(displayValue)
    }
}
