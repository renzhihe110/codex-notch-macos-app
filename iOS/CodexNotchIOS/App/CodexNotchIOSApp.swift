import SwiftUI

// Provides the iOS companion app entry point before the full dashboard is wired in later tasks.
@main
struct CodexNotchIOSApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}
