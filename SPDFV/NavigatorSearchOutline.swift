import SwiftUI

struct OutlineNavigator: View {
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

struct SearchNavigator: View {
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

struct NavigatorEmptyState: View {
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
