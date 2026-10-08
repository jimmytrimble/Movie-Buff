import Foundation
import Vapor
import AppStoreServerLibrary

/// A verified App Store transaction, normalized so callers don't depend on which
/// path (Apple-verified vs. local decode) produced it.
struct DecodedTransaction: Sendable {
    let originalTransactionId: String?
    let productId: String?
    let expiresDate: Date?
    let revocationDate: Date?
}

/// Validates App Store JWS transactions and server notifications against Apple's
/// certificate chain, using Apple's `AppStoreServerLibrary`.
///
/// Configuration (environment variables):
///   - `APNS_BUNDLE_ID`         The app's bundle id (default: `JJ.Movie-Buff`).
///   - `APPLE_APP_APPLE_ID`      The app's numeric App Store id. Required to verify
///                               *production* transactions; sandbox works without it.
///   - `APPLE_IAP_ONLINE_CHECKS` `"true"` to enable OCSP revocation + expiry checks.
///   - `APPLE_IAP_ALLOW_UNVERIFIED` `"true"` disables signature verification and
///                               decodes the payload directly. ONLY for local Xcode
///                               StoreKit testing, whose transactions are signed by a
///                               local test certificate Apple's root can't validate.
///                               Never enable this in production.
struct AppleIAPService {
    /// Ordered production-first, then sandbox. A verifier rejects transactions whose
    /// environment doesn't match, so we try each and take the first that validates.
    private let verifiers: [SignedDataVerifier]
    private let allowUnverified: Bool

    static func make(_ req: Request) throws -> AppleIAPService {
        try make(logger: req.logger)
    }

    static func make(logger: Logger) throws -> AppleIAPService {
        let allowUnverified = Environment.get("APPLE_IAP_ALLOW_UNVERIFIED")?.lowercased() == "true"
        if allowUnverified {
            logger.warning("APPLE_IAP_ALLOW_UNVERIFIED=true — App Store signatures are NOT verified. Use only for local testing.")
            return AppleIAPService(verifiers: [], allowUnverified: true)
        }

        let bundleId = Environment.get("APNS_BUNDLE_ID") ?? "JJ.Movie-Buff"
        let appAppleId = Environment.get("APPLE_APP_APPLE_ID").flatMap { Int64($0) }
        let onlineChecks = Environment.get("APPLE_IAP_ONLINE_CHECKS")?.lowercased() == "true"
        let rootCerts = try loadRootCertificates()

        var verifiers: [SignedDataVerifier] = []
        if let appAppleId {
            verifiers.append(try SignedDataVerifier(
                rootCertificates: rootCerts, bundleId: bundleId, appAppleId: appAppleId,
                environment: .production, enableOnlineChecks: onlineChecks
            ))
        } else {
            logger.warning("APPLE_APP_APPLE_ID not set — production IAP verification disabled (sandbox only).")
        }
        verifiers.append(try SignedDataVerifier(
            rootCertificates: rootCerts, bundleId: bundleId, appAppleId: appAppleId,
            environment: .sandbox, enableOnlineChecks: onlineChecks
        ))

        return AppleIAPService(verifiers: verifiers, allowUnverified: false)
    }

    // MARK: - Verification

    func verifyTransaction(_ jws: String) async throws -> DecodedTransaction {
        if allowUnverified {
            return try Self.decodeUnverified(jws)
        }
        guard !verifiers.isEmpty else {
            throw Abort(.internalServerError, reason: "App Store verification isn't configured.")
        }
        var lastError: VerificationError?
        for verifier in verifiers {
            switch await verifier.verifyAndDecodeTransaction(signedTransaction: jws) {
            case .valid(let p):
                return DecodedTransaction(
                    originalTransactionId: p.originalTransactionId,
                    productId: p.productId,
                    expiresDate: p.expiresDate,
                    revocationDate: p.revocationDate
                )
            case .invalid(let error):
                lastError = error
            }
        }
        throw Abort(.badRequest, reason: "Transaction failed App Store verification: \(String(describing: lastError))")
    }

    func verifyNotification(_ signedPayload: String) async throws -> ResponseBodyV2DecodedPayload {
        guard !verifiers.isEmpty else {
            throw Abort(.internalServerError, reason: "App Store verification isn't configured.")
        }
        var lastError: VerificationError?
        for verifier in verifiers {
            switch await verifier.verifyAndDecodeNotification(signedPayload: signedPayload) {
            case .valid(let p): return p
            case .invalid(let error): lastError = error
            }
        }
        throw Abort(.badRequest, reason: "Notification failed App Store verification: \(String(describing: lastError))")
    }

    // MARK: - Root certificate

    private static func loadRootCertificates() throws -> [Data] {
        let candidates = [
            Bundle.module.url(forResource: "AppleRootCA-G3", withExtension: "cer"),
            Bundle.module.url(forResource: "AppleRootCA-G3", withExtension: "cer", subdirectory: "Certs"),
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            throw Abort(.internalServerError, reason: "Apple root certificate resource missing from bundle.")
        }
        return [try Data(contentsOf: url)]
    }

    // MARK: - Insecure local fallback (Xcode StoreKit testing only)

    private struct RawPayload: Decodable {
        let originalTransactionId: String?
        let productId: String?
        let expiresDate: Int64?    // ms since epoch
        let revocationDate: Int64?
    }

    private static func decodeUnverified(_ jws: String) throws -> DecodedTransaction {
        let parts = jws.split(separator: ".")
        guard parts.count == 3, let data = Data(base64URLEncoded: String(parts[1])) else {
            throw Abort(.badRequest, reason: "Malformed signed transaction (expected 3 JWS segments).")
        }
        let raw = try JSONDecoder().decode(RawPayload.self, from: data)
        return DecodedTransaction(
            originalTransactionId: raw.originalTransactionId,
            productId: raw.productId,
            expiresDate: raw.expiresDate.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000.0) },
            revocationDate: raw.revocationDate.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000.0) }
        )
    }
}

private extension Data {
    /// Decodes a base64url string (JWT segments use `-`/`_` and drop padding).
    init?(base64URLEncoded input: String) {
        var s = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = s.count % 4
        if pad > 0 { s += String(repeating: "=", count: 4 - pad) }
        guard let data = Data(base64Encoded: s) else { return nil }
        self = data
    }
}
