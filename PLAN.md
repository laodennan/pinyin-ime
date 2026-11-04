# 自研 iOS 拼音输入法（Rime 引擎）— 工程路线与实施计划

> 状态：路线核查完成（2026-11-04），尚未开始编码、尚未跑过任何构建。
> 交付模式：Swift 工程 → GitHub Actions（macOS runner）打包未签名 IPA → 用户自签。
> 本机为 Linux VM、无 Xcode，一切编译验证只能在 CI 上完成；本文所有结论都标注了证据来源，未核实项单列在第 7 节。

---

## 0. 结论（一句话版）

**v1 不自己编 librime**：直接用社区维护的 SwiftPM 二进制包 `zhanggenlove/LibrimeKit`（librime 1.16.1，已内嵌 librime-lua 插件，实测验证过二进制符号）在 CI 里零引擎编译地集成；雾凇拼音（rime-ice，GPL-3.0）在 CI 的 macOS runner 上用官方 librime macOS 版 `rime_deployer` 预编译成 `.bin` 打包进 App；九宫格走**应用层 T9**（Hamster 同款设计：数字序列在 App 层切分还原成拼音字母再喂引擎），不依赖引擎侧的 `t9_processor` 插件。自编 librime 留作 v2 的备选路线（方案与脚本出处已备好）。

---

## 1. librime iOS 集成路线核查

### 1.1 仓输入法 Hamster 是怎么做的（证据）

仓库：<https://github.com/imfuxiao/Hamster>（仓库描述即 "librime for iOS App"，MIT，2025-05-13 最后推送）。

- Hamster **不从源码编 librime**。仓库根目录 `librimeFramework.sh` 只做一件事：从 `imfuxiao/LibrimeKit` 的 GitHub Release 下载预编译包 `Frameworks.tgz`（脚本内写死版本 `LibrimeKitVersion="2.4.2"`），解压到仓库根 `Frameworks/` 目录。其 CI（`.github/workflows/ci.yml`）同样用 release-downloader 拉 `imfuxiao/LibrimeKit` 的 latest `Frameworks.tgz`。
- 这些预编译产物是 **10 个 xcframework**，由本地 Swift 包 `Packages/RimeKit` 以 `binaryTarget(path:)` 引用（见 `Packages/RimeKit/Package.swift`）：
  `librime`、boost（atomic/filesystem/regex/system 四个）、`libglog`、`libleveldb`、`libmarisa`、`libopencc`、`libyaml-cpp`。即 librime 的完整依赖集就是这 6 类：**boost、glog、leveldb、marisa-trie、opencc、yaml-cpp**（与 librime 官方仓库 `.gitmodules` 的 deps 子模块一致：glog/leveldb/yaml-cpp/marisa-trie/opencc 均为子模块，boost 外部提供）。
- 桥接层结构（`Packages/RimeKit/Sources/`）：`C/` 放官方头文件 `rime_api.h`、`rime_levers_api.h`；`ObjC/` 是薄封装 `irime_api.h/.m`；`Swift/Rime.swift` 是 Swift API。我们自己的桥接层照这个三层结构设计（见第 5.4 节）。
- **重大风险实测**：截至 2026-11-04 本轮核查，`https://github.com/imfuxiao/LibrimeKit` 仓库经 GitHub API 返回 **404**，脚本里的 release 下载直链同样 **404**。即 Hamster 当前公开流水线依赖的预编译来源已不可达（仓库被删/转私有/改名，本轮无法确认是哪种）。**结论：不能把任何单一上游 release 当作长期依赖，拿到手就必须自己留一份（vendoring）。**

### 1.2 备选预编译来源：zhanggenlove/LibrimeKit（v1 推荐）

仓库：<https://github.com/zhanggenlove/LibrimeKit>（2026-06-04 仍有推送，活跃）。

- 形态：SwiftPM 二进制分发。`Package.swift` 用 `binaryTarget(url:checksum:)` 指向其 GitHub Release（tag `v0.1.0`）的 9 个 `*.xcframework.zip`，每个带 sha256 校验和：librime、boost×4、leveldb、marisa、opencc、yaml-cpp（无 glog——它以 `-DENABLE_LOGGING=OFF` 编译，正好省体积）。
- 版本：**librime 1.16.1**；架构仅 `ios-arm64`（真机）+ `ios-arm64-simulator`（Apple Silicon 模拟器），最低 iOS 15。产物是静态库 `.a` 形式的 xcframework（无动态库，签名/打包更简单）。
- **本轮实测验证**（在 Linux VM 上下载其 `librime.xcframework.zip` 并对 arm64 静态库做 strings 检查）：
  - ✅ **librime-lua 已编入**：二进制中存在 `lua_translator`、`lua_filter` 组件名及 `LuaType<...>`/`lua_State` 符号。雾凇拼音强依赖 lua（见 2.3），这一条是选型决定性条件。
  - ❌ **不含 `t9_processor`**：二进制中无此组件名字符串。所以雾凇自带的 `t9.schema.yaml` 在这个引擎包上跑不起来——这正是九宫格改走应用层的原因（第 3 节）。
