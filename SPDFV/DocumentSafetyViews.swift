import SPDFVCore
import SwiftUI

struct LockedDocumentView: View {
    @ObservedObject var session: DocumentSession
    let openDocument: () -> Void
    @State private var password = ""
    @State private var unlockFailed = false

    var body: some View {
        VStack(spacing: 18) {
            SPDFVIcon(.secureCopy)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(SPDFVTheme.paleCobalt)

            VStack(spacing: 6) {
                Text("PASSWORD REQUIRED")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.4)
                Text("Unlock this PDF to read or edit its contents.")
                    .font(.system(size: 13))
                    .foregroundStyle(SPDFVTheme.secondaryText)
            }

            SecureField("PDF password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(unlock)
                .accessibilityIdentifier("document.unlock.password")

            if unlockFailed {
                Text("That password did not unlock the document.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SPDFVTheme.redaction)
            }

            HStack(spacing: 10) {
                Button("OPEN ANOTHER PDF", action: openDocument)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("document.unlock.open-another")
                Button("UNLOCK", action: unlock)
                    .buttonStyle(.borderedProminent)
                    .tint(SPDFVTheme.cobalt)
                    .disabled(password.isEmpty)
                    .accessibilityIdentifier("document.unlock.submit")
            }
            .font(.system(size: 10, weight: .black, design: .monospaced))
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SPDFVTheme.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Locked PDF")
        .accessibilityIdentifier("document.locked")
    }

    private func unlock() {
        unlockFailed = !session.unlockDocument(with: password)
        if !unlockFailed { password = "" }
    }
}

struct DocumentInfoNavigator: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        ScrollView {
            if let details = session.documentDetails {
                VStack(alignment: .leading, spacing: 22) {
                    if let gate = session.safetyGate {
                        InspectorSection(title: "SAFETY GATE") {
                            InspectorRow(label: "Result", value: gate.level.displayLabel)
                            InspectorRow(label: "Locked", value: gate.locked ? "Password required" : "No")
                            InspectorRow(label: "Encrypted", value: gate.encrypted ? "Yes" : "No")
                            if !gate.certificateSignatureFields.isEmpty {
                                InspectorRow(label: "Signatures", value: gate.certificateSignatureFields.joined(separator: ", "))
                            }
                            ForEach(gate.issues) { issue in
                                InspectorRow(label: issue.level.displayLabel, value: issue.detail)
                            }
                        }
                    }

                    InspectorSection(title: "FILE") {
                        InspectorRow(label: "Name", value: details.fileName)
                        InspectorRow(label: "Size", value: details.fileSize)
                        InspectorRow(label: "Pages", value: "\(session.pageCount)")
                        InspectorRow(label: "Page size", value: details.pageSize)
                    }

                    InspectorSection(title: "METADATA") {
                        InspectorRow(label: "Title", value: details.title ?? "—")
                        InspectorRow(label: "Author", value: details.author ?? "—")
                        InspectorRow(label: "Subject", value: details.subject ?? "—")
                    }

                    InspectorSection(title: "PERMISSIONS") {
                        if let permissions = session.safetyGate?.permissions {
                            InspectorRow(label: "Print", value: permissions.printing.permissionLabel)
                            InspectorRow(label: "Copy", value: permissions.copying.permissionLabel)
                            InspectorRow(label: "Edit", value: permissions.documentChanges.permissionLabel)
                            InspectorRow(label: "Assemble", value: permissions.documentAssembly.permissionLabel)
                            InspectorRow(label: "Access", value: permissions.contentAccessibility.permissionLabel)
                            InspectorRow(label: "Annotate", value: permissions.commenting.permissionLabel)
                            InspectorRow(label: "Forms", value: permissions.formFieldEntry.permissionLabel)
                        } else {
                            InspectorRow(label: "Copy", value: details.allowsCopying.permissionLabel)
                            InspectorRow(label: "Print", value: details.allowsPrinting.permissionLabel)
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}

private extension PDFSafetyGateLevel {
    var displayLabel: String {
        switch self {
        case .pass: "Pass"
        case .warning: "Warning"
        case .stop: "Stop"
        }
    }
}

private extension Bool {
    var permissionLabel: String { self ? "Allowed" : "Restricted" }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(SPDFVTheme.navigatorFaint)

            VStack(spacing: 0) { content }
                .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
        }
    }
}

private struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .foregroundStyle(SPDFVTheme.navigatorText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)
        }
    }
}
