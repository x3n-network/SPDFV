import CryptoKit
import Foundation
import PDFKit
import Security

public extension PDFOperations {
    /// Verifies embedded detached CMS signatures against their declared PDF
    /// byte ranges, then evaluates the signer certificate chain with macOS.
    static func verifySignatures(in data: Data) -> PDFSignatureVerificationReport {
        let fieldNames: [String]
        if let document = PDFDocument(data: data), !document.isLocked {
            fieldNames = safetyGate(for: document).certificateSignatureFields
        } else {
            fieldNames = []
        }
        let containers = signatureContainers(in: data)
        var items = containers.enumerated().map { index, container in
            verifySignature(
                container,
                pdfData: data,
                fieldName: containers.count == 1 && fieldNames.count == 1 ? fieldNames[0] : nil,
                index: index
            )
        }
        if fieldNames.count > containers.count {
            for offset in 0..<(fieldNames.count - containers.count) {
                let fieldName = containers.isEmpty ? fieldNames[offset] : nil
                items.append(PDFSignatureVerificationItem(
                    id: fieldName.map { "field:\($0)" } ?? "unsigned-field-\(offset + 1)",
                    fieldName: fieldName,
                    subFilter: nil,
                    cryptographicStatus: .unsigned,
                    trustStatus: .notEvaluated,
                    coverage: .invalid,
                    signedByteCount: 0,
                    unsignedTrailingByteCount: data.count,
                    signerSummary: nil,
                    certificateSHA256: nil,
                    certificateChainLength: nil,
                    signingTime: nil,
                    authenticatedTimestamp: nil,
                    message: "The signature field does not contain an embedded signature."
                ))
            }
        }

        var warnings: [String] = []
        if !containers.isEmpty, !(containers.count == 1 && fieldNames.count == 1) {
            warnings.append("Embedded signatures could not be matched reliably to every PDF field name.")
        }
        if items.contains(where: { $0.authenticatedTimestamp == nil && $0.signingTime != nil }) {
            warnings.append("A signing time without a trusted timestamp is signer-supplied and is not proof of when the PDF was signed.")
        }
        return PDFSignatureVerificationReport(
            status: overallSignatureStatus(items),
            signatureFieldCount: fieldNames.count,
            embeddedSignatureCount: containers.count,
            verifiedAt: Date(),
            signatures: items,
            warnings: warnings
        )
    }
}

private extension PDFOperations {
    struct SignatureContainer {
        let byteRanges: [Range<Int>]?
        let contents: Data?
        let contentsTokenRange: Range<Int>?
        let subFilter: String?
        let parseError: String?
    }

    static func signatureContainers(in data: Data) -> [SignatureContainer] {
        let bytes = Array(data)
        let marker = Array("/ByteRange".utf8)
        var containers: [SignatureContainer] = []
        var searchStart = 0
        while let markerRange = bytes.signatureFirstRange(of: marker, after: searchStart) {
            searchStart = markerRange.upperBound
            let objectStart = bytes.signatureObjectStart(before: markerRange.lowerBound) ?? markerRange.lowerBound
            let objectEnd = bytes.signatureFirstRange(of: Array("endobj".utf8), after: markerRange.upperBound)?.lowerBound ?? bytes.count
            let objectRange = objectStart..<objectEnd
            do {
                let ranges = try parseByteRanges(bytes, after: markerRange.upperBound)
                let contents = try parseSignatureContents(bytes, within: objectRange)
                containers.append(SignatureContainer(
                    byteRanges: ranges,
                    contents: contents.data,
                    contentsTokenRange: contents.range,
                    subFilter: parsePDFName(bytes, marker: "/SubFilter", within: objectRange),
                    parseError: nil
                ))
            } catch {
                containers.append(SignatureContainer(
                    byteRanges: nil,
                    contents: nil,
                    contentsTokenRange: nil,
                    subFilter: parsePDFName(bytes, marker: "/SubFilter", within: objectRange),
                    parseError: (error as? PDFOperationError)?.description ?? error.localizedDescription
                ))
            }
        }
        return containers
    }

