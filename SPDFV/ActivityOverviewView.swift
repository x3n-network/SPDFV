import SwiftUI

struct ActivityOverviewView: View {
    @ObservedObject private var store = ActivityCenterStore.shared
    @State private var selection: UUID?
    @State private var filter = ActivityFilter.all

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            HStack(spacing: 0) {
                activityColumn
                    .frame(minWidth: 340, idealWidth: 390, maxWidth: 440)
                Rectangle().fill(SPDFVTheme.divider).frame(width: 1)
                detailColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: filteredRecords.map(\.id)) { _, _ in selectFirstIfNeeded() }
    }

    private var summaryBar: some View {
        HStack(spacing: 0) {
            summaryCount("TOTAL", value: store.records.count, color: SPDFVTheme.navigatorText)
            summaryCount("ACTIVE", value: activeCount, color: SPDFVActivityStatus.running.statusColor)
            summaryCount("FINISHED", value: finishedCount, color: SPDFVActivityStatus.succeeded.statusColor)
            summaryCount("STOPPED", value: stoppedCount, color: SPDFVActivityStatus.failed.statusColor)
            Spacer()
            HStack(spacing: 7) {
                Circle()
                    .fill(activeCount > 0 ? SPDFVActivityStatus.running.statusColor : SPDFVTheme.navigatorFaint)
                    .frame(width: 6, height: 6)
                Text(activityNotice.uppercased())
                    .lineLimit(1)
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.55)
            .foregroundStyle(SPDFVTheme.navigatorMuted)
            .padding(.horizontal, 18)
        }
        .frame(height: 46)
        .background(SPDFVTheme.navigator)
        .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider).frame(height: 1) }
    }

    private func summaryCount(_ label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 9) {
            Text(String(format: "%02d", value))
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(SPDFVTheme.navigatorMuted)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .trailing) { Rectangle().fill(SPDFVTheme.divider.opacity(0.7)).frame(width: 1) }
    }

    private var activityColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(ActivityFilter.allCases) { item in
                    Button(item.label) { filter = item }
                        .buttonStyle(ActivityFilterButtonStyle(selected: filter == item))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 43)
            .background(SPDFVTheme.navigatorInset)
            .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider).frame(height: 1) }

            if filteredRecords.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredRecords.enumerated()), id: \.element.id) { index, record in
                            ActivityRecordRow(
                                record: record,
                                isSelected: selection == record.id,
                                isFirst: index == 0,
                                isLast: index == filteredRecords.count - 1
                            ) { selection = record.id }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(SPDFVTheme.navigator)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            SPDFVIcon(filter == .all ? .processing : .filter, size: 24)
                .foregroundStyle(SPDFVTheme.navigatorFaint)
            Text(filter == .all ? "NO ACTIVITY RECORDED" : "NO \(filter.label) ACTIVITY")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(SPDFVTheme.navigatorText)
            Text(filter == .all
                ? "OCR, secure exports, recipes, watches, and queue jobs will appear here."
                : "Choose another status filter.")
                .font(.system(size: 11))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 270)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            VStack(spacing: 24) {
                ForEach(0..<12, id: \.self) { _ in
                    Rectangle().fill(SPDFVTheme.divider.opacity(0.16)).frame(height: 1)
                }
            }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let record = selectedRecord {
            ActivityRecordDetail(record: record, store: store)
        } else {
            VStack(spacing: 10) {
                SPDFVIcon(.left)
                    .foregroundStyle(SPDFVTheme.paleCobalt)
                Text("SELECT ACTIVITY TO VIEW DETAILS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SPDFVTheme.navigatorInset)
        }
    }

    private var filteredRecords: [SPDFVActivityRecord] {
        store.records
            .filter(filter.includes)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var selectedRecord: SPDFVActivityRecord? {
        store.records.first { $0.id == selection }
    }

    private var activeCount: Int {
        store.records.count { $0.status == .running || $0.status == .queued }
    }

    private var finishedCount: Int {
        store.records.count { $0.status == .succeeded }
    }

    private var stoppedCount: Int {
        store.records.count { $0.status == .failed || $0.status == .cancelled }
    }

    private var activityNotice: String {
        if activeCount > 0 { return "\(activeCount) active operation\(activeCount == 1 ? "" : "s")" }
        if let latest = store.records.max(by: { $0.updatedAt < $1.updatedAt }) {
            return "Latest · \(latest.kind.label) · \(latest.status.label)"
        }
        return "Activity ledger ready"
    }

    private func selectFirstIfNeeded() {
        if let selection, filteredRecords.contains(where: { $0.id == selection }) { return }
        selection = filteredRecords.first?.id
    }
}

private struct ActivityRecordRow: View {
    let record: SPDFVActivityRecord
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 0) {
                timeline
                    .frame(width: 38)
                SPDFVIcon(record.kind.icon, size: 13)
                    .foregroundStyle(record.status.statusColor)
                    .frame(width: 27, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(record.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Spacer()
                        Text(record.status.label.uppercased())
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(record.status.statusColor)
                    }
                    HStack(spacing: 7) {
                        Text(record.kind.label.uppercased())
                        if let documentName = record.documentName {
                            Text("·")
                            Text(documentName.uppercased()).lineLimit(1)
                        }
                        Spacer()
                        Text(record.updatedAt.formatted(date: .omitted, time: .shortened).uppercased())
                    }
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
                .padding(.trailing, 14)
            }
            .frame(height: 68)
            .foregroundStyle(SPDFVTheme.navigatorText)
            .background(isSelected ? SPDFVTheme.controlPressed : Color.clear)
            .overlay(alignment: .leading) { Rectangle().fill(isSelected ? SPDFVTheme.cobalt : Color.clear).frame(width: 2) }
            .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider.opacity(0.55)).frame(height: 1).padding(.leading, 38) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(record.status.label) \(record.kind.label) activity: \(record.title)")
    }

    private var timeline: some View {
        ZStack {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : SPDFVTheme.divider).frame(width: 1)
                Rectangle().fill(isLast ? Color.clear : SPDFVTheme.divider).frame(width: 1)
            }
            RoundedRectangle(cornerRadius: 1)
                .fill(record.status.statusColor)
                .frame(width: 9, height: 9)
                .overlay { RoundedRectangle(cornerRadius: 1).stroke(SPDFVTheme.navigator, lineWidth: 2) }
        }
    }
}