- 桥接：仓库自带 ObjC shim（`LRK*` 类型）+ Swift 糖衣（`Rime.shared.process(input:)` 等）。我们的桥接层优先用它自带的 Swift API，不够用时下沉到它暴露的 C API。
- 许可证：封装代码 BSD-3-Clause；但其 `THIRD_PARTY_LICENSES.md` 自称为 stub（完整上游许可证文本尚未内嵌）。**个人自签自用无碍；若将来要分发，必须先补齐各上游许可证文本**（librime BSD-3、Boost BSL-1.0、leveldb BSD-3、marisa-trie BSD/LGPL 双许可、opencc Apache-2.0、yaml-cpp MIT）。

### 1.3 备选路线：CI 里从源码自编 librime（v2 / 兜底）

- librime 官方仓库 <https://github.com/rime/librime>（BSD-3-Clause，活跃，最新正式版 1.17.0 / 2026-06）。官方 Release 只提供 macOS universal 与 Windows 二进制，**没有 iOS 产物**；仓库内无 iOS 工具链文件。iOS 交叉编译必须自己搭：CMake + iOS 工具链（如社区 ios-cmake）逐个编 deps 子模块与 boost。
- 现成脚本出处（均为公开仓库，可直接参考/改造）：
  - `imfuxiao/boost-iosx`：把 Boost 编成 XCFramework 的脚本工程（Hamster 作者维护，公开可用）。
  - `amorphobia/LibrimeKit`（2023）：完整的「源码编 librime for iOS + 打成 SPM 包」实现，含 `librimeBuild.sh`、`librime.patch`、boost-iosx 子模块。可作自编路线的脚手架，但年代久（对应 librime 1.7/1.8 时代），补丁需按新版本重验。
  - `chenqinggang001/LibrimeKit-ios12`（2025-08 仍有推送）：同结构（Makefile + librimeBuild.sh + librime.patch + boost-iosx），目标 iOS 12，可作较新的参考。
  - `imfuxiao/librime`、`imfuxiao/librime-lua`、`imfuxiao/librime-predict` 均为官方上游的镜像 fork，无 iOS 专用改动（本轮核查其文件树：无 t9 相关文件，plugins 目录只有官方脚手架，插件靠 `install-plugins.sh` 在构建时拉取）。
- 代价评估（未实测，属经验估计）：boost + 5 个 deps + librime + lua 插件在 GitHub macOS runner 上从零编译约 20–60 分钟/次，必须做分层缓存（deps 按版本缓存、librime 按 commit 缓存）才可日常迭代。自编的收益是可控版本与可加插件（如 t9/octagram），v1 不需要，先不付这个成本。

### 1.4 路线决策表

| 路线 | 内容 | 优点 | 风险/代价 | 采用 |
|---|---|---|---|---|
| A | SPM 引用 zhanggenlove/LibrimeKit 0.1.0（librime 1.16.1+lua），并在首次 CI 成功后把 9 个 zip 转存到**自有仓库 Release** 锁版本 | CI 零引擎编译、最快出 v1；lua 已实测在内 | 单人维护的上游；许可证 stub；无 t9_processor（九宫格走应用层解决）；版本被上游锁死 | **v1 采用** |
| B | CI 从源码自编（boost-iosx + deps + librime + lua 插件） | 版本/插件完全可控 | 搭建与维护成本高、CI 时长大、补丁坑（参考实现均需重验） | v2 或 A 失效时兜底 |
| C | 引用 imfuxiao/LibrimeKit 预编译包（Hamster 同款） | 与 Hamster 完全同源 | **来源已 404，不可用** | 排除 |

---

## 2. 雾凇拼音（rime-ice）接入核查

仓库：<https://github.com/iDvel/rime-ice>（2026-10-31 仍在推送）。

### 2.1 许可证与体积

- **许可证 GPL-3.0**。个人自用没问题；若将来分发 App，雾凇的方案/词库部分需按 GPL 履行义务（附许可证、提供对应源文件——它的源文件即仓库本身，保留出处与 LICENSE 即可基本满足，正式分发前需再做一次合规核查）。
- 仓库总体积约 237 MB（含 `.git` 与全部词库）。中文词库 `cn_dicts/` 文本量：`base.dict.yaml` 15.8 MB、`ext.dict.yaml` 11.4 MB、`tencent.dict.yaml` 16.5 MB、`8105.dict.yaml` 0.11 MB、`41448.dict.yaml` 0.37 MB（默认不启用），合计约 **44 MB 文本**；另有 `radical_pinyin.dict.yaml` 2.2 MB、英文词库 `en_dicts/`、opencc 配置与 lua 脚本若干。
- **键盘扩展内存红线**：iOS 键盘扩展有较严的内存上限（历史值约 70 MB 级别，iOS 27 上的确切值未核实，见第 7 节）。词库全量加载（尤其 tencent 大词库）可能顶内存。预案：v1 先上 base+ext+8105，tencent 词库做成可选，实测内存后再决定是否纳入。这不影响出词质量的主体（base+ext 已是雾凇的主力词库）。

### 2.2 部署方式：CI 预编译 `.bin`，首次启动免部署 ✅ 可行

