import SPDFVCore
import SwiftUI

struct SignatureVerificationSection: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        InspectorSection(title: "DIGITAL SIGNATURES") {
            if session.isVerifyingSignatures {
                InspectorMessage("Verifying PDF byte ranges, CMS signatures, and certificate trust on this Mac…")
            } else if let report = session.signatureVerificationReport {
                InspectorRow(label: "Result", value: report.status.displayLabel)
                    .accessibilityIdentifier("signatures.report")
                InspectorRow(label: "Fields", value: "\(report.signatureFieldCount)")
                InspectorRow(label: "Embedded", value: "\(report.embeddedSignatureCount)")
                if session.isDirty, report.status != .none {
                    InspectorMessage("This report covers the last saved file. Current unsaved edits will invalidate or remove its signatures when saved.")
                }
                ForEach(report.signatures) { signature in
                    SignatureVerificationRow(signature: signature)
                }
                ForEach(report.warnings, id: \.self) { warning in
                    InspectorMessage(warning)
                }
                InspectorAction(title: "VERIFY AGAIN", action: session.verifyDocumentSignatures)
            } else {
                InspectorMessage("Check signed byte ranges, detached CMS integrity, signer certificate details, trust, timestamps, and later document changes.")
                InspectorAction(title: "VERIFY SIGNATURES", action: session.verifyDocumentSignatures)
                    .accessibilityIdentifier("signatures.verify")
            }
        }
    }
}

private struct SignatureVerificationRow: View {
    let signature: PDFSignatureVerificationItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(signature.fieldName ?? signature.id)
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Text(signature.cryptographicStatus.displayLabel)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(signature.cryptographicStatus == .valid ? SPDFVTheme.paleCobalt : SPDFVTheme.redaction)
            }
            if let signer = signature.signerSummary {
                Text(signer).font(.system(size: 9, weight: .medium))
            }
            Text("TRUST \(signature.trustStatus.displayLabel.uppercased()) · COVERAGE \(signature.coverage.displayLabel.uppercased())")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
            if let timestamp = signature.authenticatedTimestamp {
                Text("Trusted timestamp: \(timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 9))
            } else if let signingTime = signature.signingTime {
                Text("Signer-supplied time: \(signingTime.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 9))
            }
            Text(signature.message)
                .font(.system(size: 9))
                .foregroundStyle(SPDFVTheme.navigatorMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let fingerprint = signature.certificateSHA256 {
                Text("SHA-256 \(fingerprint)")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(SPDFVTheme.navigatorFaint)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .overlay(alignment: .bottom) { Rectangle().fill(SPDFVTheme.divider).frame(height: 1) }
    }
}

private extension PDFSignatureOverallStatus {
    var displayLabel: String {
        switch self {
        case .none: "No signatures"
        case .validTrusted: "Valid and trusted"
        case .validUntrusted: "Valid, untrusted certificate"
        case .modifiedAfterSigning: "Valid signed revision; later changes"
        case .unsigned: "Unsigned field"
        case .invalid: "Invalid"
        case .unsupported: "Unsupported signature"
        }
    }
}

private extension PDFSignatureCryptographicStatus {
    var displayLabel: String {
        switch self {
        case .valid: "VALID"
        case .invalid: "INVALID"
        case .unsigned: "UNSIGNED"
        case .unsupported: "UNSUPPORTED"
        case .error: "ERROR"
        }
    }
}

private extension PDFSignatureTrustStatus {
    var displayLabel: String {
        switch self {
        case .trusted: "Trusted"
        case .untrusted: "Untrusted"
        case .notEvaluated: "Not evaluated"
        }
    }
}

private extension PDFSignatureCoverage {
    var displayLabel: String {
        switch self {
        case .entireFile: "Entire file"
        case .signedRevisionWithLaterChanges: "Earlier revision"
        case .invalid: "Invalid"
        }
    }
}
