import Foundation

/// Rime 引擎桥接层接口（大纲，步骤 1 落地实现）。
///
/// 三层结构参照 Hamster 的 RimeKit（PLAN.md 1.1）：
/// C API（rime_api.h）→ ObjC 薄封装 → Swift API。
/// 本项目优先使用 LibrimeKit 自带的 Swift/ObjC 封装（其存在已核实），
/// 本协议即是对上层（键盘 UI、T9 层）的唯一契约：
/// 若糖衣 API 不够用，实现内部下沉到 LibrimeKit 暴露的 C API，上层不感知。
///
/// 生命周期与目录约定（PLAN.md 4.2）：
/// - sharedDataDir：扩展 bundle 内的只读目录（方案 + CI 预编译 .bin）；
/// - userDataDir：扩展沙盒内可写目录（userdb 在此生成），不依赖 App Group。
public protocol RimeEngine: AnyObject {
    /// 初始化引擎并启动维护（部署检查）。sharedDataDir 中 .bin 齐全时应近乎瞬时。
    func start(sharedDataDir: URL, userDataDir: URL) throws
    /// 停止引擎（扩展被系统回收前调用，确保持久化 userdb）。
    func stop()

    /// 切换方案，如 "rime_ice"。T9 不切方案（应用层处理，仍用 rime_ice）。
    func setSchema(_ schemaId: String)
    var currentSchema: String { get }

    /// 以 ASCII 模式（英文）开关，对应 Rime 的 ascii_mode option。
    var isAsciiMode: Bool { get set }

    // MARK: 按键与输入

    /// 透传一个按键（keysym + 修饰位语义与 Rime C API 的 process_key 对齐）。
    /// 返回 true 表示引擎已消费。26 键路径使用。
    @discardableResult
    func processKey(code: UInt32, modifiers: UInt32) -> Bool

    /// 整串设置当前输入（T9 层切分变化时用：以 ' 连接的音节串，如 "ni'hao"）。
    func setInput(_ input: String)

    /// 清空当前组合串（不提交）。
    func clearComposition()

    // MARK: 状态读取

    var composition: RimeComposition { get }
    var menu: RimeMenu { get }
    /// 已提交待取走的文本（上屏文本由 UI 侧在状态变化后 drain）。
    func drainCommitText() -> String?

    // MARK: 候选操作

    /// 选中当前页第 index 个候选（可能触发部分上屏，剩余输入保留）。
    func selectCandidate(at index: Int)
    func nextPage()
    func previousPage()

    /// 显式提交当前组合串的首选/原文（空格、回车的上屏策略由 UI 决定调用时机）。
    func commitCurrentComposition()
}

/// 步骤 1 落地时以 LibrimeKit 实现此协议；骨架期仅提供不可用占位实现用于编排 UI。
public final class UnavailableRimeEngine: RimeEngine {
    public init() {}
    public func start(sharedDataDir: URL, userDataDir: URL) throws {}
    public func stop() {}
    public func setSchema(_ schemaId: String) {}
    public var currentSchema: String { "rime_ice" }
    public var isAsciiMode: Bool = false
    public func processKey(code: UInt32, modifiers: UInt32) -> Bool { false }
    public func setInput(_ input: String) {}
    public func clearComposition() {}
    public var composition: RimeComposition { .empty }
    public var menu: RimeMenu { .empty }
    public func drainCommitText() -> String? { nil }
    public func selectCandidate(at index: Int) {}
    public func nextPage() {}
    public func previousPage() {}
    public func commitCurrentComposition() {}
}
