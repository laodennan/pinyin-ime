# 自研拼音输入法（Rime 引擎）

个人自用的 iOS 拼音输入法：主 App + 键盘扩展，引擎为 librime（经 LibrimeKit 的 SwiftPM 二进制包引入），
方案与词库为雾凇拼音（rime-ice），支持 26 键全键盘与九宫格（应用层 T9）两种布局。

完整路线论证、证据与分步计划见 [PLAN.md](PLAN.md)。

## 构建

- CI：GitHub Actions（macOS runner）执行 `.github/workflows/build-ipa.yml`，
  产出**未签名 IPA**（artifact 下载）。
- 本地（有 Mac 时）：`xcodegen generate` 后用 Xcode 打开生成的工程构建。

## 安装（自签）

1. 从 CI artifact 下载未签名 IPA；
2. 用自己的签名工具签名（注意：不同工具可能改写 Bundle ID / App Group，
   本工程已按「键盘扩展自包含、userdb 放扩展沙盒」设计，见 PLAN.md 4.2）；
3. 装机后到「设置 → 通用 → 键盘 → 键盘 → 添加新键盘」启用，
   并按需开启「允许完全访问」（设置同步等增强功能需要；核心打字不依赖）。

## 许可说明

- 本工程代码：个人项目，未定许可。
- librime：BSD-3-Clause；其依赖见 PLAN.md 1.2 节清单。
- 雾凇拼音（rime-ice）：GPL-3.0，CI 拉取时保留其 LICENSE 与出处。
