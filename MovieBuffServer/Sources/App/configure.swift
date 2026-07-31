import Vapor
import Fluent
import FluentSQLiteDriver
import APNS
import APNSCore
import VaporAPNS
import Crypto

public func configure(_ app: Application) async throws {
    app.databases.use(.sqlite(.file("moviebuff.sqlite")), as: .sqlite)

    app.migrations.add(CreateUser())
    app.migrations.add(CreateUserToken())
    app.migrations.add(CreateSavedMovie())
    app.migrations.add(CreateFriendship())
    app.migrations.add(CreateSharedMovie())
    app.migrations.add(CreateDeviceToken())
    app.migrations.add(CreatePasswordResetToken())
    app.migrations.add(CreateWatchParty())
    app.migrations.add(CreateComment())
    app.migrations.add(EnhanceComments())
    app.migrations.add(AddCommentSpoilerFlag())

    if app.environment != .production {
        try await app.autoMigrate()
    }

    app.routes.defaultMaxBodySize = "1mb"

    // Bind to all interfaces so devices on the same LAN (phones, etc.) can reach the server.
    // Override with `--hostname` / `--port` CLI flags if needed.
    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = 8080

    try configureAPNS(app)
    try routes(app)
}

private func configureAPNS(_ app: Application) throws {
    guard
        let keyID = Environment.get("APNS_KEY_ID"),
        let teamID = Environment.get("APNS_TEAM_ID"),
        let keyPath = Environment.get("APNS_KEY_PATH")
    else {
        app.logger.info("APNs not configured (missing APNS_KEY_ID / APNS_TEAM_ID / APNS_KEY_PATH) — push notifications disabled.")
        return
    }

    do {
        let pem = try String(contentsOfFile: keyPath, encoding: .utf8)
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)

        let isProduction = Environment.get("APNS_ENVIRONMENT")?.lowercased() == "production"

        let apnsConfig = APNSClientConfiguration(
            authenticationMethod: .jwt(
                privateKey: privateKey,
                keyIdentifier: keyID,
                teamIdentifier: teamID
            ),
            environment: isProduction ? .production : .development
        )

        app.apns.containers.use(
            apnsConfig,
            eventLoopGroupProvider: .shared(app.eventLoopGroup),
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder(),
            as: .default
        )
        app.logger.info("APNs configured (\(isProduction ? "production" : "development")).")
    } catch {
        app.logger.warning("Failed to configure APNs — push notifications disabled. \(error)")
    }
}
