import PDFKit
import SwiftUI

struct AnnotationsNavigator: View {
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
