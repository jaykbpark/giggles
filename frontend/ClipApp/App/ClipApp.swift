import SwiftUI

@main
struct ClipApp: App {
    @State private var launchComplete = false
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main app
                RootView()
                    .opacity(launchComplete ? 1 : 0)
                
                // Launch animation
                if !launchComplete {
                    LaunchView(isComplete: $launchComplete)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: launchComplete)
            .onOpenURL { url in
                Task {
                    _ = await MetaGlassesManager.shared.handleURL(url)
                }
            }
        }
    }
}