- Rime 的部署产物（`build/*.prism.bin`、`*.table.bin`、`*.reverse.bin` 等）由 `rime_deployer --build` 生成，与平台无关（Hamster 的 `InputSchemaBuild.sh` 里就留有对 rime-ice 执行 `rime_deployer --build` 的命令，只是被注释掉、改为 App 内首次部署；命令本身即证据）。
- 官方 librime Release 提供 macOS universal 二进制包（含 `rime_deployer` 与 `rime-deps` 预编依赖），可直接在 GitHub macOS runner 上运行。**版本对齐原则**：预编译用的 deployer 版本应与 iOS 端 librime 版本一致——iOS 端用 1.16.1，则 CI 用官方 **1.16.1** 的 macOS 包（资产名形如 `rime-de4700e-macOS-universal.tar.bz2` / `rime-deps-de4700e-macOS-universal.tar.bz2`，已在本轮核查中确认存在于 1.16.1 Release）。跨版本 `.bin` 兼容性未核实，不冒这个险。
- 流水线：CI 中 clone 固定 commit 的 rime-ice → 组装 shared data 目录（rime-ice 文件 + 必要的 prelude/essay 基础文件——注意：雾凇是自包含方案，不依赖 plum 的 prelude；但 `default.yaml` 引用的基础组件需在组装时按其 README 的文件清单核对）→ 跑 `rime_deployer --build` → 把源码 yaml 与生成的 `build/` 一起打进键盘扩展的资源目录。运行时 Rime 以该目录为 `shared_data_dir`，检测到 `.bin` 齐全即跳过部署，首次打开键盘直接可用。
- 用户词库（userdb，leveldb 格式）**不预编译**，运行时在用户数据目录生成（见 4.2）。

### 2.3 对引擎的要求

- **必须带 librime-lua**：雾凇的日期/计算器/拆字反查等多处用 `lua_translator@*...`/`lua_filter@*...`，其 README FAQ 明确说 lua 未加载时会出现无候选/功能缺失。路线 A 的二进制已实测含 lua（1.2 节）。八股文语法模型（librime-octagram）是可选增强，默认不启用，v1 不引入。
- **九宫格支持情况**：雾凇自带 `t9.schema.yaml`（方案名「中文九键」，文件头注明「适配了仓输入法 Hamster 九宫格布局」，作者含 Hamster 作者 morse.hsiao）。但它依赖引擎组件 `t9_processor`，且其 README 脚注写明「九键方案仅适用于 iOS 平台的特定软件」。本轮核查：`t9_processor` 不在官方 librime 文件树中、也不在路线 A 的二进制中、其提供方仓库（推测为 imfuxiao 的 LibrimeKit 构建）现已 404 无法确认。**结论：雾凇 t9 方案 v1 不用，九宫格按第 3 节应用层方案实现**；该 schema 文件可留作 v2 自编引擎时的现成资产。

---

## 3. 九宫格（T9）实现方案

### 3.1 Hamster 的实现思路（证据）

Hamster 的 T9 是**应用层实现**，代码在 `Packages/HamsterKit/Sources/T9/T9Constants.swift` 与 `Packages/HamsterKeyboardKit/Sources/RimeContext/RimeContext.swift`（「T9 拼音处理」一节，约 952 行起）：

- 内置两张全量映射表（由测试代码 `HamsterKit/Tests/Algo/T9Test.swift` 从全部拼音音节表程序化生成，可复现）：
  - `t9ToPinyinMapping`：数字串 → 可能的拼音音节列表（如 `"6426": ["mian","miao","nian","niao"]`）；
  - `pinyinToT9Mapping`：音节 → 数字串；
  - 以及一棵以数字串为键的 **Trie**（`t9PinyinTrie`）做前缀匹配/切分。
- `RimeContext` 注释直言其职责是「将用户 T9 拼音输入**还原为正常的拼音**」再交给 Rime；原始数字串单独保存（`t9UserInputKey`）用于显示与删除处理（T9 删除有专门方法，因为删一位数字要重算切分）。
- 九宫格键盘视图（`ChineseNineGridKeyboard`）上方有音节条：列出当前数字串可切分出的音节供用户点选消歧，点选后用 `pinyinToT9Mapping` 与已输入数字串做前缀匹配来锁定切分。

即：**引擎永远只看到字母（全拼会话），T9 只是前端的一层数字→音节切分状态机。** 这与引擎是否支持 t9 插件完全解耦，是最稳妥的做法。

### 3.2 本项目 T9 设计（照此实现）

- **状态**：`digitBuffer: [Int]`（2–9 为字母键；`1` 作分词键，等价全拼的 `'`；`0` 待定为符号/空格，先留空）。
- **音节表生成**：不手写映射表。维护一份标准拼音音节清单（约 410 个，含 ü 系列），在构建期（或首次启动时）由「字母→按键数字」规则程序化生成 `digit→[syllable]` 映射与 Trie——与 Hamster 的生成方法一致（其测试代码即生成器原型）。音节清单随代码入库（一个文本文件），生成逻辑写单元测试保证与清单自洽。
- **切分**：对 `digitBuffer` 做动态规划切分：枚举所有能完整覆盖数字串的音节组合，按「音节数少者优先、同数时整词在词库中存在者优先」排序，取最优切分作为当前喂给引擎的输入；其余候选切分进入音节条供点选。
- **喂引擎**：把最优切分的音节以 `'` 连接（如 `ni'hao`）后整串重置进 Rime 会话（`setInput` 语义），保证引擎侧切分与前端一致；用户点选音节条锁定某个音节后，该音节在后续切分中固定（pinned），只对未锁定尾部重算。
- **候选与上屏**：候选直接取 Rime 会话的菜单（整句候选由引擎按锁定切分生成）；选中候选后由引擎完成部分上屏，剩余尾部继续留在会话中——因为喂的是字母，这一步全是 Rime 原生行为，前端只同步 `digitBuffer` 的已消耗长度（按上屏候选的 comment/音节长度反推消耗的数字位数；Hamster 用候选 comment 做此反推，我们照此设计，细节在编码时以其 `RimeContext` 为参照）。
- **预编辑显示**：前端自渲染：数字串原文 + 当前切分的拼音（空格分隔），不直接用 Rime 的 raw preedit（数字语义在引擎侧不存在）。
- **删除**：弹掉 `digitBuffer` 最后一位 → 重新切分 → 重新喂入。禁止把 Backspace 直接透传给引擎（字母数与数字数不对应）。

