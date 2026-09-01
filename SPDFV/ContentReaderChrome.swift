import AppKit
import PDFKit
import SwiftUI

struct PageStepper: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        PageJumpControl(session: session)
    }
}

struct ZoomDeck: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        HStack(spacing: 2) {
            SquareToolButton(icon: .zoomOut, help: "Zoom out") {
                session.perform(.zoomOut)
            }

            Button {
                session.perform(.actualSize)
            } label: {
                Text(session.zoomLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.primaryText)
                    .frame(width: 48, height: 34)
            }
            .buttonStyle(.plain)
            .help("Actual size")

            SquareToolButton(icon: .zoomIn, help: "Zoom in") {
                session.perform(.zoomIn)
            }

            Rectangle()
                .fill(SPDFVTheme.divider)
                .frame(width: 1, height: 22)
                .padding(.horizontal, 5)

            SquareToolButton(icon: .fitPage, help: "Fit page") {
                session.perform(.fitPage)
            }
        }
    }
}

struct PageLayoutSelector: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        Menu {
            ForEach(PageLayoutMode.allCases) { layout in
                Button {
                    session.setPageLayout(layout)
                } label: {
                    if layout == session.pageLayout {
                        SPDFVIconLabel(title: layout.label, icon: .check)
                    } else {
                        Text(layout.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                PageLayoutGlyph(layout: session.pageLayout)
                    .frame(width: 22, height: 22)
                Text(session.pageLayout.label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.6)
            }
            .foregroundStyle(SPDFVTheme.primaryText)
            .padding(.horizontal, 8)
            .frame(height: 34)
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Page layout: \(session.pageLayout.label)")
        .accessibilityLabel("Page layout")
        .accessibilityValue(session.pageLayout.label)
    }
}

private struct PageLayoutGlyph: View {
    let layout: PageLayoutMode

    var body: some View {
        GeometryReader { geometry in
            let color = SPDFVTheme.primaryText
            switch layout {
            case .single:
                page(color)
                    .frame(width: 11, height: 15)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            case .continuous:
                VStack(spacing: 2) {
                    page(color)
                    page(color)
                }
                .frame(width: 11, height: 18)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            case .spread:
                HStack(spacing: 2) {
                    page(color)
                    page(color)
                }
                .frame(width: 18, height: 13)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
    }

    private func page(_ color: Color) -> some View {
        Rectangle()
            .fill(color.opacity(0.13))
            .overlay { Rectangle().stroke(color, lineWidth: 1) }
    }
}

struct SquareToolButton: View {
    let icon: SPDFVIconName
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            SPDFVIcon(icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(SquareToolButtonStyle(isHovering: isHovering))
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovering = $0 }
    }
}

private struct SquareToolButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? SPDFVTheme.primaryText : SPDFVTheme.tertiaryText)
            .background(
                configuration.isPressed
                    ? SPDFVTheme.controlPressed
                    : (isHovering && isEnabled ? SPDFVTheme.controlPressed.opacity(0.72) : Color.clear)
            )
            .overlay {
                Rectangle().stroke(SPDFVTheme.divider.opacity(configuration.isPressed ? 1 : 0), lineWidth: 1)
            }
    }
}

struct PageSpine: View {
    @ObservedObject var session: DocumentSession

    private var progress: CGFloat {
        guard session.pageCount > 1 else { return 0 }
        return CGFloat(session.pageIndex) / CGFloat(session.pageCount - 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let usableHeight = max(1, geometry.size.height - 64)
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(SPDFVTheme.spineTrack)
                    .frame(width: 1)
                    .padding(.vertical, 24)

                VStack(spacing: 0) {
                    Text(String(format: "%02d", session.pageIndex + 1))
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 24)
                        .background(SPDFVTheme.cobalt)
                    Rectangle()
                        .fill(SPDFVTheme.paleCobalt)
                        .frame(width: 1, height: 12)
                }
                .offset(y: 20 + usableHeight * progress)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 34)
        .padding(.trailing, 6)
        .allowsHitTesting(false)
    }
}

struct DocumentStatusBar: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        HStack(spacing: 18) {
            DocumentStatusItem(label: "PAGE", value: "\(session.pageIndex + 1) OF \(session.pageCount)")
            DocumentStatusItem(label: "VIEW", value: session.pageLayout.label.uppercased())
            DocumentStatusItem(label: "MARKS", value: "\(session.annotationCount)")
            Spacer()
            DocumentStatusItem(label: "SCALE", value: session.zoomLabel)
            Circle()
                .fill(session.isDirty ? Color.orange : SPDFVTheme.cobalt)
                .frame(width: 6, height: 6)
            Text(session.isDirty ? "MODIFIED" : "READY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(SPDFVTheme.statusBarText)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(SPDFVTheme.statusBarBackground)
    }
}

