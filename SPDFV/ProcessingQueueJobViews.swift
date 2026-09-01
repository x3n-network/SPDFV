import Foundation
import SPDFVCore
import SwiftUI

struct AutomationJobRow: View {
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

struct AutomationJobDetail: View {
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
