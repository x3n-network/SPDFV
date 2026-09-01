import Foundation
import PDFKit
import SPDFVCore
import SwiftUI

struct RedactionGate: View {
    @ObservedObject var session: DocumentSession
    @Binding var isPresented: Bool
    @State private var restoresSearchableText = true
    @State private var forbiddenText = ""

    private var forbiddenTerms: [String] {
        forbiddenText
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("REDACTION GATE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.35)
                    Text("DESTRUCTIVE OUTPUT CONTROL")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
                Spacer()
                ZStack {
                    Rectangle()
                        .fill(SPDFVTheme.redactionInk)
                        .frame(width: 34, height: 20)
                    Rectangle()
                        .stroke(SPDFVTheme.redaction, lineWidth: 1.5)
                        .frame(width: 42, height: 28)
                }
            }
            .padding(14)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            VStack(spacing: 10) {
                Button {
                    session.setRedactionEditing(!session.isRedactionEditing)
                    isPresented = false
                } label: {
                    HStack {
                        SPDFVIconLabel(
                            title: session.isRedactionEditing ? "Stop drawing regions" : "Draw redaction regions",
                            icon: .region
                        )
                        Spacer()
                        Text(session.isRedactionEditing ? "ARMED" : "DIRECT")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(SPDFVTheme.navigatorText)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
                }
                .buttonStyle(.plain)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(session.pendingRedactions.count) REGION\(session.pendingRedactions.count == 1 ? "" : "S") STAGED")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                        Text("Affected pages will be flattened")
                            .font(.system(size: 10))
                            .foregroundStyle(SPDFVTheme.navigatorMuted)
                    }
                    Spacer()
                    Button("CLEAR") { session.clearPendingRedactions() }
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .buttonStyle(.plain)
                        .foregroundStyle(SPDFVTheme.redaction)
                        .disabled(session.pendingRedactions.isEmpty)
                }

                if !session.pendingRedactions.isEmpty {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(session.pendingRedactions) { mark in
                                RedactionRegisterRow(session: session, mark: mark)
                            }
                        }
                    }
                    .frame(maxHeight: 96)
                }

                VStack(alignment: .leading, spacing: 6) {
                    OCRSectionLabel(text: "VERIFY ABSENT · OPTIONAL")
                    TextField("secret, account number, identifier", text: $forbiddenText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 9)
                        .frame(height: 32)
                        .background(SPDFVTheme.navigator)
                        .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
                    Text("The export fails if any listed phrase remains extractable anywhere in the copy.")
                        .font(.system(size: 9))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }

                Toggle(isOn: $restoresSearchableText) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("REBUILD SAFE TEXT")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                        Text("OCR runs only after black regions are burned in")
                            .font(.system(size: 9))
                            .foregroundStyle(SPDFVTheme.navigatorMuted)
                    }
                }
                .toggleStyle(.switch)

                HStack(alignment: .top, spacing: 9) {
                    Rectangle().fill(SPDFVTheme.redaction).frame(width: 3, height: 58)
                    Text("This is destructive by design. Affected pages become new page images, hidden objects are discarded, annotations are baked in, and the original file remains untouched.")
                        .font(.system(size: 10))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)

            if session.isSanitizingRedactions {
                VStack(alignment: .leading, spacing: 7) {
                    ProgressView().progressViewStyle(.linear)
                    Text(session.redactionStatusMessage ?? "Sanitizing pages…")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            Button {
                session.createSanitizedCopy(
                    restoresSearchableText: restoresSearchableText,
                    forbiddenTerms: forbiddenTerms
                )
            } label: {
                HStack {
                    SPDFVIconLabel(title: "Create sanitized copy", icon: .secureCopy)
                    Spacer()
                    Text(forbiddenTerms.isEmpty ? "UNVERIFIED" : "VERIFY \(forbiddenTerms.count)")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(SPDFVTheme.redaction)
            }
            .buttonStyle(.plain)
            .disabled(session.pendingRedactions.isEmpty || session.isSanitizingRedactions)
            .padding(12)
        }
        .frame(width: 344)
        .background(SPDFVTheme.navigatorInset)
    }
}

