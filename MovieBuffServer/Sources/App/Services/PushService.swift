import Vapor
import Fluent
import APNSCore
import VaporAPNS

/// Best-effort push notification helper. All calls log-and-swallow failures so a broken
/// APNs configuration or an invalid device token never breaks the calling business logic.
enum PushService {
    struct SharePayload: Codable {
        let type: String      // "movie_share"
        let imdbID: String
        let shareID: String?
    }

    struct WatchPartyPayload: Codable {
        let type: String        // "watch_party_invite" | "watch_party_match"
        let partyID: String
        let imdbID: String?
    }

    static func sendWatchPartyInvite(
        recipientID: User.IDValue,
        senderDisplayName: String,
        partyID: UUID,
        on req: Request
    ) async {
        await sendGeneric(
            to: recipientID,
            title: "Watch Party invite",
            subtitle: "\(senderDisplayName) wants to pick a movie with you",
            body: nil,
            payload: WatchPartyPayload(
                type: "watch_party_invite",
                partyID: partyID.uuidString,
                imdbID: nil
            ),
            on: req
        )
    }

    static func sendWatchPartyMatch(
        recipientID: User.IDValue,
        senderDisplayName: String,
        partyID: UUID,
        imdbID: String,
        on req: Request
    ) async {
        await sendGeneric(
            to: recipientID,
            title: "It's a match!",
            subtitle: "You and \(senderDisplayName) both picked a movie",
            body: nil,
            payload: WatchPartyPayload(
                type: "watch_party_match",
                partyID: partyID.uuidString,
                imdbID: imdbID
            ),
            on: req
        )
    }

    private static func sendGeneric<P: Codable & Sendable>(
        to recipientID: User.IDValue,
        title: String,
        subtitle: String?,
        body: String?,
        payload: P,
        on req: Request
    ) async {
        guard let bundleID = Environment.get("APNS_BUNDLE_ID"), !bundleID.isEmpty else { return }
        let tokens: [DeviceToken]
        do {
            tokens = try await DeviceToken.query(on: req.db)
                .filter(\.$user.$id == recipientID)
                .filter(\.$platform == DevicePlatform.ios.rawValue)
                .all()
        } catch { return }
        for token in tokens {
            let alert = APNSAlertNotification(
                alert: APNSAlertNotificationContent(
                    title: .raw(title),
                    subtitle: subtitle.map { .raw($0) },
                    body: body.map { .raw($0) }
                ),
                expiration: .immediately,
                priority: .immediately,
                topic: bundleID,
                payload: payload,
                sound: .default
            )
            do {
                try await req.apns.client.sendAlertNotification(alert, deviceToken: token.token)
            } catch let error as APNSError where error.reason == .badDeviceToken || error.reason == .unregistered {
                try? await token.delete(on: req.db)
            } catch {
                req.logger.warning("Push send failed: \(error)")
            }
        }
    }

    static func sendShareNotification(
        recipientID: User.IDValue,
        senderDisplayName: String,
        movieTitle: String,
        message: String?,
        imdbID: String,
        shareID: UUID?,
        on req: Request
    ) async {
        guard let bundleID = Environment.get("APNS_BUNDLE_ID"), !bundleID.isEmpty else {
            req.logger.info("APNS_BUNDLE_ID not set — skipping push.")
            return
        }

        let tokens: [DeviceToken]
        do {
            tokens = try await DeviceToken.query(on: req.db)
                .filter(\.$user.$id == recipientID)
                .filter(\.$platform == DevicePlatform.ios.rawValue)
                .all()
        } catch {
            req.logger.warning("Push: failed to fetch device tokens — \(error)")
            return
        }
        guard !tokens.isEmpty else { return }

        let payload = SharePayload(
            type: "movie_share",
            imdbID: imdbID,
            shareID: shareID?.uuidString
        )

        for token in tokens {
            let alert = APNSAlertNotification(
                alert: APNSAlertNotificationContent(
                    title: .raw("\(senderDisplayName) shared a movie"),
                    subtitle: .raw(movieTitle),
                    body: (message?.isEmpty == false) ? .raw(message!) : nil
                ),
                expiration: .immediately,
                priority: .immediately,
                topic: bundleID,
                payload: payload,
                sound: .default
            )

            do {
                try await req.apns.client.sendAlertNotification(
                    alert,
                    deviceToken: token.token
                )
            } catch let error as APNSError where error.reason == .badDeviceToken || error.reason == .unregistered {
                req.logger.info("Push: pruning invalid token \(token.token.prefix(8))…")
                try? await token.delete(on: req.db)
            } catch {
                req.logger.warning("Push: send failed — \(error)")
            }
        }
    }
}
