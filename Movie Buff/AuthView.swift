import SwiftUI

struct AuthView: View {
    @Environment(AuthStore.self) private var auth

    @State private var isRegistering = false
    @State private var loginIdentifier = ""
    @State private var email = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showingResetSheet = false

    private var passwordTooShort: Bool { !password.isEmpty && password.count < 8 }
    private var passwordMismatch: Bool {
        isRegistering && !confirmPassword.isEmpty && confirmPassword != password
    }
    private var canSubmit: Bool {
        guard password.count >= 8 else { return false }
        if isRegistering {
            guard !email.isEmpty, !trimmedDisplayName.isEmpty,
                  confirmPassword == password else { return false }
        } else {
            guard !loginIdentifier.isEmpty else { return false }
        }
        return true
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.06, blue: 0.03),
                    Color(red: 0.02, green: 0.02, blue: 0.02)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // Soft gold halo behind the hero image
            RadialGradient(
                colors: [Theme.gold.opacity(0.22), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 380
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    header
                    fields
                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    actions
                    Spacer(minLength: 40)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            Image("MovieBuffHome")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 240)
                .shadow(color: Theme.gold.opacity(0.35), radius: 24, y: 6)

            VStack(spacing: 6) {
                Text(isRegistering ? "JOIN THE SHOW" : "WELCOME BACK")
                    .font(.marqueeLabel)
                    .foregroundStyle(Theme.gold)
                    .tracking(4)
                Text(isRegistering ? "Create your account" : "Sign in to continue")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.top, 40)
    }

    private var fields: some View {
        VStack(spacing: 16) {
            if isRegistering {
                label("Email")
                TextField("", text: $email,
                          prompt: Text("you@example.com").foregroundColor(.gray))
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .modifier(FieldStyle())

                label("Display Name")
                TextField("", text: $displayName,
                          prompt: Text("moviebuff42").foregroundColor(.gray))
                    .textContentType(.username)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .modifier(FieldStyle())
            } else {
                label("Email or Display Name")
                TextField("", text: $loginIdentifier,
                          prompt: Text("you@example.com or moviebuff42").foregroundColor(.gray))
                    .textContentType(.username)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .modifier(FieldStyle())
            }

            label("Password (min 8 characters)")
            SecureField("", text: $password,
                        prompt: Text("••••••••").foregroundColor(.gray))
                .textContentType(isRegistering ? .newPassword : .password)
                .modifier(FieldStyle(highlightError: passwordTooShort))
            if passwordTooShort {
                hint("Password must be at least 8 characters.")
            }

            if isRegistering {
                label("Confirm Password")
                SecureField("", text: $confirmPassword,
                            prompt: Text("••••••••").foregroundColor(.gray))
                    .textContentType(.newPassword)
                    .modifier(FieldStyle(highlightError: passwordMismatch))
                if passwordMismatch {
                    hint("Passwords do not match.")
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if auth.isLoading { ProgressView().tint(.black) }
                    Text(isRegistering ? "Create Account" : "Sign In")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [Theme.gold, Theme.goldSoft],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .opacity(canSubmit ? 1 : 0.5)
            }
            .disabled(!canSubmit || auth.isLoading)

            Button {
                withAnimation {
                    isRegistering.toggle()
                    confirmPassword = ""
                }
            } label: {
                Text(isRegistering
                     ? "Already have an account? Sign in"
                     : "New here? Create an account")
                    .font(.subheadline)
                    .foregroundStyle(Theme.gold)
            }

            if !isRegistering {
                Button("Forgot password?") {
                    showingResetSheet = true
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 24)
        .sheet(isPresented: $showingResetSheet) {
            PasswordResetSheet()
                .environment(auth)
        }
    }

    private func label(_ text: String) -> some View {
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

    private func submit() async {
        if isRegistering {
            await auth.register(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                displayName: trimmedDisplayName
            )
        } else {
            await auth.login(
                identifier: loginIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        }
    }
}

private struct FieldStyle: ViewModifier {
    var highlightError: Bool = false

    func body(content: Content) -> some View {
        content
            .padding()
            .background(.white.opacity(0.08))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(highlightError ? Color.red.opacity(0.7) : Color.clear,
                            lineWidth: 1)
            )
    }
}
