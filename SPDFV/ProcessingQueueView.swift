import SPDFVCore
import SwiftUI

struct ProcessingQueueView: View {
    @ObservedObject private var store = ProcessingQueueStore.shared
    @ObservedObject private var activityStore = ActivityCenterStore.shared
    @State private var selection: UUID?
    @State private var filter = ProcessingQueueFilter.all
    @State private var section = ActivityCenterSection.activity

    var body: some View {
        VStack(spacing: 0) {
            queueHeader
            if section == .activity {
                ActivityOverviewView()
            } else {
                summaryBar

                HStack(spacing: 0) {
                    queueColumn
                        .frame(minWidth: 340, idealWidth: 390, maxWidth: 440)
                    Rectangle().fill(SPDFVTheme.divider).frame(width: 1)
                    detailColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 860, minHeight: 590)
        .background(SPDFVTheme.navigator)
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: filteredJobs.map(\.id)) { _, _ in selectFirstIfNeeded() }
    }

    private var queueHeader: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 9) {
                    SPDFVIcon(.automation)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SPDFVTheme.paleCobalt)
                    Text("ACTIVITY CENTER")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .tracking(1.5)
                }
                Text("DOCUMENT WORK  /  AUTOMATION LEDGER")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.15)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(ActivityCenterSection.allCases) { item in
                    Button(item.label) { section = item }
                        .buttonStyle(QueueFilterButtonStyle(selected: section == item))
                }
            }

            HStack(spacing: 7) {
                if section == .activity {
                    QueueButton("CLEAR FINISHED", icon: .delete) { activityStore.clearFinished() }
                        .disabled(!activityStore.records.contains(where: { $0.status.isTerminal }))
                } else {
                    QueueButton("IMPORT", icon: .save) { store.importQueue() }
                    QueueButton("EXPORT", icon: .share) { store.exportQueue() }
                        .disabled(store.queue.jobs.isEmpty)
                    QueueButton("ADD JOB", icon: .add, prominent: false) { store.addJob() }
                    QueueButton(store.isRunning ? "RUNNING" : "RUN QUEUE", icon: store.isRunning ? .processing : .run, prominent: true) {
                        store.runPending()
                    }
                    .disabled(store.isRunning || store.queue.summary.queued == 0)
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 74)
        .foregroundStyle(SPDFVTheme.navigatorText)
        .background(SPDFVTheme.navigatorInset)
        .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.cobalt).frame(height: 2) }
    }

    private var summaryBar: some View {
        HStack(spacing: 0) {
            statusCount("TOTAL", value: store.queue.summary.total, color: SPDFVTheme.navigatorText)
            statusCount("QUEUED", value: store.queue.summary.queued, color: PDFRecipeJobStatus.queued.statusColor)
            statusCount("RUNNING", value: store.queue.summary.running, color: PDFRecipeJobStatus.running.statusColor)
            statusCount("PASSED", value: store.queue.summary.passed, color: PDFRecipeJobStatus.passed.statusColor)
            statusCount("STOPPED", value: store.queue.summary.failed, color: PDFRecipeJobStatus.failed.statusColor)
            Spacer()
            HStack(spacing: 7) {
                Circle()
                    .fill(store.isRunning ? PDFRecipeJobStatus.running.statusColor : SPDFVTheme.navigatorFaint)
                    .frame(width: 6, height: 6)
                Text(store.notice.uppercased())
                    .lineLimit(1)
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.55)
            .foregroundStyle(SPDFVTheme.navigatorMuted)
            .padding(.horizontal, 18)
            backgroundControl
                .padding(.trailing, 14)
        }
        .frame(height: 46)
        .background(SPDFVTheme.navigator)
        .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider).frame(height: 1) }
    }

    private var backgroundControl: some View {
        Menu {
            switch store.backgroundStatus {
            case .off:
                Button("Turn On Background Processing") { store.setBackgroundProcessingEnabled(true) }
            case .on:
                Button("Turn Off Background Processing") { store.setBackgroundProcessingEnabled(false) }
                Button("Open Login Item Settings") { store.openBackgroundSettings() }
            case .needsApproval:
                Button("Open Login Item Settings") { store.openBackgroundSettings() }
                Button("Remove Background Processing") { store.setBackgroundProcessingEnabled(false) }
            case .needsInstall:
                Button("Show SPDFV in Finder") { store.revealApp() }
            case .unavailable:
                Button("Check Again") { store.refreshBackgroundStatus() }
            }
        } label: {
            HStack(spacing: 7) {
                SPDFVIcon(store.backgroundStatus == .on ? .check : .queue)
                Text(store.backgroundStatus.label)
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .tracking(0.6)
            }
            .foregroundStyle(store.backgroundStatus == .on ? PDFRecipeJobStatus.passed.statusColor : SPDFVTheme.navigatorMuted)
            .padding(.horizontal, 9)
            .frame(height: 25)
            .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func statusCount(_ label: String, value: Int, color: Color) -> some View {
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

    private var queueColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(ProcessingQueueFilter.allCases) { item in
                    Button(item.label) { filter = item }
                        .buttonStyle(QueueFilterButtonStyle(selected: filter == item))
                }
                Spacer()
                Button("CLEAR") { store.clearFinished() }
                    .buttonStyle(.plain)
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
                    .disabled(store.queue.summary.passed + store.queue.summary.failed == 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 43)
            .background(SPDFVTheme.navigatorInset)
            .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider).frame(height: 1) }

            if filteredJobs.isEmpty {
                queueEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredJobs.enumerated()), id: \.element.id) { index, job in
                            AutomationJobRow(
                                job: job,
                                hasAccess: store.hasAccess(to: job.id),
                                isSelected: selection == job.id,
                                isFirst: index == 0,
                                isLast: index == filteredJobs.count - 1
                            ) { selection = job.id }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(SPDFVTheme.navigator)
            }
        }
    }

    private var queueEmptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            SPDFVIcon(filter == .all ? .tray : .filter)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(SPDFVTheme.navigatorFaint)
                .padding(.bottom, 14)
            Text(filter == .all ? "NO JOBS IN THE QUEUE" : "NO \(filter.label) JOBS")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(SPDFVTheme.navigatorText)
            Text(filter == .all ? "Add a PDF and recipe, or import a queue file." : "Choose another status filter.")
                .font(.system(size: 11))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .padding(.top, 6)
            if filter == .all {
                QueueButton("ADD FIRST JOB", icon: .add, prominent: true) { store.addJob() }
                    .padding(.top, 18)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            VStack(spacing: 24) {
                ForEach(0..<12, id: \.self) { _ in Rectangle().fill(SPDFVTheme.divider.opacity(0.16)).frame(height: 1) }
            }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let job = selectedJob {
            AutomationJobDetail(job: job, hasAccess: store.hasAccess(to: job.id), store: store)
        } else {
            VStack(spacing: 10) {
                SPDFVIcon(.left)
                    .foregroundStyle(SPDFVTheme.paleCobalt)
                Text("SELECT A JOB TO VIEW DETAILS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SPDFVTheme.navigatorInset)
        }
    }

    private var filteredJobs: [PDFRecipeJob] {
        store.queue.jobs
            .filter { filter.status == nil || $0.status == filter.status }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var selectedJob: PDFRecipeJob? {
        store.queue.jobs.first { $0.id == selection }
    }

    private func selectFirstIfNeeded() {
        if let selection, filteredJobs.contains(where: { $0.id == selection }) { return }
        selection = filteredJobs.first?.id
    }
}

private enum ActivityCenterSection: String, CaseIterable, Identifiable {
    case activity
    case queue

    var id: Self { self }
    var label: String { rawValue.uppercased() }
}

private struct AutomationJobRow: View {
    let job: PDFRecipeJob
    let hasAccess: Bool
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 0) {
                statusLine
                    .frame(width: 38)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(URL(fileURLWithPath: job.inputPath).lastPathComponent)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(job.status.statusLabel)
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(job.status.statusColor)
                    }
                    HStack(spacing: 7) {
                        Text(URL(fileURLWithPath: job.recipePath).deletingPathExtension().lastPathComponent.uppercased())
                            .lineLimit(1)
                        Text("·")
                        Text("TRY \(job.attempts)")
                        if !hasAccess && (job.status == .queued || job.status == .failed) {
                            Text("· ACCESS NEEDED").foregroundStyle(PDFRecipeJobStatus.running.statusColor)
                        }
                    }
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.45)
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
        .accessibilityLabel("\(job.status.statusLabel) job for \(URL(fileURLWithPath: job.inputPath).lastPathComponent)")
    }

    private var statusLine: some View {
        ZStack {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : SPDFVTheme.divider).frame(width: 1)
                Rectangle().fill(isLast ? Color.clear : SPDFVTheme.divider).frame(width: 1)
            }
            RoundedRectangle(cornerRadius: 1)
                .fill(job.status.statusColor)
                .frame(width: 9, height: 9)
                .overlay { RoundedRectangle(cornerRadius: 1).stroke(SPDFVTheme.navigator, lineWidth: 2) }
        }
    }
}

