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

        MenuBarExtra {
            PostureView(motion: motion, posture: motion.posture)
        } label: {
            if motion.posture.isSlouching {
                Label("\(Int(motion.posture.tiltDegrees.rounded()))°",
                      systemImage: "brain.head.profile")
            } else {
                Image(systemName: "brain.head.profile")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
