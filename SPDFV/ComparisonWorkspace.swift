import AppKit
import SPDFVCore
import SwiftUI

struct ComparisonWorkspace: View {
    @ObservedObject var session: DocumentSession
    @State private var visualization: ComparisonVisualizationMode = .sideBySide
    @State private var alignment: PDFComparisonAlignment
    @State private var similarityPercent: Double
    @State private var ignoredRegions: String
    @State private var optionError: String?
    @State private var showsUnchanged = false

    init(session: DocumentSession) {
        self.session = session
        _alignment = State(initialValue: session.comparisonOptions.alignment)
        _similarityPercent = State(initialValue: session.comparisonOptions.minimumAppearanceSimilarity * 100)
        _ignoredRegions = State(initialValue: Self.format(session.comparisonOptions.ignoredRegions))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                resultList
                    .frame(minWidth: 235, idealWidth: 270, maxWidth: 330)
                preview
                    .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(SPDFVTheme.canvas)
        .foregroundStyle(SPDFVTheme.navigatorText)
        .accessibilityIdentifier("compare.workspace")
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("COMPARE WORKSPACE")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1.2)
                    Text(session.comparisonReferenceName ?? "No reference selected")
                        .font(.system(size: 11))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
                Spacer()
                Picker("Alignment", selection: $alignment) {
                    Text("Intelligent").tag(PDFComparisonAlignment.intelligent)
                    Text("By position").tag(PDFComparisonAlignment.position)
                }
                .frame(width: 170)
                Picker("View", selection: $visualization) {
                    Text("Side by side").tag(ComparisonVisualizationMode.sideBySide)
                    Text("Overlay").tag(ComparisonVisualizationMode.overlay)
                    Text("Heatmap").tag(ComparisonVisualizationMode.heatmap)
                }
                .frame(width: 155)
                Button("EXPORT JSON", action: session.exportComparisonReport)
                    .buttonStyle(.bordered)
                    .disabled(session.comparisonReport == nil)
            }

            HStack(spacing: 12) {
                Text("APPEARANCE \(similarityPercent, specifier: "%.1f")%")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .frame(width: 112, alignment: .leading)
                Slider(value: $similarityPercent, in: 90...100, step: 0.1)
                    .frame(width: 170)
                TextField("Ignored regions: x,y,width,height;…", text: $ignoredRegions)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Ignored normalized page regions")
                Button(session.isComparing ? "COMPARING…" : "APPLY OPTIONS", action: applyOptions)
                    .buttonStyle(.borderedProminent)
                    .tint(SPDFVTheme.cobalt)
                    .disabled(session.isComparing || session.comparisonReferenceDocument == nil)
            }
            if let optionError {
                Text(optionError)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(SPDFVTheme.redaction)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(SPDFVTheme.navigator)
    }

    private var resultList: some View {
        VStack(spacing: 0) {
            Toggle("Show unchanged pages", isOn: $showsUnchanged)
                .toggleStyle(.checkbox)
                .font(.system(size: 10, weight: .medium))
                .padding(12)
            Divider()
            if session.isComparing {
                ProgressView("Comparing pages…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let report = session.comparisonReport {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(report.pages.filter { showsUnchanged || $0.status != .unchanged }) { page in
                            resultRow(page)
                        }
                    }
                }
            } else {
                Text("Run a comparison to inspect results.")
                    .font(.system(size: 11))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(SPDFVTheme.navigator)
    }

    private func resultRow(_ page: PDFPageComparison) -> some View {
        Button {
            session.showComparisonPage(page)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(pageLabel(page))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Spacer()
                    Text(page.status.workspaceLabel)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(page.status == .unchanged ? SPDFVTheme.navigatorMuted : SPDFVTheme.paleCobalt)
                }
                if !page.differences.isEmpty {
                    Text(page.differences.map(\.workspaceLabel).joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(session.selectedComparisonPosition == page.position ? SPDFVTheme.cobalt.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preview: some View {
        if let page = session.comparisonPage(at: session.selectedComparisonPosition) {
            GeometryReader { proxy in
                let imageSize = previewImageSize(proxy.size)
                let images = session.comparisonImages(for: page, size: imageSize)
                VStack(spacing: 12) {
                    previewTitle(page)
                    Group {
                        switch visualization {
                        case .sideBySide:
                            HStack(spacing: 14) {
                                pageImage(images.reference, label: "REFERENCE")
                                pageImage(images.candidate, label: "CANDIDATE")
                            }
                        case .overlay:
                            ZStack {
                                pageImage(images.reference, label: "REFERENCE")
                                pageImage(images.candidate, label: "CANDIDATE")
                                    .opacity(0.5)
                                    .blendMode(.difference)
                            }
                        case .heatmap:
                            pageImage(session.comparisonHeatmap(for: page, size: imageSize), label: "DIFFERENCE HEATMAP")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(16)
            }
        } else {
            Text("Select a comparison result.")
                .font(.system(size: 12))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func previewTitle(_ page: PDFPageComparison) -> some View {
        HStack {
            Text(pageLabel(page))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            Spacer()
            if let similarity = page.appearanceSimilarity {
                Text("APPEARANCE \(similarity * 100, specifier: "%.2f")%")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }
        }
    }

    private func pageImage(_ image: NSImage?, label: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .background(Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            } else {
                Text("No corresponding page")
                    .font(.system(size: 11))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5])) }
            }
        }
    }

    private func applyOptions() {
        do {
            let regions = try Self.parseRegions(ignoredRegions)
            optionError = nil
            session.rerunComparison(options: PDFComparisonOptions(
                alignment: alignment,
                minimumAppearanceSimilarity: similarityPercent / 100,
                ignoredRegions: regions
            ))
        } catch {
            optionError = error.localizedDescription
        }
    }

    private func pageLabel(_ page: PDFPageComparison) -> String {
        "REF \(page.referencePage.map(String.init) ?? "—")  →  CAND \(page.candidatePage.map(String.init) ?? "—")"
    }

    private func previewImageSize(_ available: CGSize) -> NSSize {
        let divisor: CGFloat = visualization == .sideBySide ? 2.2 : 1.2
        return NSSize(width: max(220, available.width / divisor), height: max(300, available.height - 90))
    }

    private static func parseRegions(_ text: String) throws -> [PDFComparisonIgnoredRegion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try trimmed.split(separator: ";").map { component in
            let values = component.split(separator: ",").compactMap {
                Double($0.trimmingCharacters(in: .whitespaces))
            }
            guard values.count == 4,
                  values[0] >= 0, values[1] >= 0,
                  values[2] > 0, values[3] > 0,
                  values[0] + values[2] <= 1,
                  values[1] + values[3] <= 1 else {
                throw ComparisonOptionError.invalidRegion
            }
            return PDFComparisonIgnoredRegion(x: values[0], y: values[1], width: values[2], height: values[3])
        }
    }

    private static func format(_ regions: [PDFComparisonIgnoredRegion]) -> String {
        regions.map { "\($0.x),\($0.y),\($0.width),\($0.height)" }.joined(separator: ";")
    }
}

private enum ComparisonOptionError: LocalizedError {
    case invalidRegion

    var errorDescription: String? {
        "Ignored regions must use normalized x,y,width,height values within 0…1, separated by semicolons."
    }
}

private extension PDFPageComparisonStatus {
    var workspaceLabel: String {
        switch self {
        case .unchanged: "SAME"
        case .changed: "CHANGED"
        case .added: "ADDED"
        case .removed: "REMOVED"
        }
    }
}

private extension PDFPageDifference {
    var workspaceLabel: String {
        switch self {
        case .appearance: "appearance"
        case .text: "text"
        case .dimensions: "size"
        case .rotation: "rotation"
        case .annotations: "annotations"
        case .formFields: "form fields"
        }
    }
}
