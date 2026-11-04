# RimeData（运行时数据，不入 git）

键盘扩展的 `SharedData/` 目录由 CI 组装，不在本仓库提交（体积大）：

1. `scripts/fetch-rime-ice.sh <commit>`：拉取锁定的雾凇拼音（rime-ice）版本，
   组装到 `Keyboard/SharedData/`（含其 LICENSE）。
2. `scripts/precompile-schemas.sh`：用官方 librime 同版本（1.16.1）的 macOS
   `rime_deployer --build` 生成 `SharedData/build/*.bin`，首次启动免部署。

运行时目录分工（PLAN.md 4.2）：

- `shared_data_dir` = 扩展 bundle 内的 `SharedData/`（只读，含预编译 .bin）；
- `user_data_dir` = 扩展沙盒 `Library/RimeUserData/`（可写，userdb 在此生成）。

本地开发想跑通步骤 1（App 内首次部署路径）时，可手工执行第 1 步脚本
把原始 yaml 放进 `SharedData/`，跳过预编译——功能等价，仅首次启动要等部署。
