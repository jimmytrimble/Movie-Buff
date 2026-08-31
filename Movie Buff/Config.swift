import Foundation

enum Config {
    // Production — Render-hosted server. HTTPS, so no ATS exceptions required.
    // Replace `YOUR-SERVICE` with the subdomain from your Render dashboard (looks like
    // `movie-buff-XXXX.onrender.com` — copy from the top of the service page).
    nonisolated static let apiBaseURL = URL(string: "https://movie-buff-sm5m.onrender.com")!

    // Local dev fallbacks (uncomment one when you're pointing at a laptop server):
    //   iOS Simulator on your Mac:  URL(string: "http://localhost:8080")!
    //   Real iPhone on same Wi-Fi:  URL(string: "http://192.168.23.79:8080")!
}