---

## 4. 工程结构设计

### 4.1 总体结构

```
pinyin-ime/
├── PLAN.md                  # 本文件
├── README.md
├── project.yml              # XcodeGen 工程定义（见 4.3 取舍）
├── .github/workflows/
│   └── build-ipa.yml        # CI：组装 Rime 数据 + 预编译 + 打未签名 IPA
├── App/                     # 主 App（启用引导、设置、词库管理入口）
│   ├── PinyinIMEApp.swift
│   ├── ContentView.swift
│   └── SettingsBridge.swift # 与键盘共享设置的读写（含 App Group 容错，见 4.2）
├── Keyboard/                # 键盘扩展（主体）
│   ├── KeyboardViewController.swift
│   ├── RimeBridge/
│   │   ├── RimeEngine.swift       # 对 LibrimeKit/C API 的统一包装（接口先行）
│   │   └── RimeModels.swift       # Candidate / Composition / Menu 值类型
│   ├── T9/
│   │   ├── T9Mapper.swift         # 音节表生成 + Trie + 切分（DP）
│   │   ├── syllables.txt          # 标准拼音音节清单（生成映射表的源）
│   │   └── README.md
│   ├── Layout/
│   │   ├── FullKeyboardLayout.swift   # 26 键键位模型
│   │   └── NineGridLayout.swift       # 九宫格键位模型
│   └── CandidateBar/              # 候选栏 UI（后续步骤填充）
├── RimeData/
│   └── README.md            # 说明：CI 如何填充 rime-ice 与 build/*.bin；大数据不入 git
├── scripts/
│   ├── fetch-rime-ice.sh    # 按锁定 commit 拉取 rime-ice 并组装 SharedData
│   └── precompile-schemas.sh# 在 macOS runner 上跑官方 rime_deployer 生成 .bin
└── Vendor/
    └── README.md            # LibrimeKit 的 SPM 引用与 vendoring 策略（见 1.4 路线 A）
```

主 App 与键盘扩展的关系：主 App 只做启用引导与设置；**键盘扩展自包含**（引擎、词库、userdb 都在扩展侧闭环），主 App 挂掉或未打开都不影响打字。

### 4.2 Rime 数据目录与 userdb 存放策略（针对免费证书自签的容错设计）

背景约束：用户用免费证书自签，签名工具（AltStore/SideStore/巨魔等各不相同）可能改写 Bundle ID 与 **App Group 标识**（常见做法是给 group id 加 Team 前缀）；若设计强依赖 App Group 共享容器，换个签名工具就可能整个键盘失效。因此：

- **只读数据（方案+预编译 .bin）**：放在**键盘扩展自身的 bundle 资源**里（`Keyboard.appex` 内的 `SharedData/`），作为 Rime 的 `shared_data_dir`。不依赖任何共享容器，签名怎么改都不影响。
- **可写数据（userdb 用户词库、部署日志）**：放在**键盘扩展自己沙盒**内的目录（`Library/RimeUserData/`，经 `FileManager` 取扩展容器路径），作为 `user_data_dir`。扩展沙盒在重签后依然是扩展自己的，userdb 可正常读写、跨启动持久。代价：主 App 看不到 userdb——v1 接受（词库管理功能若将来要做，再走导出/导入文件中转）。
- **设置共享（可选增强，不作地基）**：主 App 与扩展之间共享少量设置（如默认布局 26 键/九宫格、模糊音开关）时，先尝试 App Group（`group.<bundleid>`）；运行时用 `containerURL(forSecurityApplicationGroupIdentifier:)` 探测可用性：**可用则用共享 UserDefaults，不可用则各自回退到本地 UserDefaults**，键盘以扩展本地值为准。探测结果在设置页明示（「设置同步：开/关（本地模式）」），不让用户对着失效的开关干瞪眼。
- **完全访问（RequestsOpenAccess）**：扩展 Info.plist 申请 `RequestsOpenAccess = true`（app group 容器、剪贴板等都需要）。PLAN 层面先声明：即使未获授权，核心打字（引擎+userdb 在扩展沙盒内）也必须能工作——授权只影响设置同步等增强项。

### 4.3 工程文件取舍：XcodeGen（project.yml）

- 文栖的教训是手写 pbxproj + 自定义 Info.plist 易错（版本号两处同步问题）。本项目有 3 个 target（App、键盘扩展、测试）+ SPM 依赖，手写 pbxproj 更脆。
- **选 XcodeGen**：`project.yml` 单文件声明 targets、SPM 包（LibrimeKit）、扩展的 Info.plist 键（`NSExtensionPointIdentifier = com.apple.keyboard-service`、`RequestsOpenAccess`、`PrimaryLanguage = zh-Hans` 等以 `info:` 段生成，避免再维护独立 plist 文件）。CI 里 `brew install xcodegen`（锁版本）后生成工程再 `xcodebuild`。
- 风险：XcodeGen 生成结果与手写工程在扩展嵌入关系（Embed App Extensions）上偶有坑；第 0 步验收就包含「IPA 内 appex 结构正确、装机后键盘出现在系统设置列表里」，把这个风险前置暴露。

