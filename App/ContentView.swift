import SwiftUI

/// 启用引导页（占位）。正式版包含：启用步骤图文、默认布局选择、
/// 设置同步状态（App Group 可用/本地模式，见 SettingsBridge）。
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("启用键盘") {
                    Text("设置 → 通用 → 键盘 → 键盘 → 添加新键盘，选择「拼音键盘」。")
                    Text("「允许完全访问」仅影响设置同步等增强功能，核心打字不依赖它。")
                        .foregroundStyle(.secondary)
                }
                Section("设置") {
                    // TODO(步骤 5): 默认布局（26 键 / 九宫格）、模糊音开关，经 SettingsBridge 读写。
                    Text("设置项将在后续版本出现。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("拼音输入法")
        }
    }
}
