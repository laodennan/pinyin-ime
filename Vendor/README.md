# 引擎包：LibrimeKit（路线 A）

引用：`project.yml` 中以 SwiftPM 依赖 `https://github.com/zhanggenlove/LibrimeKit`（from 0.1.0）。
其实测性质见 PLAN.md 1.2：librime 1.16.1 静态 xcframework ×9（librime、boost×4、leveldb、
marisa、opencc、yaml-cpp），已内嵌 librime-lua，不含 t9_processor（九宫格走应用层）。

## Vendoring 策略（防上游消失，必做）

教训：Hamster 依赖的 imfuxiao/LibrimeKit 仓库已 404（PLAN.md 1.1）。
本项目首次 CI 跑通后立即执行：

1. 下载该版本 Release 的全部 `*.xcframework.zip`（9 个）与对应 sha256；
2. 上传到**本项目自有仓库**的 Release（如 tag `librimekit-v0.1.0-vendored`），
   注明来源与上游许可证（其 THIRD_PARTY_LICENSES.md 为 stub，分发前需补齐全文）；
3. 把 `project.yml` 的包引用切换为 vendored 地址（或改成本地 binaryTarget 路径），
   并在 PLAN.md 记录切换日期。

在此之前，构建依赖上游可用性——属已知风险，首次试跑时优先处理。