    static func verifySignature(
        _ container: SignatureContainer,
        pdfData: Data,
        fieldName: String?,
        index: Int
    ) -> PDFSignatureVerificationItem {
        let base = SignatureItemBuilder(id: "signature-\(index + 1)", fieldName: fieldName, subFilter: container.subFilter)
        if let parseError = container.parseError {
            return base.item(cryptographic: .error, coverage: .invalid, message: parseError)
        }
        let supportedSubFilters = ["adbe.pkcs7.detached", "ETSI.CAdES.detached"]
        guard let subFilter = container.subFilter, supportedSubFilters.contains(subFilter) else {
            return base.item(
                cryptographic: .unsupported,
                coverage: .invalid,
                message: "This PDF signature SubFilter is not supported for detached CMS verification."
            )
        }
        guard let ranges = container.byteRanges,
              let contents = container.contents,
              let contentsRange = container.contentsTokenRange else {
            return base.item(cryptographic: .unsupported, coverage: .invalid, message: "The signature container is incomplete.")
        }
        guard rangesAreValid(ranges, dataCount: pdfData.count),
              ranges.first?.lowerBound == 0,
              ranges.contains(where: { $0.upperBound <= contentsRange.lowerBound }),
              ranges.contains(where: { $0.lowerBound >= contentsRange.upperBound }),
              !ranges.contains(where: { $0.overlaps(contentsRange) }) else {
            return base.item(cryptographic: .invalid, coverage: .invalid, message: "The PDF signature ByteRange is invalid.")
        }

        var signedData = Data()
        for range in ranges { signedData.append(pdfData.subdata(in: range)) }
        let finalSignedOffset = ranges.last?.upperBound ?? 0
        let trailing = max(0, pdfData.count - finalSignedOffset)
        let coverage: PDFSignatureCoverage = trailing == 0 ? .entireFile : .signedRevisionWithLaterChanges
        let cmsData = trimmedDER(contents)
        guard !cmsData.isEmpty else {
            return base.item(cryptographic: .unsigned, coverage: coverage, signedBytes: signedData.count, trailing: trailing, message: "The signature Contents value is empty.")
        }

        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else {
            return base.item(cryptographic: .error, coverage: coverage, signedBytes: signedData.count, trailing: trailing, message: "macOS could not initialize CMS verification.")
        }
        let updateStatus = cmsData.withUnsafeBytes { buffer in
            CMSDecoderUpdateMessage(decoder, buffer.baseAddress!, buffer.count)
        }
        guard updateStatus == errSecSuccess,
              CMSDecoderSetDetachedContent(decoder, signedData as CFData) == errSecSuccess,
              CMSDecoderFinalizeMessage(decoder) == errSecSuccess else {
            return base.item(cryptographic: .unsupported, coverage: coverage, signedBytes: signedData.count, trailing: trailing, message: "The embedded signature is not a supported detached CMS message.")
        }
        var signerCount = 0
        guard CMSDecoderGetNumSigners(decoder, &signerCount) == errSecSuccess, signerCount > 0 else {
            return base.item(cryptographic: .unsigned, coverage: coverage, signedBytes: signedData.count, trailing: trailing, message: "The CMS container does not contain a signer.")
        }
        guard signerCount == 1 else {
            return base.item(cryptographic: .unsupported, coverage: coverage, signedBytes: signedData.count, trailing: trailing, message: "CMS containers with multiple signers are not yet supported.")
        }

        var signingTime: CFAbsoluteTime = 0
        let hasSigningTime = CMSDecoderCopySignerSigningTime(decoder, 0, &signingTime) == errSecSuccess
        var timestamp: CFAbsoluteTime = 0
        let hasTimestamp = CMSDecoderCopySignerTimestamp(decoder, 0, &timestamp) == errSecSuccess
        let policy = SecPolicyCreateBasicX509()
        var signerStatus: CMSSignerStatus = .unsigned
        var trust: SecTrust?
        var certificateStatus: OSStatus = errSecSuccess
        let signerCall = CMSDecoderCopySignerStatus(
            decoder, 0, policy, false, &signerStatus, &trust, &certificateStatus
        )
        guard signerCall == errSecSuccess else {
            return base.item(cryptographic: .error, coverage: coverage, signedBytes: signedData.count, trailing: trailing, signingTime: hasSigningTime ? Date(timeIntervalSinceReferenceDate: signingTime) : nil, timestamp: hasTimestamp ? Date(timeIntervalSinceReferenceDate: timestamp) : nil, message: securityMessage(signerCall, fallback: "CMS signer verification failed."))
        }

        var certificate: SecCertificate?
        _ = CMSDecoderCopySignerCert(decoder, 0, &certificate)
        let certificateDetails = certificate.map(signatureCertificateDetails) ?? (nil, nil)
        let chainLength = trust.flatMap { SecTrustCopyCertificateChain($0) as? [SecCertificate] }?.count
        let cryptographic: PDFSignatureCryptographicStatus
        switch signerStatus {
        case .valid, .invalidCert: cryptographic = .valid
        case .invalidSignature: cryptographic = .invalid
        case .unsigned: cryptographic = .unsigned
        case .needsDetachedContent, .invalidIndex: cryptographic = .error
        @unknown default: cryptographic = .error
        }

        var trustStatus: PDFSignatureTrustStatus = .notEvaluated
        var trustMessage: String?
        if cryptographic == .valid, let trust {
            if hasTimestamp { SecTrustSetVerifyDate(trust, Date(timeIntervalSinceReferenceDate: timestamp) as CFDate) }
            var trustError: CFError?
            if SecTrustEvaluateWithError(trust, &trustError) {
                trustStatus = .trusted
            } else {
                trustStatus = .untrusted
                trustMessage = (trustError as Error?)?.localizedDescription
            }
        }
        let message: String
        if cryptographic == .invalid {
            message = "The signed byte ranges do not match the embedded cryptographic signature."
        } else if cryptographic != .valid {
            message = "The CMS signer could not be verified."
        } else if coverage == .signedRevisionWithLaterChanges {
            message = "The signature is cryptographically valid for an earlier revision; later PDF bytes are not covered."
        } else if trustStatus == .trusted {
            message = "The signature bytes and current certificate trust evaluation are valid."
        } else {
            message = trustMessage.map { "The signature bytes are valid, but certificate trust failed: \($0)" }
                ?? "The signature bytes are valid, but the certificate is not trusted."
        }
        return base.item(
            cryptographic: cryptographic,
            trust: trustStatus,
            coverage: coverage,
            signedBytes: signedData.count,
            trailing: trailing,
            signer: certificateDetails.0,
            fingerprint: certificateDetails.1,
            chainLength: chainLength,
            signingTime: hasSigningTime ? Date(timeIntervalSinceReferenceDate: signingTime) : nil,
            timestamp: hasTimestamp ? Date(timeIntervalSinceReferenceDate: timestamp) : nil,
            message: message
        )
    }