private struct ActivityRecordDetail: View {
    let record: SPDFVActivityRecord
    @ObservedObject var store: ActivityCenterStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                detailSection
                if let outputPath = record.outputPath { outputSection(outputPath) }
            }
        }
        .background(SPDFVTheme.navigatorInset)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                SPDFVIcon(record.kind.icon, size: 24)
                    .foregroundStyle(record.status.statusColor)
                    .frame(width: 34, height: 34)
                    .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(record.kind.label.uppercased()) · \(record.status.label.uppercased())")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(record.status.statusColor)
                    Text(record.title)
                        .font(.system(size: 25, weight: .light, design: .rounded))
                        .lineLimit(3)
                        .foregroundStyle(SPDFVTheme.navigatorText)
                    if let documentName = record.documentName {
                        Text(documentName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SPDFVTheme.navigatorMuted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(String(record.id.uuidString.prefix(8)))
                    Text(record.startedAt.formatted(date: .abbreviated, time: .shortened).uppercased())
                }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
            }

            if record.outputPath != nil {
                ActivityCenterButton("SHOW OUTPUT", icon: .reveal, prominent: true) {
                    store.revealOutput(for: record.id)
                }
            }
        }
        .padding(24)
        .background(SPDFVTheme.navigator)
        .overlay(alignment: .bottom) { Rectangle().fill(record.status.statusColor).frame(height: 2) }
    }

    private var detailSection: some View {
        ActivityDetailSection(title: "STATUS", caption: record.updatedAt.formatted(date: .abbreviated, time: .shortened).uppercased()) {
            Text(record.detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SPDFVTheme.navigatorText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(record.status.statusColor.opacity(0.08))
                .overlay(alignment: .leading) { Rectangle().fill(record.status.statusColor).frame(width: 2) }
        }
    }

    private func outputSection(_ path: String) -> some View {
        ActivityDetailSection(title: "OUTPUT", caption: "REVEAL IN FINDER") {
            Text(path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SPDFVTheme.navigatorText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ActivityDetailSection<Content: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let content: Content

    init(title: String, caption: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(SPDFVTheme.navigatorText)
                Spacer()
                Text(caption)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.55)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }
            content
        }
        .padding(22)
        .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider).frame(height: 1) }
    }
}

private struct ActivityCenterButton: View {
    let title: String
    let icon: SPDFVIconName
    let prominent: Bool
    let action: () -> Void

    init(_ title: String, icon: SPDFVIconName, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                SPDFVIcon(icon, size: 9)
                Text(title)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.65)
            }
            .padding(.horizontal, 10)
            .frame(height: 29)
            .foregroundStyle(prominent ? Color.white : SPDFVTheme.navigatorText)
            .background(prominent ? SPDFVTheme.cobalt : Color.clear)
            .overlay { Rectangle().stroke(prominent ? SPDFVTheme.cobalt : SPDFVTheme.divider, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

private enum ActivityFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case finished
    case stopped

    var id: Self { self }
    var label: String { rawValue.uppercased() }

    func includes(_ record: SPDFVActivityRecord) -> Bool {
        switch self {
        case .all: true
        case .active: record.status == .queued || record.status == .running
        case .finished: record.status == .succeeded
        case .stopped: record.status == .failed || record.status == .cancelled
        }
    }
}

private struct ActivityFilterButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 7, weight: .black, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(selected ? Color.white : SPDFVTheme.navigatorMuted)
            .padding(.horizontal, 8)
            .frame(height: 23)
            .background(selected ? SPDFVTheme.cobalt : Color.clear)
            .overlay { Rectangle().stroke(selected ? SPDFVTheme.cobalt : SPDFVTheme.divider.opacity(0.7), lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension SPDFVActivityStatus {
    var statusColor: Color {
        switch self {
        case .queued: SPDFVTheme.paleCobalt
        case .running: Color(hex: 0xD58A18)
        case .succeeded: Color(hex: 0x2E9A68)
        case .failed: SPDFVTheme.redaction
        case .cancelled: SPDFVTheme.navigatorMuted
        }
    }
}
