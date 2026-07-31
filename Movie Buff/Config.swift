import Foundation

enum Config {
    // For iOS Simulator: "http://localhost:8080" works (simulator shares the Mac's loopback).
    // For a real iPhone on the same Wi-Fi: replace with your Mac's LAN IP,
    //     e.g. "http://192.168.1.42:8080".
    // Find your Mac's IP with:  ipconfig getifaddr en0   (or System Settings → Wi-Fi)
    static let apiBaseURL = URL(string: "http://192.168.68.104:8080")!
}
