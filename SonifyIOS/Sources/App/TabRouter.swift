import Combine
import SwiftUI

/// 跨页跳转的唯一入口。之前 Home 的搜索/设置按钮是空实现（点了没反应），
/// 就是因为 Home 拿不到 TabView 的 selection。现在统一走这里。
@MainActor
final class TabRouter: ObservableObject {

    enum Tab: Hashable {
        case home, library, settings
    }

    @Published var selected: Tab = .home
    /// 跳到资料库并自动聚焦搜索框。
    @Published var focusLibrarySearch = false

    func openLibrary() {
        selected = .library
    }

    func openLibrarySearch() {
        focusLibrarySearch = true
        selected = .library
    }

    func openSettings() {
        selected = .settings
    }

    /// 从首页"继续播放"卡片等处直接唤起播放页（MiniPlayerBar 之外的第二入口）。
    @Published var presentPlayer = false

    func openPlayer() {
        presentPlayer = true
    }
}
