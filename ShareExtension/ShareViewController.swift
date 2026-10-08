import SwiftUI
import UIKit
import Vision
import UniformTypeIdentifiers

/// Principal class for the Share Extension (referenced by Info.plist).
///
/// The extension never shows the host app. It reads whatever the share sheet
/// hands us — selected text, a URL, and/or a screenshot (OCR'd on-device) —
/// extracts movie/TV titles on-device with Apple Intelligence, resolves them to
/// real entries via the server, and lets the user confirm before batch-saving
/// to their list. All in the share sheet overlay.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let model = ShareModel(extensionContext: extensionContext)
        let host = UIHostingController(rootView: ShareRootView(model: model))
        host.view.backgroundColor = .clear

        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

// MARK: - View model

/// Drives the extension through its phases: read input → extract → resolve →
/// review → save. Lives on the main actor; all host-context work funnels here.
@MainActor
@Observable
final class ShareModel {
    enum Phase {
        case analyzing
        case analyzingVideo
        case review
        case empty
        case saving
        case done(count: Int)
        case signInRequired
        case premiumRequired
        case unavailable(String)
        case error(String)
    }

    private(set) var phase: Phase = .analyzing
    private(set) var matches: [ExtractedMovie] = []
    private(set) var unmatched: [String] = []
    /// imdbIDs the user has chosen to save (defaults to all matches).
    var selected: Set<String> = []

    private weak var extensionContext: NSExtensionContext?

    init(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
    }

    // MARK: Lifecycle

    func start() async {
        // On-device model has to be ready before anything else.
        if let unavailable = TitleExtractor.availability() {
            phase = .unavailable(unavailable.message)
            return
        }
        guard let token = ShareKeychain.readToken(), !token.isEmpty else {
            phase = .signInRequired
            return
        }

        let text = await gatherSharedText()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .error("Couldn't find any text to analyze. Try sharing a screenshot or selecting the post's caption.")
            return
        }

