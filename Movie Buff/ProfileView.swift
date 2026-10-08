import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Shared avatar helpers

/// Cross-platform SwiftUI image from raw bytes (avatars are delivered as base64).
func platformImage(from data: Data) -> Image? {
    #if canImport(UIKit)
    if let image = UIImage(data: data) { return Image(uiImage: image) }
    #elseif canImport(AppKit)
    if let image = NSImage(data: data) { return Image(nsImage: image) }
    #endif
    return nil
}

/// Circular avatar: the user's image if present, otherwise gold initials.
struct ProfileAvatar: View {
    let imageData: Data?
    let label: String
    var size: CGFloat = 72

    private var initials: String {
        let words = label.split(separator: " ")
        if let first = words.first, let firstChar = first.first {
            if words.count > 1, let secondChar = words[1].first {
                return String([firstChar, secondChar]).uppercased()
            }
            return String(firstChar).uppercased()
        }
        return "?"
    }

    var body: some View {
        Group {
            if let imageData, let image = platformImage(from: imageData) {
                image.resizable().scaledToFill()
            } else {
                Circle()
                    .fill(LinearGradient(colors: [Theme.gold, Theme.goldSoft],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        Text(initials)
                            .font(.system(size: size * 0.4, weight: .black))
                            .foregroundStyle(.black)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

enum ProfileTab: String, CaseIterable {
    case saved = "Saved"
    case comments = "Comments"
    case ratings = "Ratings"
}

// MARK: - Signed-in user's own profile

struct ProfileView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var profile: ProfileDTO?
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var bioDraft = ""
    @State private var isEditingBio = false
    @State private var isPublic = false
    @State private var isSavingInfo = false

    @State private var photoItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false

    @State private var selectedTab: ProfileTab = .saved

    private let service = ProfileService()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                if auth.isGuest {
                    guestPrompt
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            header
                            visibilitySection
                            statsBar
                            ProfileContentTabs(profile: profile, selectedTab: $selectedTab)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(auth.isGuest ? "Account" : "Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(auth.isGuest ? "Close" : "Done") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
                if !auth.isGuest {
                    ToolbarItem(placement: .confirmationAction) {
                        NavigationLink {
                            AccountSettingsView()
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .navigationDestination(for: MovieSummary.self) { movie in
                MovieDetailView(imdbID: movie.imdbID)
            }
            .task { await load() }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatar(imageData: auth.user?.avatarImageData, label: identityLabel, size: 96)
                    .shadow(color: Theme.gold.opacity(0.35), radius: 12, y: 4)
                #if canImport(UIKit)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: isUploadingAvatar ? "hourglass" : "camera.fill")
                        .font(.caption)
                        .foregroundStyle(.black)
                        .padding(8)
                        .background(Theme.accent, in: Circle())
                }
                .disabled(isUploadingAvatar)
                #endif
            }
            Text(identityLabel)
                .font(.sectionTitle)
                .foregroundStyle(.white)

            bioView
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadAvatar(newItem) }
        }
    }

    @ViewBuilder
    private var bioView: some View {
        if isEditingBio {
            VStack(spacing: 8) {
                TextField("", text: $bioDraft,
                          prompt: Text("Add a short bio").foregroundColor(.gray),
                          axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .modifier(ProfileFieldStyle())
                HStack {
                    Button("Cancel") { isEditingBio = false; bioDraft = profile?.user.bio ?? "" }
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button {
                        Task { await saveInfo(bio: bioDraft) }
                    } label: {
                        if isSavingInfo { ProgressView().tint(.black) }
                        else { Text("Save bio").font(.caption.weight(.semibold)).foregroundStyle(.black) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.accent, in: Capsule())
                }
            }
        } else {
            Button {
                bioDraft = profile?.user.bio ?? ""
                isEditingBio = true
            } label: {
                let bio = profile?.user.bio
                Text(bio?.isEmpty == false ? bio! : "Add a short bio")
                    .font(.footnote)
                    .foregroundStyle(bio?.isEmpty == false ? .white.opacity(0.75) : .white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private var visibilitySection: some View {
        Toggle(isOn: $isPublic) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Public profile").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(isPublic ? "Anyone can find and view your profile."
                              : "Only you and your friends can view your profile.")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            }
        }
        .tint(Theme.accent)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: isPublic) { old, new in
            guard profile != nil, old != new else { return }
            Task { await saveInfo(isPublic: new) }
        }
    }

    private var statsBar: some View {
        HStack(spacing: 0) {
            stat(count: profile?.savedCount ?? 0, label: "Saved")
            divider
            stat(count: profile?.commentCount ?? 0, label: "Comments")
            divider
            stat(count: profile?.ratings.count ?? 0, label: "Ratings")
        }
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func stat(count: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title3.weight(.black)).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 28)
    }

    private var identityLabel: String {
        if let name = auth.user?.displayName, !name.isEmpty { return name }
        return auth.user?.email ?? "You"
    }

    private var guestPrompt: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 64))
                .foregroundStyle(Theme.gold)
                .padding(.top, 32)
            Text("You're browsing as a guest")
                .font(.sectionTitle)
                .foregroundStyle(.white)
            Text("Create an account to build your profile, save movies, and message friends.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                auth.exitGuestMode()
                dismiss()
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

    // MARK: Actions

    private func load() async {
        guard !auth.isGuest else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await service.me()
            profile = loaded
            isPublic = loaded.user.isPublic ?? false
            bioDraft = loaded.user.bio ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveInfo(bio: String? = nil, isPublic newPublic: Bool? = nil) async {
        isSavingInfo = true
        defer { isSavingInfo = false }
        do {
            let updated = try await service.updateInfo(
                bio: bio?.trimmingCharacters(in: .whitespacesAndNewlines),
                isPublic: newPublic
            )
            profile = updated
            self.isPublic = updated.user.isPublic ?? false
            isEditingBio = false
            await auth.refreshUser()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        #if canImport(UIKit)
        isUploadingAvatar = true
        defer { isUploadingAvatar = false; photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let base64 = Self.downscaledJPEGBase64(data) else {
                errorMessage = "Couldn't read that image."
                return
            }
            _ = try await service.uploadAvatar(imageBase64: base64)
            await auth.refreshUser()
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    #if canImport(UIKit)
    /// Downscale to a small square-ish JPEG so avatars stay tiny (base64 in JSON).
    static func downscaledJPEGBase64(_ data: Data, maxDimension: CGFloat = 256, quality: CGFloat = 0.8) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)?.base64EncodedString()
    }
    #endif
}

// MARK: - Shared profile content (saved / comments / ratings)

/// Renders a profile's content lists. Reused by the self profile and the public
/// profile view. Expects to live inside a `NavigationStack` that provides a
/// `navigationDestination(for: MovieSummary.self)`.
struct ProfileContentTabs: View {
    let profile: ProfileDTO?
    @Binding var selectedTab: ProfileTab

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $selectedTab) {
                ForEach(ProfileTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch selectedTab {
            case .saved:    savedGrid
            case .comments: commentsList
            case .ratings:  ratingsList
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14),
         GridItem(.flexible(), spacing: 14)]
    }

    @ViewBuilder
    private var savedGrid: some View {
        let movies = profile?.savedMovies ?? []
        if movies.isEmpty {
            emptyRow("No saved movies yet.")
        } else {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(movies) { saved in
                    NavigationLink(value: saved.summary) {
                        ProfilePoster(posterURL: saved.posterAsURL, title: saved.title)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var commentsList: some View {
        let comments = profile?.comments ?? []
        if comments.isEmpty {
            emptyRow("No comments yet.")
        } else {
            VStack(spacing: 10) {
                ForEach(comments) { comment in
                    NavigationLink(value: MovieSummary(title: comment.imdbID, year: nil,
                                                       imdbID: comment.imdbID, type: nil, poster: nil)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(comment.content)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if comment.isSpoiler {
                                Text("Spoiler").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                            }
                        }
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var ratingsList: some View {
        let ratings = profile?.ratings ?? []
        if ratings.isEmpty {
            emptyRow("No ratings yet.")
        } else {
            VStack(spacing: 8) {
                ForEach(ratings) { rating in
                    NavigationLink(value: MovieSummary(title: rating.imdbID, year: nil,
                                                       imdbID: rating.imdbID, type: nil, poster: nil)) {
                        HStack {
                            Image(systemName: rating.value == .up ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                                .foregroundStyle(rating.value == .up ? .green : .red)
                            Text(rating.imdbID).font(.subheadline).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
    }
}

/// Small poster tile used in profile grids.
struct ProfilePoster: View {
    let posterURL: URL?
    let title: String

    var body: some View {
        AsyncImage(url: posterURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(2/3, contentMode: .fill)
            default:
                ZStack {
                    Theme.surface
                    Image(systemName: "film").foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Account & security (email / display name / password)

struct AccountSettingsView: View {
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
            guard !currentPassword.isEmpty, newPassword.count >= 8, confirmPassword == newPassword
            else { return false }
            return true
        }
        return emailChanged || nameChanged
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section(title: "Account") {
                        fieldLabel("Email")
                        TextField("", text: $email, prompt: Text(currentEmail).foregroundColor(.gray))
                            .textContentType(.emailAddress)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .modifier(ProfileFieldStyle())
                        fieldLabel("Display Name")
                        TextField("", text: $displayName,
                                  prompt: Text(currentDisplayName).foregroundColor(.gray))
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .modifier(ProfileFieldStyle())
                    }

                    section(title: "Change Password") {
                        Text("Leave blank to keep your current password.")
                            .font(.caption).foregroundStyle(.white.opacity(0.5))
                        fieldLabel("Current Password")
                        SecureField("", text: $currentPassword,
                                    prompt: Text("Current").foregroundColor(.gray))
                            .modifier(ProfileFieldStyle())
                        fieldLabel("New Password (min 8)")
                        SecureField("", text: $newPassword, prompt: Text("New").foregroundColor(.gray))
                            .modifier(ProfileFieldStyle(highlight: passwordTooShort))
                        if passwordTooShort { hint("New password must be at least 8 characters.") }
                        fieldLabel("Confirm New Password")
                        SecureField("", text: $confirmPassword,
                                    prompt: Text("Confirm").foregroundColor(.gray))
                            .modifier(ProfileFieldStyle(highlight: passwordMismatch))
                        if passwordMismatch { hint("Passwords do not match.") }
                    }

                    if let successMessage { banner(text: successMessage, color: .green) }
                    if let errorMessage { banner(text: errorMessage, color: .red) }

                    signOutButton.padding(.top, 8)
                }
                .padding()
            }
        }
        .navigationTitle("Account & Security")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
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
        .onAppear {
            if email.isEmpty { email = currentEmail }
            if displayName.isEmpty { displayName = currentDisplayName }
        }
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            Task { await auth.logout(); dismiss() }
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
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.sectionTitle).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 10) { content() }
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
            currentPassword = ""; newPassword = ""; confirmPassword = ""
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProfileFieldStyle: ViewModifier {
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
                        if let infoMessage { banner(text: infoMessage, color: .green) }
                        if let errorMessage { banner(text: errorMessage, color: .red) }
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
                    Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter the email associated with your account. We'll send you a 6-digit code.")
                .font(.footnote).foregroundStyle(.white.opacity(0.7))
            TextField("", text: $email, prompt: Text("you@example.com").foregroundColor(.gray))
                .textContentType(.emailAddress)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .modifier(ProfileFieldStyle())
            Button {
                Task { await requestCode() }
            } label: { buttonLabel(title: "Send Code", loading: isSubmitting) }
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("If \(email) has an account, you'll receive a 6-digit code. Enter it below along with your new password.")
                .font(.footnote).foregroundStyle(.white.opacity(0.7))
            TextField("", text: $code, prompt: Text("6-digit code").foregroundColor(.gray))
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                #endif
                .modifier(ProfileFieldStyle())
            SecureField("", text: $newPassword, prompt: Text("New password (min 8)").foregroundColor(.gray))
                .modifier(ProfileFieldStyle(highlight: !newPassword.isEmpty && newPassword.count < 8))
            SecureField("", text: $confirmPassword, prompt: Text("Confirm new password").foregroundColor(.gray))
                .modifier(ProfileFieldStyle(highlight: !confirmPassword.isEmpty && confirmPassword != newPassword))
            Button {
                Task { await submitReset() }
            } label: { buttonLabel(title: "Reset Password", loading: isSubmitting) }
            .disabled(!canSubmitReset || isSubmitting)
            Button("Use a different email") {
                step = .email; code = ""; newPassword = ""; confirmPassword = ""
                infoMessage = nil; errorMessage = nil
            }
            .font(.footnote).foregroundStyle(.yellow).padding(.top, 4)
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
        errorMessage = nil; infoMessage = nil
        do {
            try await auth.forgotPassword(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            infoMessage = "If that email is registered, a code has been sent. Check your inbox."
            step = .code
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitReset() async {
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil; infoMessage = nil
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