### 4.4 CI 流水线设计

单 workflow `build-ipa.yml`（`macos-14` 或更新的 runner，手动触发 + push 触发）：

1. **checkout** 本仓库。
2. **组装 Rime 数据**：`scripts/fetch-rime-ice.sh` 按锁定的 rime-ice commit 拉取（`actions/cache` 以 commit 为 key 缓存整个组装结果，命中则跳过第 2–3 步）。
3. **预编译词库**：下载官方 librime **1.16.1** macOS 包（rime + rime-deps 两个 tar.bz2，URL 写死在脚本里），`scripts/precompile-schemas.sh` 在组装目录跑 `rime_deployer --build`，产出 `build/*.bin`；顺带记录产物总大小到构建日志（验收指标）。
4. **拉引擎包**：SPM 解析 LibrimeKit（URL+checksum 已在 `project.yml`/Package 引用中锁定；首次成功后按 vendoring 策略改指自有 Release）。
5. **生成工程并构建**：`xcodegen generate` → `xcodebuild archive -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`（Hamster 的 CI 正是这么打未签名包的，其 ci.yml 可参照；注意它的 runner 是 macos-13 + Xcode 15.0.1，我们用更新的即可）。
6. **打 IPA**：把 archive 里的 `.app` 放进 `Payload/` 压成 `.ipa`，`actions/upload-artifact` 产出。附带输出一份构建摘要（IPA 大小、RimeData 大小、librime 版本、rime-ice commit）。

缓存策略小结：rime-ice 组装+预编译结果按（rime-ice commit × librime 版本）缓存；SPM 包走 Xcode 默认缓存/单独 cache 步；**不缓存** XcodeGen 生成的工程（每次现生成，保证 project.yml 是唯一事实源）。

自编引擎的 `build-librime.yml` **不在 v1 范围**，路线 B 启用时再按 1.3 节出处新写。

---

## 5. 分步实施计划与验收点

> 每步的「验收」都需要用户在其 iPhone 上自签装机验证的，标注 📱；纯 CI 侧可验的标注 ☁️。

### 步骤 0：工程骨架 + 空键盘跑通 CI
- 内容：本骨架落仓；主 App（仅引导页）+ 键盘扩展（系统默认样式的占位键盘，能输入字母/退格）；CI 出未签名 IPA。
- 验收：☁️ CI 绿、IPA 结构含 `PlugIns/Keyboard.appex`；📱 自签装机后设置里能启用该键盘、任意 App 里能调出并打字（占位功能即可）。

### 步骤 1：引擎接入（26 键直通）
- 内容：SPM 引入 LibrimeKit；`RimeEngine` 包装层完成会话生命周期（start/stop、processKey、setInput、取 context/menu、select candidate、commit）；RimeData 先**不预编译**、走 App 内首次部署验证链路通（部署在扩展沙盒内执行）；26 键把字母/退格/空格直接透传引擎；候选栏只读展示引擎菜单并支持点选上屏。
- 验收：📱 输入 `nihao` 出现「你好」候选并可上屏；连打一句话能整句上屏；userdb 学习生效（自造词第二次出现时排位上升）；冷启动二次打开键盘无重复部署卡顿。

### 步骤 2：CI 预编译词库
- 内容：启用第 4.4 节第 2–3 步；扩展启动时检测 `.bin` 齐全则跳过部署；记录 RimeData 体积与键盘进程内存（Instruments/系统日志粗测）。
- 验收：☁️ 构建日志给出 .bin 清单与总大小；📱 全新安装后首次调出键盘即可出词（无部署等待）；打字 10 分钟无被系统杀进程（内存红线初判）；若内存吃紧，执行 2.1 节预案（下掉 tencent 词库）后复验。

### 步骤 3:26 键全键盘完整化
- 内容：候选栏展开/分页、符号与数字键盘页、中英切换（ascii_mode）、回车/空格上屏策略对齐系统键盘习惯、长按删除连删、地球键切换下一键盘（`advanceToNextInputMode`）。
- 验收：📱 日常聊天/备忘录/搜索框三类场景可用；中英混输（如 `wo yao qu Starbucks` 的英文段）行为符合预期；密码框等安全输入场景系统自动切回系统键盘（iOS 既定行为，确认不 crash 即可）。

### 步骤 4：九宫格（应用层 T9）
- 内容：按第 3.2 节实现 `T9Mapper`（音节表生成、Trie、DP 切分、pinned 音节）+ 九宫格布局 + 音节条 UI；T9 删除走重算路径；`1` 键分词。
- 验收：📱 `64426` 出「你好」；`94664486` 切分出 `zhong guo` 并出「中国」；点选音节条锁定音节后尾部切分随之修正；连删到空不残留；T9 与 26 键可一键互切且已输入内容不丢（以字母会话为中介状态）。

### 步骤 5：设置与收尾
- 内容：主 App 设置页（默认布局、模糊音开关——经 schema custom 补丁实现、设置同步状态显示）；图标与名称定版；README 写清自签安装步骤。
- 验收：📱 设置改动在键盘侧生效（或在本地模式下扩展内设置入口生效）；换一种签名工具重签后键盘仍可打字、userdb 不丢（同工具重签）/可接受丢失但不白屏（换工具）。

