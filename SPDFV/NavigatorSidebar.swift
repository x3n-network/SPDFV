import SwiftUI

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
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.label)
                .accessibilityIdentifier("navigator.\(mode.rawValue)")
                .accessibilityValue(session.navigatorMode == mode ? "Selected" : "Not selected")
            }
        }
    }
}
