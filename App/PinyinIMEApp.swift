import SwiftUI

/// 主 App 入口。主 App 只做启用引导与设置，键盘扩展自包含（见 PLAN.md 4.1/4.2）。
@main
struct PinyinIMEApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