---

## 6. 骨架文件完成度（本轮已产出）

| 文件 | 状态 | 说明 |
|---|---|---|
| `PLAN.md` | ✅ 完成 | 本文件 |
| `README.md` | ✅ 完成 | 项目说明 + 自签安装流程占位 |
| `project.yml` | ✅ 草稿 | XcodeGen 定义：3 targets + LibrimeKit SPM 依赖 + 扩展 Info 键；bundle id 为占位符，建仓时定 |
| `.github/workflows/build-ipa.yml` | ✅ 草稿 | 按 4.4 节写；rime-ice 锁定 commit、deployer 下载地址等常量留了 TODO 注释，需首次试跑时填实 |
| `App/PinyinIMEApp.swift`、`ContentView.swift` | ✅ 占位可编译级 | 仅引导页骨架 |
| `Keyboard/KeyboardViewController.swift` | ✅ 骨架 | 占位键盘（字母直输），引擎接入点以 TODO 标明 |
| `Keyboard/RimeBridge/RimeEngine.swift` | ✅ 接口大纲 | 协议 + 值类型 + 未实现体（`fatalError` 占位改为返回空状态，编码步骤 1 落地） |
| `Keyboard/RimeBridge/RimeModels.swift` | ✅ 完成 | Candidate/Composition/Menu 值类型 |
| `Keyboard/T9/T9Mapper.swift` | ✅ 核心算法骨架 | 映射表生成 + Trie + DP 切分逻辑可运行；音节清单 `syllables.txt` 已备 |
| `Keyboard/T9/README.md` | ✅ 完成 | 设计说明（与 PLAN 第 3 节互为详略） |
| `Keyboard/Layout/*.swift` | ✅ 键位模型骨架 | 26 键与九宫格的键定义数据 |
| `RimeData/README.md` | ✅ 完成 | 数据组装说明；实际数据由 CI 生成，不入 git |
| `scripts/fetch-rime-ice.sh`、`precompile-schemas.sh` | ✅ 草稿 | 逻辑完整，常量待首次试跑填实 |
| `Vendor/README.md` | ✅ 完成 | 路线 A 引用与 vendoring 操作说明 |

未产出（有意留空，原因注明）：键盘候选栏 UI（步骤 3/4 才有真实数据可调，先写必返工）；`build-librime.yml`（路线 B 才需要）；App 图标资源（等定版名与视觉方案）。

---

## 7. 未核实事项清单

1. `t9_processor` 的确切出处（哪个插件仓库/构建提供）——imfuxiao/LibrimeKit 仓库 2026-11-04 实测 404，无法确认其插件清单；不影响 v1（应用层 T9），影响 v2 是否能直接启用雾凇 t9 方案。
2. imfuxiao/LibrimeKit 404 的原因（删除/私有/改名）未确认；Hamster 主仓库最后推送 2025-05，其现行 App Store 版本是否已换构建来源未核查（与本项目无关，仅作背景风险记录）。
3. CI 预编译 `.bin`（macOS deployer 1.16.1 产出）被 iOS 端 librime 1.16.1 运行时直接加载的兼容性——原理上是 Rime 的标准跨平台用法（Hamster 脚本留有同命令），但**未经我们自己的构建+真机验证**，步骤 2 的验收就是为它设的；若不兼容，回退为 App 内首次部署（步骤 1 的路径），功能不受影响、仅首次启动慢。
4. 预编译后 RimeData 的确切体积与键盘扩展在 iOS 27 上的内存上限数值——都需步骤 2 实测；iOS 键盘扩展内存上限的历史数值（约 70 MB）未在当前系统版本上核实。
5. zhanggenlove/LibrimeKit 的 Swift 糖衣 API 是否覆盖我们需要的全部会话操作（细粒度 menu 分页、setInput 语义）——接口大纲按 C API 设计了下沉路径，步骤 1 编码时以其仓库源码为准核对；其 ObjC shim 的存在已确认。
6. XcodeGen 生成「App + 键盘扩展」嵌入关系在当前 Xcode 版本下的正确性——步骤 0 验收前置验证。
7. 雾凇默认文件清单与 librime 1.16.1 的细节兼容（如 schema 中引用的个别组件在该版本的可用性）——首次部署日志即能暴露，步骤 1 验收覆盖。
8. rime-ice 的 GPL-3.0 对「自签分发给他人」的确切义务边界——仅影响分发场景，个人自用不涉及；若将来要给别人用，先做合规核查。

---

## 8. 证据索引（本轮核查的一手来源）

- Hamster 仓库与脚本：<https://github.com/imfuxiao/Hamster>（`librimeFramework.sh`、`Makefile`、`.github/workflows/ci.yml`、`Packages/RimeKit/Package.swift`、`InputSchemaBuild.sh`、`Packages/HamsterKit/Sources/T9/T9Constants.swift`、`Packages/HamsterKeyboardKit/Sources/RimeContext/RimeContext.swift`、`.../View/StandarKeyboard/ChineseNineGridKeyboard.swift`）
- imfuxiao/LibrimeKit（404 实测，2026-11-04）：<https://github.com/imfuxiao/LibrimeKit>
- zhanggenlove/LibrimeKit：<https://github.com/zhanggenlove/LibrimeKit>（README 版本表、Package.swift 的 binaryTarget+checksum、THIRD_PARTY_LICENSES.md；其实测二进制 strings 结果为本轮本地验证）
- librime 官方：<https://github.com/rime/librime>（`.gitmodules` deps 清单、Releases 的 macOS 包与 1.16.1/1.17.0 版本资产）
- 自编路线参考：<https://github.com/imfuxiao/boost-iosx>、<https://github.com/amorphobia/LibrimeKit>、<https://github.com/chenqinggang001/LibrimeKit-ios12>
- 雾凇拼音：<https://github.com/iDvel/rime-ice>（`t9.schema.yaml` 文件头与 processors、`cn_dicts/` 文件体积、README 的 lua 依赖 FAQ 与九键脚注、LICENSE 为 GPL-3.0）

