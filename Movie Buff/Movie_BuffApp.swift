import SwiftUI

@main
struct Movie_BuffApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(iOS)
                .environment(PushCoordinator.shared)
                #endif
        }
    }
}
