import SwiftUI

/// 主 App：启用教程 + 设置（默认布局）+ 关于（引擎/词库版本与许可证）。
/// 键盘扩展自包含，主 App 只做引导与设置（见 PLAN.md 4.1/4.2）；
/// 设置经 SettingsBridge 读写：App Group 可用时与键盘同步，
/// 不可用（本地模式）时此处改动不会传到键盘，键盘以其自身保存值为准——
/// 页面上明示当前同步状态，避免用户对着不生效的开关纳闷。
struct ContentView: View {
    @AppStorage(SettingsKey.defaultLayout, store: SettingsBridge.defaults)
    private var defaultLayout = "full26"

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("启用键盘") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. 打开系统「设置 → 通用 → 键盘 → 键盘」")
                        Text("2. 点「添加新键盘…」，选择「拼音键盘」")
                        Text("3. 回到键盘列表，点「拼音键盘」，打开「允许完全访问」")
                        Text("4. 在任意输入框长按地球键，选择「拼音键盘」即可开始打字")
                    }
                    .font(.subheadline)
                    Text("「允许完全访问」仅影响设置同步等增强功能；不开启时核心打字（引擎与用户词库都在键盘扩展自身沙盒内）照常工作。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("设置") {
                    Picker("默认布局", selection: $defaultLayout) {
                        Text("26 键全键盘").tag("full26")
                        Text("九宫格").tag("nineGrid")
                    }
                    HStack {
                        Text("设置同步")
                        Spacer()
                        Text(SettingsBridge.isSharedContainerAvailable ? "已开启" : "本地模式")
                            .foregroundStyle(.secondary)
                    }
                    if !SettingsBridge.isSharedContainerAvailable {
                        Text("当前为本地模式：这里改的默认布局不会同步到键盘，请在键盘上用布局切换键更改（键盘的设置优先）。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("输入引擎", value: "Rime（librime 1.16.1，经 LibrimeKit 0.1.0）")
                    LabeledContent("方案与词库", value: "雾凇拼音（rime-ice）")
                    Text("许可证：librime 与 LibrimeKit 封装为 BSD-3-Clause；雾凇拼音方案与词库为 GPL-3.0；其余组件——Boost（BSL-1.0）、LevelDB（BSD-3-Clause）、marisa-trie（BSD-2-Clause / LGPL-2.1 双许可）、OpenCC（Apache-2.0）、yaml-cpp（MIT）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("拼音输入法")
        }
    }
}