private struct DocumentStatusItem: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(SPDFVTheme.statusBarLabel)
            Text(value).foregroundStyle(SPDFVTheme.statusBarText)
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .tracking(0.8)
    }
}

struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            SPDFVTheme.statusBarBackground.opacity(0.9)
            Rectangle()
                .strokeBorder(SPDFVTheme.paleCobalt, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .padding(16)
            VStack(spacing: 10) {
                SPDFVIcon(.insertPages)
                    .font(.system(size: 30, weight: .light))
                Text("Drop to open")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
        }
    }
}

struct EmptyDocumentView: View {
    @ObservedObject var session: DocumentSession
    @Binding var themePreference: ThemePreference
    let openDocument: () -> Void

    var body: some View {
        ZStack {
            SPDFVTheme.canvas

            VStack(spacing: 0) {
                HStack {
                    Text("SPDFV")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(2.4)
                    Spacer()
                    HStack(spacing: 16) {
                        Text("SIMPLE PDF VIEWER")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(SPDFVTheme.secondaryText)
                        ThemeSelector(selection: $themePreference)
                    }
                }
                .foregroundStyle(SPDFVTheme.primaryText)
                .padding(22)

                Spacer()

                HStack(spacing: 22) {
                    launchCard

                    if !session.recentDocuments.isEmpty {
                        RecentDocumentsPanel(session: session)
                    }
                }

                Spacer()

                Text("⌘O  OPEN   ·   DROP  ANYWHERE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(SPDFVTheme.tertiaryText)
                    .padding(.bottom, 22)
            }
        }
    }

    private var launchCard: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(SPDFVTheme.cobalt)
                .frame(width: 7)

            VStack(alignment: .leading, spacing: 26) {
                Text("A clear place\nfor documents.")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .tracking(-1.2)
                    .foregroundStyle(SPDFVTheme.primaryText)

                Text("Open a PDF or drop one into the window.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(SPDFVTheme.secondaryText)

                Button(action: openDocument) {
                    HStack(spacing: 28) {
                        Text("OPEN PDF")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.3)
                        SPDFVIcon(.reveal)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .background(SPDFVTheme.statusBarBackground)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("document.open")
            }
            .padding(42)
        }
        .frame(width: 510, height: 350, alignment: .leading)
        .background(SPDFVTheme.folio)
        .shadow(color: .black.opacity(0.28), radius: 32, y: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document.empty")
    }
}

private struct RecentDocumentsPanel: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(SPDFVTheme.secondaryText)
                Spacer()
                Button("CLEAR") { session.clearRecentDocuments() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.tertiaryText)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            VStack(spacing: 0) {
                ForEach(Array(session.recentDocuments.prefix(5).enumerated()), id: \.element) { index, url in
                    Button {
                        session.open(url)
                    } label: {
                        HStack(spacing: 11) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundStyle(SPDFVTheme.paleCobalt)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(SPDFVTheme.primaryText)
                                    .lineLimit(1)
                                Text(url.deletingLastPathComponent().lastPathComponent.uppercased())
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .tracking(0.7)
                                    .foregroundStyle(SPDFVTheme.tertiaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            SPDFVIcon(.reveal)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(SPDFVTheme.tertiaryText)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 55)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open recent document \(url.lastPathComponent)")

                    if index < min(session.recentDocuments.count, 5) - 1 {
                        Rectangle()
                            .fill(SPDFVTheme.divider)
                            .frame(height: 1)
                            .padding(.leading, 40)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 270, height: 350)
        .background(SPDFVTheme.folio)
        .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
    }
}

struct ThemeSelector: View {
    @Binding var selection: ThemePreference

    var body: some View {
        Menu {
            ForEach(ThemePreference.allCases) { preference in
                Button {
                    selection = preference
                } label: {
                    SPDFVIconLabel(title: preference.label, icon: preference.icon)
                }
            }
        } label: {
            HStack(spacing: 7) {
                SPDFVIcon(selection.icon, size: 11)
                    .font(.system(size: 11, weight: .semibold))
                Text(selection.label.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
            }
            .foregroundStyle(SPDFVTheme.primaryText)
            .padding(.horizontal, 9)
            .frame(height: 34)
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Appearance: \(selection.label)")
        .accessibilityLabel("Appearance")
        .accessibilityValue(selection.label)
    }
}

#Preview {
    ContentView()
}
