import AppKit
import PDFKit
import SPDFVCore
import SwiftUI
import UniformTypeIdentifiers

struct PagesNavigator: View {
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
