import SwiftUI

struct ProfileView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var displayName = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var currentEmail: String { auth.user?.email ?? "" }
    private var currentDisplayName: String { auth.user?.displayName ?? "" }

    private var wantsPasswordChange: Bool {
        !newPassword.isEmpty || !confirmPassword.isEmpty || !currentPassword.isEmpty
    }
    private var passwordTooShort: Bool { !newPassword.isEmpty && newPassword.count < 8 }
    private var passwordMismatch: Bool { !confirmPassword.isEmpty && confirmPassword != newPassword }

    private var canSave: Bool {
        if isSaving { return false }
        let emailChanged = !email.isEmpty && email != currentEmail
        let nameChanged = !displayName.isEmpty && displayName != currentDisplayName
        if wantsPasswordChange {
            guard !currentPassword.isEmpty,
                  newPassword.count >= 8,
                  confirmPassword == newPassword
            else { return false }
            return true
        }
        return emailChanged || nameChanged
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    if auth.isGuest {
                        guestPromptView
                    } else {
                        signedInProfileView
                    }
                }
            }
            .navigationTitle(auth.isGuest ? "Account" : "Edit Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(auth.isGuest ? "Close" : "Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
                if !auth.isGuest {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await save() }
                        } label: {
                            if isSaving { ProgressView().tint(Theme.accent) }
                            else { Text("Save").foregroundStyle(Theme.accent) }
                        }
                        .disabled(!canSave)
                    }
                }
            }
            .onAppear {
                if email.isEmpty { email = currentEmail }
                if displayName.isEmpty { displayName = currentDisplayName }
            }
        }
    }

    private var signedInProfileView: some View {
        VStack(alignment: .leading, spacing: 22) {
            profileHeader

            section(title: "Account") {
                fieldLabel("Email")
                emailField
                fieldLabel("Display Name")
                nameField
            }

            section(title: "Change Password") {
                Text("Leave blank to keep your current password.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                fieldLabel("Current Password")
                SecureField("", text: $currentPassword,
                            prompt: Text("Current").foregroundColor(.gray))
                    .modifier(ProfileFieldStyle())
                fieldLabel("New Password (min 8)")
                SecureField("", text: $newPassword,
                            prompt: Text("New").foregroundColor(.gray))
                    .modifier(ProfileFieldStyle(highlight: passwordTooShort))
                if passwordTooShort {
                    hint("New password must be at least 8 characters.")
                }
                fieldLabel("Confirm New Password")
                SecureField("", text: $confirmPassword,
                            prompt: Text("Confirm").foregroundColor(.gray))
                    .modifier(ProfileFieldStyle(highlight: passwordMismatch))
                if passwordMismatch {
                    hint("Passwords do not match.")
                }
            }

            if let successMessage {
                banner(text: successMessage, color: .green)
            }
            if let errorMessage {
                banner(text: errorMessage, color: .red)
            }

            signOutButton
                .padding(.top, 8)
        }
        .padding()
    }

    private var guestPromptView: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 64))
                .foregroundStyle(Theme.gold)
                .padding(.top, 32)
            Text("You're browsing as a guest")
                .font(.sectionTitle)
                .foregroundStyle(.white)
            Text("Create an account to save movies, add friends, and post comments.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                Task {
                    auth.exitGuestMode()
                    dismiss()
                }
            } label: {
                Text("Sign In or Create Account")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [Theme.gold, Theme.goldSoft],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var profileHeader: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(LinearGradient(
                    colors: [Theme.gold, Theme.goldSoft],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 76, height: 76)
                .overlay(
                    Text(initials)
                        .font(.title.weight(.black))
                        .foregroundStyle(.black)
                )
                .shadow(color: Theme.gold.opacity(0.35), radius: 12, y: 4)
            Text(currentDisplayName.isEmpty ? currentEmail : currentDisplayName)
                .font(.sectionTitle)
                .foregroundStyle(.white)
            Text(currentEmail)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var initials: String {
        let source = currentDisplayName.isEmpty ? currentEmail : currentDisplayName
        let parts = source.split(separator: " ")
        if let first = parts.first, let ch = first.first {
            if parts.count > 1, let second = parts[1].first {
                return String([ch, second]).uppercased()
            }
            return String(ch).uppercased()
        }
        return "?"
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            Task {
                await auth.logout()
                dismiss()
            }
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out").font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
    }

    private var emailField: some View {
        TextField("", text: $email, prompt: Text(currentEmail).foregroundColor(.gray))
            .textContentType(.emailAddress)
            #if os(iOS)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .modifier(ProfileFieldStyle())
    }

    private var nameField: some View {
        TextField("", text: $displayName,
                  prompt: Text(currentDisplayName).foregroundColor(.gray))
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .modifier(ProfileFieldStyle())
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.sectionTitle)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func banner(text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        successMessage = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        let emailChanged = trimmedEmail != currentEmail
        let nameChanged = trimmedName != currentDisplayName

        do {
            try await auth.updateProfile(
                email: emailChanged ? trimmedEmail : nil,
                displayName: nameChanged ? trimmedName : nil,
                currentPassword: wantsPasswordChange ? currentPassword : nil,
                newPassword: wantsPasswordChange ? newPassword : nil
            )
            successMessage = "Profile updated."
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProfileFieldStyle: ViewModifier {
    var highlight: Bool = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(highlight ? Color.red.opacity(0.7) : Color.clear, lineWidth: 1)
            )
    }
}

struct PasswordResetSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    enum Step { case email, code }

    @State private var step: Step = .email
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch step {
                        case .email: emailStep
                        case .code:  codeStep
                        }

                        if let infoMessage {
                            banner(text: infoMessage, color: .green)
                        }
                        if let errorMessage {
                            banner(text: errorMessage, color: .red)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Reset Password")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter the email associated with your account. We'll send you a 6-digit code.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))

            TextField("", text: $email,
                      prompt: Text("you@example.com").foregroundColor(.gray))
                .textContentType(.emailAddress)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .modifier(ProfileFieldStyle())

            Button {
                Task { await requestCode() }
            } label: {
                buttonLabel(title: "Send Code", loading: isSubmitting)
            }
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("If \(email) has an account, you'll receive a 6-digit code. Enter it below along with your new password.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))

            TextField("", text: $code,
                      prompt: Text("6-digit code").foregroundColor(.gray))
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                #endif
                .modifier(ProfileFieldStyle())

            SecureField("", text: $newPassword,
                        prompt: Text("New password (min 8)").foregroundColor(.gray))
                .modifier(ProfileFieldStyle(
                    highlight: !newPassword.isEmpty && newPassword.count < 8
                ))
            SecureField("", text: $confirmPassword,
                        prompt: Text("Confirm new password").foregroundColor(.gray))
                .modifier(ProfileFieldStyle(
                    highlight: !confirmPassword.isEmpty && confirmPassword != newPassword
                ))

            Button {
                Task { await submitReset() }
            } label: {
                buttonLabel(title: "Reset Password", loading: isSubmitting)
            }
            .disabled(!canSubmitReset || isSubmitting)

            Button("Use a different email") {
                step = .email
                code = ""
                newPassword = ""
                confirmPassword = ""
                infoMessage = nil
                errorMessage = nil
            }
            .font(.footnote)
            .foregroundStyle(.yellow)
            .padding(.top, 4)
        }
    }

    private var canSubmitReset: Bool {
        code.count >= 4 && newPassword.count >= 8 && confirmPassword == newPassword
    }

    private func buttonLabel(title: String, loading: Bool) -> some View {
        HStack {
            if loading { ProgressView().tint(.black) }
            Text(title).font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(.black)
    }

    private func banner(text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func requestCode() async {
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        infoMessage = nil
        do {
            try await auth.forgotPassword(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
            infoMessage = "If that email is registered, a code has been sent. Check your inbox."
            step = .code
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitReset() async {
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        infoMessage = nil
        do {
            try await auth.resetPassword(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                code: code.trimmingCharacters(in: .whitespaces),
                newPassword: newPassword
            )
            infoMessage = "Password updated. You can now sign in."
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
