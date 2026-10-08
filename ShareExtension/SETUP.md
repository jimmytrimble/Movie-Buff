# Movie Buff Share Extension — setup

Lets users share a post (text, link, or screenshot) from Instagram/X/Threads/etc.
and save the movies it mentions to their list, without leaving the host app.

## How it works

1. The share sheet hands the extension selected text, a URL, an image, and/or a **video**.
2. Screenshots are OCR'd on-device (Vision).
3. **Videos** are analyzed on-device (`VideoAnalyzer.swift`): we sample frames and
   OCR them (on-screen text — title cards, captions, rankings) **and** transcribe
   the narration (Speech, forced on-device). Both are best-effort and combined into
   the text blob. Foundation Models is text-only, so this is how it "reads" a video.
4. Movie/TV titles are extracted **on-device** with Apple Intelligence
   (Foundation Models) — no API key, no network, private. See `TitleExtractor.swift`.
5. Titles are sent to the server (`POST /movies/resolve`) which matches them
   against OMDB for real imdbIDs + posters.
6. The user confirms, and the selection is saved (`POST /me/movies/batch`).

## Files (already in this folder)

- `ShareViewController.swift` — principal class + SwiftUI UI (review list, upsell,
  status screens).
- `TitleExtractor.swift` — on-device Foundation Models extraction.
- `VideoAnalyzer.swift` — on-device video → text (frame OCR + speech transcription).
- `ShareAPI.swift` — self-contained networking + shared-keychain token read.
- `Info.plist` — activation rules (text/URL/image/**movie**) + `NSExtensionPrincipalClass`
  + `NSSpeechRecognitionUsageDescription`.
- `ShareExtension.entitlements` — App Group `group.JJ.Movie-Buff`.

## One-time Xcode setup (required — not scriptable)

1. **File ▸ New ▸ Target ▸ Share Extension.** Name `ShareExtension`,
   bundle id `JJ.Movie-Buff.ShareExtension`, embed in the Movie Buff app.
2. Delete the generated `ShareViewController.swift` and `MainInterface.storyboard`,
   and remove the `NSExtensionMainStoryboard` key from the generated Info.plist
   (we use `NSExtensionPrincipalClass` instead — our `Info.plist` already does).
3. Add the files in this folder to the new target; point the target's
   `INFOPLIST_FILE` / `CODE_SIGN_ENTITLEMENTS` at our `Info.plist` and
   `ShareExtension.entitlements` (or paste their contents into the generated ones).
4. **App Groups** capability on **both** the app target and the extension target:
   enable `group.JJ.Movie-Buff` (register it in the Developer portal if needed).
5. Set the extension's deployment target to **iOS 26** (matches the app; required
   for Foundation Models + `@Observable`).

## Server / config

- **No Anthropic/OpenAI key needed** — extraction is on-device.
- `OMDB_API_KEY` must be set on the server (already is; used by `/movies/resolve`).
- `/movies/resolve` and `/me/movies/batch` are premium-gated, so a premium
  account is needed to save (the UI shows a friendly upsell otherwise).

## Deep link for the upsell buttons — DONE

The "Open Movie Buff" / "See Premium" buttons open `moviebuff://premium` and
`moviebuff://signin`. Fully wired in the app:

- The `moviebuff` URL scheme is declared in `Movie-Buff-Info.plist` (project root)
  under `CFBundleURLTypes`, and the app target's `INFOPLIST_FILE` build setting
  points at it (Debug + Release). `GENERATE_INFOPLIST_FILE = YES` stays on, so Xcode
  merges the generated keys on top.
- `DeepLinkRouter.swift` parses incoming links; `ContentView` handles them via
  `.onOpenURL` — `premium` presents the paywall, `signin` drops guest mode so the
  sign-in / create-account flow appears.

Note: opening a URL from a Share extension via `extensionContext.open` is not
always honored; if it doesn't open, fall back to walking the responder chain to
`UIApplication.open`.

## Device requirement

On-device extraction needs an Apple Intelligence–capable device with the feature
enabled. On ineligible devices / when it's off, the extension shows an explanatory
screen instead of failing silently.

**Video analysis** additionally uses Vision (frame OCR, always available) and the
Speech framework for narration. Speech transcription is forced on-device
(`requiresOnDeviceRecognition`) and prompts once for permission
(`NSSpeechRecognitionUsageDescription`); the required speech assets download on
first use. If Speech is unavailable/denied, analysis gracefully falls back to
frames-only. Note: Speech/Foundation Models are limited in Simulator, so test video
sharing on a real device.
