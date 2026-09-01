import AppKit
import PDFKit
import SPDFVCore
import SwiftUI
import UniformTypeIdentifiers

struct MergePlate: View {
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
