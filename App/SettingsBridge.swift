import Foundation

/// 主 App 与键盘扩展之间的设置共享（含 App Group 容错）。
///
/// 设计依据见 PLAN.md 4.2：免费证书自签时签名工具可能改写 App Group 标识，
/// 因此共享只是可选增强——探测可用则用共享 UserDefaults，
/// 不可用则回退到各自进程的本地 UserDefaults，键盘侧以本地值为准。
enum SettingsBridge {
    /// 已定版（2026-11-04，随 Bundle ID com.mrzhao.pinyinime）。
    /// 注意：工程当前未声明 App Group entitlement，此值仅作探测——不可用时自动走本地回退。
    static let appGroupIdentifier = "group.com.mrzhao.pinyinime"

    /// 当前进程可用的设置存储：优先 App Group 共享容器，否则本地。
    static var defaults: UserDefaults {
        if let shared = UserDefaults(suiteName: appGroupIdentifier),
           FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil {
            return shared
        }
        return .standard
    }

    /// 共享容器是否可用（设置页据此显示「设置同步：开 / 本地模式」）。
    static var isSharedContainerAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil
    }
}

enum SettingsKey {
    static let defaultLayout = "settings.defaultLayout" // "full26" | "nineGrid"
    static let fuzzyPinyin = "settings.fuzzyPinyin"     // Bool
}
