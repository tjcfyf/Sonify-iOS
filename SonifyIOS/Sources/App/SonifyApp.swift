import SwiftUI
import UIKit

@main
@MainActor
struct SonifyApp: App {

    @StateObject private var engine = PlayerEngine.shared

    init() {
        // iOS 15 没有 scrollContentBackground(.hidden)，List 只能靠 UIKit 外观把底色打通，
        // 否则资料库会在深色玻璃背景上出现一块不透明的默认列表底色。
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
    }
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