private struct RedactionRegisterRow: View {
    @ObservedObject var session: DocumentSession
    let mark: PendingRedaction

    private var pageNumber: Int {
        let index = session.document?.index(for: mark.page) ?? NSNotFound
        return index == NSNotFound ? 0 : index + 1
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(SPDFVTheme.redactionInk)
                .frame(width: 24, height: 13)
                .overlay { Rectangle().stroke(SPDFVTheme.redaction, lineWidth: 1) }
            Text("PAGE \(pageNumber) · \(Int(mark.bounds.width.rounded()))×\(Int(mark.bounds.height.rounded())) PT")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(SPDFVTheme.navigatorText)
            Spacer()
            Button {
                session.removePendingRedaction(mark.id)
            } label: {
                SPDFVIcon(.close)
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove redaction on page \(pageNumber)")
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(SPDFVTheme.navigator)
    }
}

struct OCRPanel: View {
    @ObservedObject var session: DocumentSession
    @Binding var isPresented: Bool
    @State private var scope: OCRPageScope = .all
    @State private var quality: PDFOCRRecognitionLevel = .accurate
    @State private var language: OCRLanguagePreset = .automatic

    private var scopedPageCount: Int {
        switch scope {
        case .current: 1
        case .selection: max(1, session.selectedPageIndices.count)
        case .all: session.pageCount
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("OCR")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.4)
                    Text("ON-DEVICE TEXT RECOGNITION")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
                Spacer()
                ZStack {
                    SPDFVIcon(.scanText)
                        .font(.system(size: 22, weight: .light))
                    Text("Aa")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .offset(y: 1)
                }
                .foregroundStyle(SPDFVTheme.paleCobalt)
            }
            .padding(14)

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                OCRSectionLabel(text: "SHEETS TO READ")
                HStack(spacing: 6) {
                    ForEach(OCRPageScope.allCases) { item in
                        Button {
                            scope = item
                        } label: {
                            Text(item.label)
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .foregroundStyle(scope == item ? Color.white : SPDFVTheme.navigatorText)
                                .background(scope == item ? SPDFVTheme.cobalt : Color.clear)
                                .overlay { Rectangle().stroke(SPDFVTheme.divider, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        OCRSectionLabel(text: "OUTPUT")
                        Picker("Quality", selection: $quality) {
                            Text("PROOF · ACCURATE").tag(PDFOCRRecognitionLevel.accurate)
                            Text("DRAFT · FAST").tag(PDFOCRRecognitionLevel.fast)
                        }
                        .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        OCRSectionLabel(text: "LANGUAGE")
                        Picker("Language", selection: $language) {
                            ForEach(OCRLanguagePreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .labelsHidden()
                    }
                }

                HStack(alignment: .top, spacing: 9) {
                    Rectangle()
                        .fill(SPDFVTheme.cobalt)
                        .frame(width: 3, height: 44)
                    Text("The page image stays untouched. SPDFV adds an invisible, selectable text layer to a separate PDF using Apple Vision on this Mac.")
                        .font(.system(size: 10))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)

            if session.isPerformingOCR {
                VStack(alignment: .leading, spacing: 7) {
                    ProgressView().progressViewStyle(.linear)
                    Text(session.ocrStatusMessage ?? "Reading pages…")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(SPDFVTheme.navigatorMuted)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }

            Rectangle().fill(SPDFVTheme.divider).frame(height: 1)

            Button {
                session.createSearchableCopy(
                    scope: scope,
                    quality: quality,
                    languages: language.languages
                )
                if !session.isPerformingOCR { isPresented = false }
            } label: {
                HStack {
                    SPDFVIconLabel(title: "Create searchable copy", icon: .scanText)
                    Spacer()
                    Text("\(scopedPageCount) PG")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(SPDFVTheme.cobalt)
            }
            .buttonStyle(.plain)
            .disabled(session.isPerformingOCR)
            .padding(12)
        }
        .frame(width: 326)
        .background(SPDFVTheme.navigatorInset)
    }
}

private struct OCRSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .tracking(0.9)
            .foregroundStyle(SPDFVTheme.navigatorFaint)
    }
}
