import Vapor

func routes(_ app: Application) throws {
    app.get("health") { _ in
        HealthResponse(status: "ok")
    }

    try app.register(collection: AuthController())
    try app.register(collection: MovieController())
    try app.register(collection: FriendController())
    try app.register(collection: DeviceTokenController())
    try app.register(collection: WatchPartyController())
    try app.register(collection: ReelsController())
    try app.register(collection: CommentController())
}

struct HealthResponse: Content {
    let status: String
}
