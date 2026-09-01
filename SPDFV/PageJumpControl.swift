import AppKit
import SwiftUI

/// A keyboard-first, squared document-instrument page jump control for SPDFV.
/// Displays current and total pages, opens a focused numeric entry popover,
/// validates/clamps input within the document range, and jumps via `session.goToPage(index)`.
struct PageJumpControl: View {
    @ObservedObject var session: DocumentSession
    var includeSteppers: Bool = true

    @State private var isPopoverPresented = false
    @State private var inputPageText = ""
    @State private var isBadgeHovering = false

    var body: some View {
        HStack(spacing: 4) {
            if includeSteppers {
                PageJumpToolButton(
                    icon: .left,
                    help: "Previous page (⌥←)",
                    accessibilityLabel: "Previous page"
                ) {
                    session.perform(.previousPage)
                }
                .disabled(session.pageIndex <= 0 || session.pageCount == 0)
                .accessibilityIdentifier("page.previous")
            }

            pageBadgeButton
                .popover(
                    isPresented: $isPopoverPresented,
                    arrowEdge: .bottom
                ) {
                    PageJumpPopover(
                        session: session,
                        isPresented: $isPopoverPresented,
                        pageText: $inputPageText
                    )
                }

            if includeSteppers {
                PageJumpToolButton(
                    icon: .right,
                    help: "Next page (⌥→)",
                    accessibilityLabel: "Next page"
                ) {
                    session.perform(.nextPage)
                }
                .disabled(session.pageIndex >= max(0, session.pageCount - 1) || session.pageCount == 0)
                .accessibilityIdentifier("page.next")
            }
        }
        .disabled(session.pageCount == 0)
    }

    private var pageBadgeButton: some View {
        Button {
            presentJumpPopover()
        } label: {
            HStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formattedPage(session.pageIndex + 1))
                        .foregroundStyle(SPDFVTheme.primaryText)
                    Text("/")
                        .foregroundStyle(SPDFVTheme.tertiaryText)
                    Text(formattedPage(session.pageCount))
                        .foregroundStyle(SPDFVTheme.secondaryText)
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))

                SPDFVIcon(.jump, size: 9)
                    .foregroundStyle(isBadgeHovering || isPopoverPresented ? SPDFVTheme.cobalt : SPDFVTheme.tertiaryText)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background(
                isPopoverPresented
                    ? SPDFVTheme.controlPressed
                    : (isBadgeHovering ? SPDFVTheme.controlPressed.opacity(0.72) : Color.clear)
            )
            .overlay {
                Rectangle().stroke(
                    isPopoverPresented ? SPDFVTheme.cobalt : SPDFVTheme.divider,
                    lineWidth: isPopoverPresented ? 1.5 : 1
                )
            }
        }
        .buttonStyle(.plain)
        .onHover { isBadgeHovering = $0 }
        .help("Jump to page (Click to enter page number)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Page navigation and jump")
        .accessibilityValue("Page \(session.pageIndex + 1) of \(session.pageCount)")
        .accessibilityHint("Opens numeric jump entry popover to navigate directly to any page")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("page.jump")
    }

    private func presentJumpPopover() {
        inputPageText = session.pageCount > 0 ? "\(session.pageIndex + 1)" : "1"
        isPopoverPresented = true
    }

    private func formattedPage(_ page: Int) -> String {
        if session.pageCount < 100 {
            return String(format: "%02d", max(0, page))
        } else {
            return "\(max(0, page))"
        }
    }
}

/// The focused numeric entry popover for keyboard-first page jumps.
private struct PageJumpPopover: View {
    @ObservedObject var session: DocumentSession
    @Binding var isPresented: Bool
    @Binding var pageText: String

    @FocusState private var isFieldFocused: Bool

    private var totalPages: Int {
        max(1, session.pageCount)
    }

