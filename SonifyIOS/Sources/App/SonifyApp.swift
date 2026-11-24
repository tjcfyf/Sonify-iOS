import SwiftUI

@main
@MainActor
struct SonifyApp: App {

    @StateObject private var engine = PlayerEngine.shared
    @StateObject private var library = LibraryStore.shared
    @StateObject private var settings = SettingsStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(library)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .onAppear {
                    // 默认倍速跟随设置。
                    engine.setRate(Float(settings.defaultRate))
                }
        }
    }
}