    struct SignatureItemBuilder {
        let id: String
        let fieldName: String?
        let subFilter: String?

        func item(
            cryptographic: PDFSignatureCryptographicStatus,
            trust: PDFSignatureTrustStatus = .notEvaluated,
            coverage: PDFSignatureCoverage,
            signedBytes: Int = 0,
            trailing: Int = 0,
            signer: String? = nil,
            fingerprint: String? = nil,
            chainLength: Int? = nil,
            signingTime: Date? = nil,
            timestamp: Date? = nil,
            message: String
        ) -> PDFSignatureVerificationItem {
            PDFSignatureVerificationItem(
                id: id,
                fieldName: fieldName,
                subFilter: subFilter,
                cryptographicStatus: cryptographic,
                trustStatus: trust,
                coverage: coverage,
                signedByteCount: signedBytes,
                unsignedTrailingByteCount: trailing,
                signerSummary: signer,
                certificateSHA256: fingerprint,
                certificateChainLength: chainLength,
                signingTime: signingTime,
                authenticatedTimestamp: timestamp,
                message: message
            )
        }
    }

    static func overallSignatureStatus(_ items: [PDFSignatureVerificationItem]) -> PDFSignatureOverallStatus {
        guard !items.isEmpty else { return .none }
        if items.contains(where: { $0.cryptographicStatus == .invalid || $0.cryptographicStatus == .error }) { return .invalid }
        if items.contains(where: { $0.cryptographicStatus == .unsupported }) { return .unsupported }
        if items.contains(where: { $0.cryptographicStatus == .unsigned }) { return .unsigned }
        if items.contains(where: { $0.coverage == .signedRevisionWithLaterChanges }) { return .modifiedAfterSigning }
        if items.allSatisfy({ $0.trustStatus == .trusted }) { return .validTrusted }
        return .validUntrusted
    }