---

## 9. 实现轮 1（2026-11-04）：引擎真实现 + 26 键键盘 + 设置页

> 本节为实现轮 1 的追记：API 路线以当轮实拉源码为据（LibrimeKit tag v0.1.0 的
> Package.swift、Sources/Swift 全部文件、Sources/ObjC 的 lrk_api.h/.m 本地通读；
> 另解压本地 Vendor 的 librime.xcframework.zip 核对头文件构成）。本轮代码
> **未经编译验证**——CI 是唯一编译器，下述「预计炸点」即为此设。

### 9.1 API 路线结论：用糖衣层 + API() 逃生口，不直桥 C API

- **SPM 结构**（Package.swift 实证）：包名/product 均为 `LibrimeKit`；Swift target
  `LibrimeKit`（Sources/Swift）依赖 ObjC target `RimeKitObjC`（Sources/ObjC，
  LRK* 类型，头在 include/）；9 个 binaryTarget（remote zip+checksum）。
  糖衣各文件带 `@_exported import RimeKitObjC`，故业务侧只写 `import LibrimeKit`。
- **README 的用法示例是假的**：README 写的 `Rime.shared.startService(...)`、
  `process(input:)` 在 v0.1.0 源码中不存在。实际入口是
  `Rime.createTraits(sharedSupportDir:userDataDir:)` →
  `Rime.shared.start(_:maintenance:fullCheck:)`（内部 setup→initialize→maintenance）。
- **糖衣覆盖面**：start/createSession/isRunning、inputKey/inputKeyCode、
  candidateList（走候选迭代器、返回跨页全量）、candidateListWithIndex、
  selectCandidateOnCurrentPage、highlightCandidateOnCurrentPage、changePage、
  context()/status() 快照、getInputKeys/cleanComposition/commitComposition/
  getCommitText、isAsciiMode()/asciiMode(_:)、setSchema/currentSchema、
  deploy 回调注册。协议所需操作全部有着落。
- **两处下沉逃生口**（`Rime.shared.API()` → LRKAPI，糖衣未暴露）：
  `simulateKeySequence(_:andSession:)` 实现协议的 setInput（先 cleanComposition
  再整串送入；T9 喂入的只有字母与分词符 '，无 RimeSimulateKeySequence 的
  `{...}` 特殊记法，语义安全）；`syncUserData()` 实现 stop 的 userdb 落盘。
- **不走 C API 的理由**：librime.xcframework.zip 内确实带完整 rime_api.h，
  但 zip 内**没有 module.modulemap**，且该 binaryTarget 在 SPM 里只是被
  RimeKitObjC 链接依赖、不向消费方暴露头模块——上层 Swift 无从 import。
  糖衣+逃生口是这条分发形态下的唯一正道，C 头仅作语义参照。
- **实测纠正两条糖衣注释**（以 lrk_api.m 实现为准）：
  ① `processKey(_:)` 的 ObjC 实现只取字符串首字节（ASCII 场景够用，
  我们字母键一律走 inputKeyCode 的 keysym 路径，不用它）；
  ② `candidateListWithIndex` 的 index 走 `RimeCandidateListFromIndex`，
  是 0 起的全量下标，糖衣注释写的「1-based」与实现矛盾——本轮展开列表
  直接用 candidateList() 全量，不依赖该函数。
- **选词必须用 on-current-page 版**：lrk_api.h 注释实测记录，旧
  `select_candidate` 在 rime_ice 上会被静默忽略；翻页必须用 `changePage`
  （雾凇未绑定 XK_Page_Down 键位，发键码翻页同样无效）。两者本轮均已按此实现。
- **会话创建时机**：lrk_api.m 的 createSession 带有 FIXME——部署完成前调用
  可能崩溃。故启动顺序钉死为：后台线程跑 start（含 maintenance，同为
  同步 join 语义）→ 回主线程 createSession → selectSchema(rime_ice)。
- **stop 不 finalize**：糖衣 shutdown 注释明示 librime 进程级单例 finalize 后
  同进程不可再 setup；stop 只做 syncUserData + 不销毁，随扩展进程回收自然结束。
- **traits 字段有效面**：lrk_api.m 的 `rimeTraits:` 转换只拷贝
  shared/user/distribution×3/appName/prebuilt/staging 八个字段；
  LRKTraits 上的 modules/minLogLevel/logDir 设了也不生效（v0.1.0 实测），
  本轮不设。appName 覆写为 `rime.pinyinime`（工厂默认 rime.moocat）。

### 9.2 部署策略

- sharedDataDir = appex bundle 内 `SharedData/`（CI 预编译 .bin 已在其中，
  由 project.yml 的 postBuildScript 拷入）；userDataDir = 扩展沙盒
  `Application Support/RimeUser/`（不用 App Group，理由同 4.2）。
