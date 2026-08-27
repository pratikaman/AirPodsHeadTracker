import SwiftUI

@main
struct HeadTrackerApp: App {
    @StateObject private var motion = MotionManager()

    var body: some Scene {
        Window("Head Tracker", id: "main") {
            ContentView()
                .environmentObject(motion)
        }
        .defaultSize(width: 480, height: 540)
    }
}