    static func signatureCertificateDetails(_ certificate: SecCertificate) -> (String?, String?) {
        let summary = SecCertificateCopySubjectSummary(certificate) as String?
        let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")
        return (summary, digest)
    }

    static func securityMessage(_ status: OSStatus, fallback: String) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? fallback
    }

    static func rangesAreValid(_ ranges: [Range<Int>], dataCount: Int) -> Bool {
        guard ranges.count >= 2 else { return false }
        var previousEnd = 0
        for range in ranges {
            guard range.lowerBound >= previousEnd, range.lowerBound >= 0, range.upperBound <= dataCount else { return false }
            previousEnd = range.upperBound
        }
        return true
    }

    static func parseByteRanges(_ bytes: [UInt8], after markerEnd: Int) throws -> [Range<Int>] {
        var cursor = markerEnd
        while cursor < bytes.count, bytes[cursor].signatureWhitespace { cursor += 1 }
        guard cursor < bytes.count, bytes[cursor] == 0x5B else {
            throw PDFOperationError.invalidInput("Signature ByteRange is not an array")
        }
        cursor += 1
        var values: [Int] = []
        var closed = false
        while cursor < bytes.count {
            while cursor < bytes.count, bytes[cursor].signatureWhitespace { cursor += 1 }
            if cursor < bytes.count, bytes[cursor] == 0x5D {
                closed = true
                break
            }
            let start = cursor
            while cursor < bytes.count, bytes[cursor] >= 0x30, bytes[cursor] <= 0x39 { cursor += 1 }
            guard cursor > start, let value = Int(String(decoding: bytes[start..<cursor], as: UTF8.self)) else {
                throw PDFOperationError.invalidInput("Signature ByteRange contains a non-integer value")
            }
            values.append(value)
        }
        guard closed, values.count >= 4, values.count.isMultiple(of: 2) else {
            throw PDFOperationError.invalidInput("Signature ByteRange must contain offset-length pairs")
        }
        var ranges: [Range<Int>] = []
        for index in stride(from: 0, to: values.count, by: 2) {
            let (start, length) = (values[index], values[index + 1])
            guard length >= 0, start <= Int.max - length else {
                throw PDFOperationError.invalidInput("Signature ByteRange contains an invalid offset or length")
            }
            ranges.append(start..<(start + length))
        }
        return ranges
    }

    static func parseSignatureContents(_ bytes: [UInt8], within objectRange: Range<Int>) throws -> (data: Data, range: Range<Int>) {
        let marker = Array("/Contents".utf8)
        guard let markerRange = bytes.signatureFirstRange(of: marker, after: objectRange.lowerBound), markerRange.lowerBound < objectRange.upperBound else {
            throw PDFOperationError.invalidInput("Signature dictionary does not contain Contents")
        }
        var cursor = markerRange.upperBound
        while cursor < objectRange.upperBound, bytes[cursor].signatureWhitespace { cursor += 1 }
        guard cursor < objectRange.upperBound, bytes[cursor] == 0x3C,
              cursor + 1 >= objectRange.upperBound || bytes[cursor + 1] != 0x3C else {
            throw PDFOperationError.invalidInput("Only hexadecimal PDF signature Contents are supported")
        }
        let tokenStart = cursor
        cursor += 1
        var nibbles: [UInt8] = []
        while cursor < objectRange.upperBound, bytes[cursor] != 0x3E {
            if !bytes[cursor].signatureWhitespace {
                guard let nibble = bytes[cursor].hexNibble else {
                    throw PDFOperationError.invalidInput("Signature Contents contains invalid hexadecimal data")
                }
                nibbles.append(nibble)
            }
            cursor += 1
        }
        guard cursor < objectRange.upperBound, nibbles.count.isMultiple(of: 2) else {
            throw PDFOperationError.invalidInput("Signature Contents is truncated")
        }
        var decoded: [UInt8] = []
        decoded.reserveCapacity(nibbles.count / 2)
        for index in stride(from: 0, to: nibbles.count, by: 2) {
            decoded.append((nibbles[index] << 4) | nibbles[index + 1])
        }
        return (Data(decoded), tokenStart..<(cursor + 1))
    }

    static func parsePDFName(_ bytes: [UInt8], marker: String, within range: Range<Int>) -> String? {
        guard let markerRange = bytes.signatureFirstRange(of: Array(marker.utf8), after: range.lowerBound), markerRange.lowerBound < range.upperBound else { return nil }
        var cursor = markerRange.upperBound
        while cursor < range.upperBound, bytes[cursor].signatureWhitespace { cursor += 1 }
        guard cursor < range.upperBound, bytes[cursor] == 0x2F else { return nil }
        cursor += 1
        let start = cursor
        while cursor < range.upperBound, !bytes[cursor].signatureWhitespace, ![0x2F, 0x3E, 0x5D].contains(bytes[cursor]) { cursor += 1 }
        return cursor > start ? String(decoding: bytes[start..<cursor], as: UTF8.self) : nil
    }

    static func trimmedDER(_ data: Data) -> Data {
        let bytes = Array(data)
        guard bytes.count >= 2, bytes[0] == 0x30 else { return data }
        let contentLength: Int
        let headerLength: Int
        if bytes[1] & 0x80 == 0 {
            contentLength = Int(bytes[1])
            headerLength = 2
        } else {
            let lengthBytes = Int(bytes[1] & 0x7F)
            guard (1...4).contains(lengthBytes), bytes.count >= 2 + lengthBytes else { return data }
            contentLength = bytes[2..<(2 + lengthBytes)].reduce(0) { ($0 << 8) | Int($1) }
            headerLength = 2 + lengthBytes
        }
        let total = headerLength + contentLength
        guard total <= bytes.count else { return data }
        return Data(bytes.prefix(total))
    }
}

