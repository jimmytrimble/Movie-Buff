import Vapor

struct RegisterDeviceTokenRequest: Content {
    let token: String
    let platform: String  // "ios" for now
}

extension RegisterDeviceTokenRequest: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("token", as: String.self, is: .count(1...))
        validations.add("platform", as: String.self, is: .in("ios", "android"))
    }
}