    private var parsedPageNumber: Int? {
        let trimmed = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed)
    }

    private var targetClampedPage: Int {
        guard let num = parsedPageNumber else {
            return session.pageIndex + 1
        }
        return min(max(1, num), totalPages)
    }

    private var isOutOfRange: Bool {
        guard let num = parsedPageNumber else { return false }
        return num < 1 || num > totalPages
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("JUMP TO PAGE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(SPDFVTheme.secondaryText)

                Spacer()

                Text("1 – \(totalPages)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(SPDFVTheme.tertiaryText)
            }

            Rectangle()
                .fill(SPDFVTheme.divider)
                .frame(height: 1)

            // Input Row
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("PAGE")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(SPDFVTheme.statusBarLabel)

                    TextField("1", text: $pageText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(SPDFVTheme.primaryText)
                        .focused($isFieldFocused)
                        .onSubmit(commitJump)
                        .onExitCommand {
                            isPresented = false
                        }
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(SPDFVTheme.navigatorInset)
                .overlay {
                    Rectangle().stroke(
                        isOutOfRange
                            ? Color.orange
                            : (isFieldFocused ? SPDFVTheme.cobalt : SPDFVTheme.divider),
                        lineWidth: isFieldFocused ? 2 : 1
                    )
                }
                .accessibilityLabel("Target page number")
                .accessibilityValue(pageText)

                Button(action: commitJump) {
                    Text("GO")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 34)
                        .background(SPDFVTheme.cobalt)
                }
                .buttonStyle(.plain)
                .help("Jump to page (Return)")
                .accessibilityLabel("Go to page")
            }

            if isOutOfRange {
                Text("Will clamp to page \(targetClampedPage) of \(totalPages)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }

            // Quick Nav Presets
            HStack(spacing: 4) {
                QuickJumpButton(label: "FIRST (1)") {
                    jumpToDirectPage(1)
                }
                QuickJumpButton(label: "PREV (-1)") {
                    jumpToDirectPage(max(1, session.pageIndex))
                }
                QuickJumpButton(label: "NEXT (+1)") {
                    jumpToDirectPage(min(totalPages, session.pageIndex + 2))
                }
                QuickJumpButton(label: "LAST (\(totalPages))") {
                    jumpToDirectPage(totalPages)
                }
            }

            Rectangle()
                .fill(SPDFVTheme.divider)
                .frame(height: 1)

            // Footer hint
            HStack {
                Text("PRESS RETURN TO JUMP · ESC TO CLOSE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(SPDFVTheme.tertiaryText)
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(SPDFVTheme.folio)
        .onAppear {
            DispatchQueue.main.async {
                isFieldFocused = true
            }
        }
    }

    private func commitJump() {
        let clamped = targetClampedPage
        let targetIndex = clamped - 1
        session.goToPage(targetIndex)
        isPresented = false
    }

    private func jumpToDirectPage(_ page: Int) {
        let clamped = min(max(1, page), totalPages)
        session.goToPage(clamped - 1)
        isPresented = false
    }
}

/// A quick jump helper button matching the squared instrument design.
private struct QuickJumpButton: View {
    let label: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(SPDFVTheme.secondaryText)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 22)
                .background(isHovering ? SPDFVTheme.controlPressed : Color.clear)
                .overlay {
                    Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(label)
    }
}

/// A squared tool button matching SPDFV toolbar instrument language.
private struct PageJumpToolButton: View {
    let icon: SPDFVIconName
    let help: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            SPDFVIcon(icon, size: 12)
                .foregroundStyle(isEnabled ? SPDFVTheme.primaryText : SPDFVTheme.tertiaryText)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .background(
                    isHovering && isEnabled ? SPDFVTheme.controlPressed.opacity(0.72) : Color.clear
                )
                .overlay {
                    Rectangle().stroke(SPDFVTheme.divider.opacity(isHovering && isEnabled ? 1 : 0), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .onHover { isHovering = $0 }
    }
}

struct PageJumpControl_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ZStack {
                SPDFVTheme.folio
                PageJumpControl(session: DocumentSession())
            }
            .frame(width: 320, height: 100)
            .preferredColorScheme(.light)
            .previewDisplayName("Light")

            ZStack {
                SPDFVTheme.folio
                PageJumpControl(session: DocumentSession())
            }
            .frame(width: 320, height: 100)
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark")
        }
    }
}