private struct AutomationJobDetail: View {
    let job: PDFRecipeJob
    let hasAccess: Bool
    @ObservedObject var store: ProcessingQueueStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                detailMasthead
                pathSection
                if let error = job.error { failureSection(error) }
                if let report = job.report { reportSection(report) }
                if job.report == nil && job.error == nil { waitingSection }
            }
        }
        .background(SPDFVTheme.navigatorInset)
    }

    private var detailMasthead: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(job.status.statusLabel)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(job.status.statusColor)
                    Text(URL(fileURLWithPath: job.inputPath).deletingPathExtension().lastPathComponent)
                        .font(.system(size: 26, weight: .light, design: .rounded))
                        .lineLimit(2)
                        .foregroundStyle(SPDFVTheme.navigatorText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(String(job.id.uuidString.prefix(8)))
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                    Text(job.createdAt.formatted(date: .abbreviated, time: .shortened).uppercased())
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(SPDFVTheme.navigatorMuted)
            }

            HStack(spacing: 7) {
                if !hasAccess && (job.status == .queued || job.status == .failed) {
                    QueueButton("RELINK ACCESS", icon: .link) { store.relink(job.id) }
                }
                if job.status == .failed {
                    QueueButton("RETRY", icon: .retry, prominent: true) { store.retry(job.id) }
                }
                if job.status == .passed && hasAccess {
                    QueueButton("SHOW OUTPUT", icon: .reveal) { store.revealOutput(for: job.id) }
                }
                Spacer()
                QueueButton("REMOVE", icon: .delete) { store.remove(job.id) }
                    .disabled(job.status == .running)
            }
        }
        .padding(24)
        .background(SPDFVTheme.navigator)
        .overlay(alignment: .bottom) { Rectangle().fill(job.status.statusColor).frame(height: 2) }
    }

    private var pathSection: some View {
        QueueSection(title: "FILES", caption: hasAccess ? "ACCESS READY" : "CHOOSE FILES BEFORE RUNNING") {
            pathRow("INPUT", job.inputPath)
            pathRow("RECIPE", job.recipePath)
            pathRow("OUTPUT", job.outputPath)
        }
    }

    private func failureSection(_ error: String) -> some View {
        QueueSection(title: "ERROR", caption: "CORRECT THE INPUT OR RECIPE, THEN RETRY") {
            HStack(alignment: .top, spacing: 12) {
                SPDFVIcon(.warning)
                    .foregroundStyle(PDFRecipeJobStatus.failed.statusColor)
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SPDFVTheme.navigatorText)
                    .textSelection(.enabled)
                Spacer()
            }
            .padding(14)
            .background(PDFRecipeJobStatus.failed.statusColor.opacity(0.08))
            .overlay(alignment: .leading) { Rectangle().fill(PDFRecipeJobStatus.failed.statusColor).frame(width: 2) }
        }
    }

    private func reportSection(_ report: PDFRecipeReport) -> some View {
        QueueSection(title: "RESULT", caption: "\(report.outputPageCount) PAGE\(report.outputPageCount == 1 ? "" : "S") · \(report.steps.count) COMPLETED STEPS") {
            VStack(spacing: 0) {
                ForEach(report.steps) { step in
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "%02d", step.index))
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(SPDFVTheme.paleCobalt)
                            .frame(width: 22, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.operation.uppercased())
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .tracking(0.7)
                            Text(step.summary)
                                .font(.system(size: 11))
                                .foregroundStyle(SPDFVTheme.navigatorMuted)
                        }
                        Spacer()
                        SPDFVIcon(.check)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(PDFRecipeJobStatus.passed.statusColor)
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider.opacity(0.45)).frame(height: 1) }
                }
            }
        }
    }

    private var waitingSection: some View {
        QueueSection(title: "STATUS", caption: job.status == .running ? "PROCESSING" : "READY TO RUN") {
            HStack(spacing: 10) {
                Rectangle().fill(job.status.statusColor).frame(width: 28, height: 2)
                Text(job.status == .running ? "Processing and verifying the PDF in memory." : "This job will write only after every recipe step passes.")
                    .font(.system(size: 11))
                    .foregroundStyle(SPDFVTheme.navigatorMuted)
            }
        }
    }

    private func pathRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(SPDFVTheme.navigatorFaint)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SPDFVTheme.navigatorText)
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct QueueSection<Content: View>: View {
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

private struct QueueButton: View {
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

private struct QueueFilterButtonStyle: ButtonStyle {
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

private enum ProcessingQueueFilter: String, CaseIterable, Identifiable {
    case all
    case queued
    case running
    case passed
    case failed

    var id: Self { self }
    var label: String { self == .failed ? "STOPPED" : rawValue.uppercased() }
    var status: PDFRecipeJobStatus? { self == .all ? nil : PDFRecipeJobStatus(rawValue: rawValue) }
}

private extension PDFRecipeJobStatus {
    var statusLabel: String {
        switch self {
        case .queued: "QUEUED"
        case .running: "RUNNING"
        case .passed: "PASSED"
        case .failed: "STOPPED"
        }
    }

    var statusColor: Color {
        switch self {
        case .queued: SPDFVTheme.paleCobalt
        case .running: Color(hex: 0xD58A18)
        case .passed: Color(hex: 0x2E9A68)
        case .failed: SPDFVTheme.redaction
        }
    }
}