        // Video analysis may have flipped the phase; settle back to the generic
        // "Finding movies…" state while the model extracts titles.
        phase = .analyzing
        do {
            let titles = try await TitleExtractor().extractTitles(from: text)
            guard !titles.isEmpty else {
                phase = .empty
                return
            }
            let response = try await ShareAPI(token: token).resolveTitles(titles)
            matches = response.matches
            unmatched = response.unmatched
            selected = Set(matches.map(\.id))
            phase = matches.isEmpty ? .empty : .review
        } catch let error as ShareAPIError {
            handle(error)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func toggle(_ movie: ExtractedMovie) {
        if selected.contains(movie.id) {
            selected.remove(movie.id)
        } else {
            selected.insert(movie.id)
        }
    }

    func save() async {
        guard let token = ShareKeychain.readToken(), !token.isEmpty else {
            phase = .signInRequired
            return
        }
        let chosen = matches.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }

        phase = .saving
        do {
            try await ShareAPI(token: token).saveMovies(chosen)
            phase = .done(count: chosen.count)
            // Let the success state land before dismissing.
            try? await Task.sleep(for: .seconds(1.2))
            finish()
        } catch let error as ShareAPIError {
            handle(error)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func handle(_ error: ShareAPIError) {
        switch error {
        case .notSignedIn: phase = .signInRequired
        case .premiumRequired: phase = .premiumRequired
        case .server(let message): phase = .error(message)
        }
    }

    func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: "com.moviebuff.share", code: 0)
        )
    }

    /// Opens the host app (optionally deep-linking to the paywall) so the user
    /// can sign in or subscribe, then dismisses the extension.
    func openApp(path: String) {
        if let url = URL(string: "moviebuff://\(path)") {
            extensionContext?.open(url)
        }
        finish()
    }

    // MARK: Input gathering

    /// Collects every usable piece of text from the shared items: the share
    /// sheet's attributed text, plain-text attachments, URLs, and OCR of any
    /// shared image. Joined into one blob for on-device extraction.
    private func gatherSharedText() async -> String {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return "" }

        var pieces: [String] = []
        for item in items {
            if let text = item.attributedContentText?.string, !text.isEmpty {
                pieces.append(text)
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.audiovisualContent.identifier) {
                    // A shared video: sample frames (OCR) + transcribe narration on-device.
                    // Slower than text/image, so surface a dedicated status.
                    if let videoURL = await loadVideo(from: provider) {
                        phase = .analyzingVideo
                        let text = await VideoAnalyzer().analyze(url: videoURL)
                        if !text.isEmpty { pieces.append(text) }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let image = await loadImage(from: provider),
                       let text = await recognizeText(in: image) {
                        pieces.append(text)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadText(from: provider) {
                        pieces.append(text)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(from: provider) {
                        pieces.append(url.absoluteString)
                    }
                }
            }
        }
        return pieces.joined(separator: "\n")
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    /// Resolves a shared video attachment to a readable file URL, copied into our
    /// own temp dir so it stays valid for the duration of analysis.
    private func loadVideo(from provider: NSItemProvider) async -> URL? {
        let typeID = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
            ? UTType.movie.identifier
            : UTType.audiovisualContent.identifier
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeID) { item, _ in
                switch item {
                case let url as URL:
                    continuation.resume(returning: Self.copyToTemp(url))
                case let data as Data:
                    continuation.resume(returning: Self.writeTemp(data))
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func copyToTemp(_ url: URL) -> URL? {
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            // Fall back to the original URL; it may still be readable.
            return url
        }
    }

    private static func writeTemp(_ data: Data, ext: String = "mov") -> URL? {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try data.write(to: dest)
            return dest
        } catch {
            return nil
        }
    }

    private func loadImage(from provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
                switch item {
                case let image as UIImage:
                    continuation.resume(returning: image)
                case let url as URL:
                    continuation.resume(returning: (try? Data(contentsOf: url)).flatMap(UIImage.init))
                case let data as Data:
                    continuation.resume(returning: UIImage(data: data))
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Runs on-device text recognition (Vision) over a shared screenshot so we
    /// can analyze posts from platforms that only share an image, not a caption.
    /// Shares the implementation used for video frames.
    private func recognizeText(in image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        return await VideoAnalyzer.recognizeText(in: cgImage)
    }
}

// MARK: - Root view

struct ShareRootView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add to Movie Buff")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.cancel() }
                    }
                    if case .review = model.phase {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { Task { await model.save() } }
                                .disabled(model.selected.isEmpty)
                        }
                    }
                }
        }
        .task { await model.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .analyzing:
            StatusView(systemImage: "sparkles", title: "Finding movies…", spinner: true)
        case .analyzingVideo:
            StatusView(
                systemImage: "film",
                title: "Analyzing video…",
                subtitle: "Reading on-screen text and narration on-device.",
                spinner: true
            )
        case .saving:
            StatusView(systemImage: "square.and.arrow.down", title: "Saving…", spinner: true)
        case .done(let count):
            StatusView(
                systemImage: "checkmark.circle.fill",
                title: "Saved \(count) \(count == 1 ? "movie" : "movies")",
                tint: .green
            )
        case .empty:
            StatusView(
                systemImage: "film",
                title: "No movies found",
                subtitle: "We couldn't spot any movies or shows in that post."
            )
        case .signInRequired:
            UpsellView(
                icon: "person.crop.circle",
                title: "Sign in to save",
                message: "Sign in to Movie Buff, then share a post to add movies to your list.",
                actionTitle: "Open Movie Buff",
                action: { model.openApp(path: "signin") },
                dismiss: { model.cancel() }
            )
        case .premiumRequired:
            UpsellView(
                icon: "sparkles",
                title: "Save movies from anywhere",
                message: "Movie Buff Premium spots the movies in any post — captions or screenshots — and saves them to your list in one tap.",
                actionTitle: "See Premium",
                action: { model.openApp(path: "premium") },
                dismiss: { model.cancel() }
            )
        case .unavailable(let message):
            StatusView(systemImage: "wand.and.stars", title: "Apple Intelligence needed", subtitle: message, tint: .orange)
        case .error(let message):
            StatusView(systemImage: "exclamationmark.triangle", title: "Something went wrong", subtitle: message, tint: .orange)
        case .review:
            reviewList
        }
    }

    private var reviewList: some View {
        List {
            Section {
                ForEach(model.matches) { movie in
                    Button {
                        model.toggle(movie)
                    } label: {
                        MovieRow(movie: movie, isSelected: model.selected.contains(movie.id))
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("\(model.selected.count) selected")
            }

            if !model.unmatched.isEmpty {
                Section("Couldn't find") {
                    ForEach(model.unmatched, id: \.self) { title in
                        Text(title)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

private struct StatusView: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil
    var spinner: Bool = false
    var tint: Color = .accentColor

    var body: some View {
        VStack(spacing: 16) {
            if spinner {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Branded call-to-action shown when the user needs to sign in or subscribe —
/// a friendly screen instead of a raw error.
private struct UpsellView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: action) {
                Text(actionTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Not now", action: dismiss)
                .font(.subheadline)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MovieRow: View {
    let movie: ExtractedMovie
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            poster
            VStack(alignment: .leading, spacing: 2) {
                Text(movie.title)
                    .font(.body)
                    .lineLimit(2)
                if let year = movie.year, year != "N/A" {
                    Text(year)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .contentShape(Rectangle())
    }

    private var poster: some View {
        AsyncImage(url: movie.posterURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(.quaternary)
                .overlay(Image(systemName: "film").foregroundStyle(.secondary))
        }
        .frame(width: 46, height: 69)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
