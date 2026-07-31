import Vapor

struct RegisterRequest: Content {
    let email: String
    let password: String
    let displayName: String
}

extension RegisterRequest: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("email", as: String.self, is: .email)
        validations.add("password", as: String.self, is: .count(8...))
        validations.add("displayName", as: String.self, is: .count(1...50))
    }
}

struct LoginResponse: Content {
    let token: String
    let user: UserDTO
}

struct UserDTO: Content {
    let id: UUID
    let email: String
    let displayName: String

    init(_ user: User) throws {
        self.id = try user.requireID()
        self.email = user.email
        self.displayName = user.displayName
    }
}

struct UpdateProfileRequest: Content {
    let email: String?
    let displayName: String?
    let currentPassword: String?
    let newPassword: String?
}

struct ForgotPasswordRequest: Content {
    let email: String
}

struct ResetPasswordRequest: Content {
    let email: String
    let code: String
    let newPassword: String
}
