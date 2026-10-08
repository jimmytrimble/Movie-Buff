import Foundation
import AVFoundation
import Vision
import Speech

/// Turns a shared *video* into one text blob for the title extractor, entirely
/// on-device: it OCRs a handful of sampled frames (on-screen text — titles,
/// captions, rankings baked into the video) and transcribes the narration
/// (spoken audio). Foundation Models is text-only, so this is how we let it
/// "read" a video.
///
/// Both halves are best-effort and run concurrently — either can return empty
/// (no audio track, speech unavailable, unreadable frames) without failing the
/// whole analysis.
struct VideoAnalyzer {

    nonisolated func analyze(url: URL) async -> String {
        async let framesText = extractFrameText(from: url)
        async let spokenText = transcribeAudio(from: url)

        var pieces: [String] = []
        let frames = await framesText
        if !frames.isEmpty { pieces.append(frames) }
        let spoken = await spokenText
        if !spoken.isEmpty { pieces.append("Narration: " + spoken) }
        return pieces.joined(separator: "\n")
    }

    // MARK: - Frame OCR

    private nonisolated func extractFrameText(from url: URL) async -> String {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        // OCR doesn't need full resolution; downscale for speed and memory.
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        let times = await sampleTimes(for: asset)
        guard !times.isEmpty else { return "" }

        // Dedupe lines across frames — a title card shows the same text for many
        // frames, and we don't want to flood the model with repeats.
        var seen = Set<String>()
        var lines: [String] = []
        for time in times {
            guard let cgImage = try? await generator.image(at: time).image else { continue }
            guard let text = await Self.recognizeText(in: cgImage) else { continue }
            for raw in text.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.count >= 2, seen.insert(line.lowercased()).inserted else { continue }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Up to ~12 evenly spaced timestamps across the clip.
    private nonisolated func sampleTimes(for asset: AVURLAsset) async -> [CMTime] {
        let zero = CMTime(seconds: 0, preferredTimescale: 600)
        guard let duration = try? await asset.load(.duration) else { return [zero] }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return [zero] }

        let maxFrames = 12
        let step = max(1.5, seconds / Double(maxFrames))
        var times: [CMTime] = []
        var t = 0.0
        while t < seconds && times.count < maxFrames {
            times.append(CMTime(seconds: t, preferredTimescale: 600))
            t += step
        }
        return times.isEmpty ? [zero] : times
    }

    /// On-device Vision text recognition for a single frame. Being a
    /// `nonisolated async` function, it runs on the cooperative pool rather than
    /// the main actor, so the synchronous (CPU-heavy) `perform` doesn't block UI.
    nonisolated static func recognizeText(in cgImage: CGImage) async -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        let lines = (request.results as? [VNRecognizedTextObservation])?
            .compactMap { $0.topCandidates(1).first?.string } ?? []
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    // MARK: - Audio transcription

    private nonisolated func transcribeAudio(from url: URL) async -> String {
        // Skip entirely if the clip has no audio track.
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio),
              !tracks.isEmpty else { return "" }

        guard await Self.requestSpeechAuthorization(),
              let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return "" }

        let request = SFSpeechURLRecognitionRequest(url: url)
        // Keep it private: force on-device recognition. If the device/locale can't,
        // the task errors and we fall back to frames-only.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            let oneShot = OneShotString(continuation)
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    oneShot.resume(result.bestTranscription.formattedString)
                } else if error != nil {
                    oneShot.resume("")
                }
            }
        }
    }

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }
}

/// One-shot guard so a recognition callback (which can fire on an arbitrary
/// queue) resumes its continuation exactly once.
private final class OneShotString: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<String, Never>

    init(_ continuation: CheckedContinuation<String, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(returning: value)
    }
}