private extension Array where Element == UInt8 {
    func signatureFirstRange(of needle: [UInt8], after lowerBound: Int) -> Range<Int>? {
        guard !needle.isEmpty, lowerBound <= count - needle.count else { return nil }
        for start in lowerBound...(count - needle.count) where self[start..<(start + needle.count)].elementsEqual(needle) {
            return start..<(start + needle.count)
        }
        return nil
    }

    func signatureObjectStart(before upperBound: Int) -> Int? {
        let marker = Array(" obj".utf8)
        guard upperBound >= marker.count else { return nil }
        for start in stride(from: upperBound - marker.count, through: 0, by: -1)
            where self[start..<(start + marker.count)].elementsEqual(marker) {
            var lineStart = start
            while lineStart > 0, self[lineStart - 1] != 0x0A, self[lineStart - 1] != 0x0D { lineStart -= 1 }
            let prefix = String(decoding: self[lineStart..<start], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
            if prefix.count == 2, prefix.allSatisfy({ Int($0) != nil }) { return lineStart }
        }
        return nil
    }
}

private extension UInt8 {
    var signatureWhitespace: Bool { self == 0 || self == 0x09 || self == 0x0A || self == 0x0C || self == 0x0D || self == 0x20 }

    var hexNibble: UInt8? {
        switch self {
        case 0x30...0x39: self - 0x30
        case 0x41...0x46: self - 0x41 + 10
        case 0x61...0x66: self - 0x61 + 10
        default: nil
        }
    }
}
