import SwiftUI
import MWDATCore

@main
struct ClipApp: App {
    @State private var launchComplete = false
    
    init() {
        // Configure Meta Wearables SDK once at app startup (per SDK documentation)
        do {
            try Wearables.configure()
            #if DEBUG
            print("[ClipApp] Meta Wearables SDK configured successfully")
            #endif
        } catch {
            #if DEBUG
            print("[ClipApp] Meta Wearables SDK configuration failed: \(error)")
            #endif
        }
    }
    
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
                // Only handle URLs with metaWearablesAction parameter (per SDK docs)
                if url.absoluteString.contains("metaWearablesAction") {
                    Task {
                        _ = await MetaGlassesManager.shared.handleURL(url)
                    }
                } else {
                    print("[ClipApp] Ignoring non-Meta URL: \(url.scheme ?? "nil")")
                }
            }
        }
    }
}