- maintenance 只在 userDataDir 无 `.pinyinime-deploy-v1.done` 标记时跑一次
  （fullCheck=false）；跑完（无论个别 schema 成败）即写标记，避免每次调出
  键盘都付出全量检查成本；SharedData 的 .bin 齐全时这轮维护应近乎瞬时。
- UI 侧：部署完成前显示「正在准备词库…」，不喂任何按键，从根上避开
  维护线程与输入线程并发访问 librime；onReady 回主线程后才建会话、亮键盘。

### 9.3 本轮落地清单

- `Keyboard/RimeBridge/RimeEngine.swift`：协议补 isReady/onReady/
  allCandidates() 三项；`LibrimeKitRimeEngine` 全实现替换原
  UnavailableRimeEngine 占位（已确认无其他文件引用该占位类）；新增 RimeKey
  keysym 常量表。
- `Keyboard/CandidateBar/CandidateBarView.swift`（新）：候选条（preedit +
  横向滚动全量候选 + 高亮 + 展开按钮）与展开列表 CandidateListView（逐行
  点选、含注释列、收起按钮）。
- `Keyboard/Views/KeyButton.swift`（新）：按下变色（动态色、深浅适配）、
  退格长按连删（0.45s 后 55ms 连发）、多点触控独立计时。
- `Keyboard/Views/FullKeyboardView.swift`（新）：按 FullKeyboardLayout 模型
  手工 frame 布局（权重分宽）；地球键以 target/action 直挂
  handleInputModeList（.allTouchEvents）；shift/ascii/回车文案状态外观。
- `Keyboard/Layout/SymbolLayout.swift`（新）+ `Views/SymbolKeyboardView.swift`（新）：
  数字行 + 中文标点两行 + 补充行；点击语义为「先提交组合串，再直插字面量」
  （全角标点无 keysym 可透传，见文件注释）。
- `Keyboard/KeyboardViewController.swift`：全量重写——引擎装配/启动、
  refresh 统一回收上屏文本、候选全量下标↔（翻页+页内下标）换算、
  空格选高亮/回车透传/退格分流（组合内走引擎、否则删文档）、符号页切换、
  展开列表高度切换、九宫格占位页与布局切换持久化（写 SettingsBridge）。
- `project.yml`：PinyinKeyboard 的 sources 追加 `App/SettingsBridge.swift`
  单文件（双 target 共用同一份设置桥实现；targets/SPM/Info 结构未动）。
- `App/ContentView.swift`：启用教程四步、默认布局 Picker（写
  SettingsBridge）、同步状态明示（本地模式下注明键盘设置优先）、关于页
  （版本/引擎/词库 + 许可证：librime 与 LibrimeKit 均为 **BSD-3-Clause**
  ——注意不是 LGPL；雾凇 GPL-3.0；Boost BSL-1.0；leveldb BSD-3；
  marisa-trie BSD-2/LGPL-2.1 双许可；OpenCC Apache-2.0；yaml-cpp MIT）。

### 9.4 已知风险（按可能炸的顺序）

1. **SPM 链接面**：`import LibrimeKit` 后 LRK* 类型的可见性依赖糖衣的
   `@_exported import`，常规成立；若个别符号（如 LRKTraits 属性）不可见，
   备选是在扩展内加一行 `import RimeKitObjC`（product 内 target 可直引）。
2. **handleInputModeList 的 #selector 解析**：`#selector(handleInputModeList(from:with:))`
   是苹果文档的标准写法，但若当前 SDK 的 Swift 名称有出入会直接编译失败——
   这是本轮最可能的单点编译错误，失败则改用 advanceToNextInputMode() 兜底。
3. **ObjC 无 nullability 头的类型推断**：LRKContext/LRKMenu/LRKCandidate 的
   属性在 Swift 侧为 IUO，本轮已按可空防御性写（`?.`/`??`）；若某个属性被
   推断为非可选，`??` 会报警告甚至错误，按报错逐个收紧即可。
4. **高度约束**：view.heightAnchor 常量约束（优先级 999）是社区惯用做法；
   若与系统 inputView 的固有高度冲突，可能出现约束警告或键盘高度不符——
   真机验收时重点看（展开列表 308+44 是否被系统截断）。
5. **首次维护耗时与标记语义**：若 CI 预编译 .bin 与运行时版本细节不兼容，
   首次 maintenance 仍可能全量重编（慢但可用）；标记在维护后即写，
   个别 schema 失败不会重试出词问题——失败会以「不出候选」暴露，下一轮
   可加诊断页读取部署日志定位。
6. **高亮全量下标换算**：页起始下标由「末页倒推 / 页号×本页数」推得，
   页大小靠 cachedPageSize 缓存自引擎满页；若雾凇在某种模式下页大小可变
   （如联想页），高亮位置与翻页目标可能偏一页——真机重点验翻到第 2 页点选。
7. **进程内重启**：扩展进程被系统回收后是新进程，setup 重新走全流程
   （标记在盘上，不重跑部署）；同进程内 stop→start 不被支持也不需要。
8. **内容 EdgeInsets 等旧 API**：UIButton.contentEdgeInsets 在新 SDK 为
   弃用警告（不阻断编译）；本轮为保 iOS 16 兼容未用 UIButton.Configuration。
