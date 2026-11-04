import Foundation
import LibrimeKit

/// Rime 引擎桥接层接口（对 UI / T9 层的唯一契约）。
///
/// ## API 路线结论（实现轮 1 核查，证据见 PLAN.md「实现轮 1」追记）
///
/// 底层包 `zhanggenlove/LibrimeKit` v0.1.0 的真实 API 面（以其 tag v0.1.0 源码为准，
/// README 里的 `startService(...)` / `process(input:)` 示例在源码中并不存在，勿信）：
/// - SPM product 名 `LibrimeKit`；target `LibrimeKit`（Swift 糖衣，Sources/Swift）
///   依赖 target `RimeKitObjC`（ObjC shim，LRK* 类型）；糖衣文件均带
///   `@_exported import RimeKitObjC`，故 `import LibrimeKit` 即可见 LRK 类型。
/// - Swift 糖衣 `Rime.shared` 已覆盖本协议所需绝大部分操作：
///   start(setup+initialize+maintenance)、createSession、inputKey/inputKeyCode、
///   candidateList（全量迭代）、context()/status() 快照、
///   selectCandidateOnCurrentPage、changePage、commitComposition、
///   getCommitText、cleanComposition、asciiMode(_:)、setSchema。
/// - 糖衣未暴露的两处经逃生口 `Rime.shared.API()`（返回 LRKAPI）下沉 ObjC 层：
///   `simulateKeySequence`（setInput 实现）、`syncUserData`（userdb 持久化）。
/// - 因此**不需要**直接桥接 librime C API；xcframework 虽自带 rime_api.h，
///   但其 zip 内无 module.modulemap，SPM binaryTarget 也不会把该头暴露给上层，
///   强行 import C 模块反而无路可走——糖衣+逃生口是本包唯一正道。
///
/// 生命周期与目录约定（PLAN.md 4.2）：
/// - sharedDataDir：扩展 bundle 内的只读目录（方案 + CI 预编译 .bin）；
/// - userDataDir：扩展沙盒内可写目录（userdb 在此生成），不依赖 App Group。
public protocol RimeEngine: AnyObject {
    /// 引擎是否已完成启动（含首次部署）并建好会话，可接受按键。
    var isReady: Bool { get }
    /// 启动完成（成功或失败）后在主线程回调一次，供 UI 从「准备中」切换到键盘。
    var onReady: (() -> Void)? { get set }

    /// 启动引擎（异步：内部在后台线程做 setup/initialize/必要的维护部署，
    /// 完成后置 isReady 并回调 onReady；重复调用无副作用）。
    func start(sharedDataDir: URL, userDataDir: URL) throws
    /// 持久化用户数据（同步 userdb 落盘）。不 finalize 引擎——librime 是进程级
    /// 单例，finalize 后同进程不可再 setup（LibrimeKit 源码 shutdown 注释明示），
    /// 扩展进程存活期间 stop 只做同步、不做销毁。
    func stop()

    /// 切换方案，如 "rime_ice"。T9 不切方案（应用层处理，仍用 rime_ice）。
    func setSchema(_ schemaId: String)
    var currentSchema: String { get }

    /// 以 ASCII 模式（英文）开关，对应 Rime 的 ascii_mode option。
    var isAsciiMode: Bool { get set }

    // MARK: 按键与输入

    /// 透传一个按键（X11 keysym + 修饰位，与 Rime C API 的 process_key 对齐）。
    /// 返回 true 表示引擎已消费。26 键路径使用。
    @discardableResult
    func processKey(code: UInt32, modifiers: UInt32) -> Bool

    /// 整串设置当前输入（T9 层切分变化时用：以 ' 连接的音节串，如 "ni'hao"）。
    func setInput(_ input: String)

    /// 清空当前组合串（不提交）。
    func clearComposition()

    // MARK: 状态读取

    var composition: RimeComposition { get }
    /// 当前页候选菜单（分页元数据 + 本页候选）。
    var menu: RimeMenu { get }
    /// 一次 context 读取同时产出 composition 与 menu（实现轮 4 卡顿优化：
    /// composition / menu 两属性各调一次 RimeGetContext，每键两次全量
    /// 快照是浪费；refresh 路径改走本方法只取一次）。
    func snapshot() -> (composition: RimeComposition, menu: RimeMenu)
    /// 有界取候选：返回全量下标 [from, from+count) 的切片（实现轮 4 新增）。
    /// 候选栏每键只取前若干条，不再全量迭代（见 allCandidates 的说明）。
    func candidatesSlice(from: Int, count: Int) -> [RimeCandidate]
    /// 全部候选（跨页）。内部走候选迭代器全量枚举，量级可达数百，
    /// **不要在每键路径调用**（实现轮 4 起仅保留定义，UI 已改用
    /// candidatesSlice 有界取）。
    func allCandidates() -> [RimeCandidate]
    /// 已提交待取走的文本（上屏文本由 UI 侧在状态变化后 drain）。
    func drainCommitText() -> String?

    // MARK: 候选操作

    /// 选中当前页第 index 个候选（页内下标；可能触发部分上屏，剩余输入保留）。
    func selectCandidate(at index: Int)
    func nextPage()
    func previousPage()

    /// 显式提交当前组合串（空格、回车的上屏策略由 UI 决定调用时机）。
    func commitCurrentComposition()
}

/// X11 keysym 常量（与 librime 的 process_key 入参一致；数值取自 X11 keysymdef.h，
/// LibrimeKit 的 lrk_api.h 注释亦以 0xff56/0xff55 指代 Page_Down/Page_Up）。
public enum RimeKey {
    public static let backspace: UInt32 = 0xff08
    public static let tab: UInt32 = 0xff09
    public static let `return`: UInt32 = 0xff0d
    public static let escape: UInt32 = 0xff1b
    public static let pageUp: UInt32 = 0xff55
    public static let pageDown: UInt32 = 0xff56
    public static let space: UInt32 = 0x20
    /// 修饰位：kShiftMask（X11 状态掩码，与 Rime process_key 的 modifier 约定一致）。
    public static let shiftMask: UInt32 = 0x1
    public static let controlMask: UInt32 = 0x4
}

/// 基于 LibrimeKit（librime 1.16.1）的 RimeEngine 真实现。
public final class LibrimeKitRimeEngine: RimeEngine {
    /// 固定方案（PLAN 定版：雾凇拼音）。
    public static let fixedSchemaId = "rime_ice"
    /// 首次部署完成标记文件名（位于 userDataDir 内）。SharedData 已由 CI 预编译，
    /// 维护（maintenance）只在无此标记时跑一次，避免每次调出键盘都做全量检查。
    private static let deployMarkerName = ".pinyinime-deploy-v1.done"

    public private(set) var isReady = false
    public var onReady: (() -> Void)?

    private var startInFlight = false
    private var schemaId = LibrimeKitRimeEngine.fixedSchemaId
    private var asciiModeCache = false

    public init() {}

    // MARK: 生命周期

    public func start(sharedDataDir: URL, userDataDir: URL) throws {
        guard !isReady, !startInFlight else { return }
        startInFlight = true

        let fm = FileManager.default
        try fm.createDirectory(at: userDataDir, withIntermediateDirectories: true)

        // traits：用糖衣工厂方法生成后覆写发行信息与 app_name。
        // 注意：LRKTraits 的 modules/minLogLevel/logDir 字段在 v0.1.0 的
        // rimeTraits: 转换实现里并未被拷贝（实测 lrk_api.m），设了也不生效，
        // 故此处只设真正生效的字段；modules 用引擎默认值（core/dict/gears/lua）。
        let traits = Rime.createTraits(
            sharedSupportDir: sharedDataDir.path,
            userDataDir: userDataDir.path
        )
        traits.distributionName = "拼音输入法"
        traits.distributionCodeName = "PinyinIME"
        traits.distributionVersion = "0.3.0"
        // 形如 "rime.<x>"，前缀让 librime 识别为自家日志命名（工厂默认 rime.moocat）。
        traits.appName = "rime.pinyinime"

        let markerURL = userDataDir.appendingPathComponent(Self.deployMarkerName)
        let needsMaintenance = !fm.fileExists(atPath: markerURL.path)

        // start(maintenance:) 内部顺序为 setup → initialize → startMaintenance，
        // 而 ObjC 层 startMaintenance 会 join 维护线程（同步阻塞至部署结束），
        // 因此整段必须放后台线程；且 LRKAPI 的 createSession 实现带有
        // 「部署完成前调用可能崩溃」的 FIXME 注释——会话创建务必等维护返回后
        // 在主线程执行，本类正是这样排序的。部署未完成前 UI 显示准备中、不喂按键，
        // 故不存在维护线程与按键线程并发访问 librime 的窗口。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Rime.shared.start(traits, maintenance: needsMaintenance, fullCheck: false)
            DispatchQueue.main.async {
                guard let self else { return }
                Rime.shared.createSession()
                _ = Rime.shared.setSchema(Self.fixedSchemaId)
                if needsMaintenance {
                    // 部署跑完即写标记；即使个别 schema 部署失败，引擎仍可进入可用态
                    // （失败会在出词时暴露并在后续轮处理），不因标记缺失而每次全量重跑。
                    FileManager.default.createFile(atPath: markerURL.path, contents: nil)
                }
                self.startInFlight = false
                self.isReady = true
                self.onReady?()
            }
        }
    }

    public func stop() {
        guard isReady else { return }
        // 只同步 userdb 落盘，不 destroySession/finalize（理由见协议注释）。
        _ = Rime.shared.API().syncUserData()
    }

    // MARK: 方案与模式

    public func setSchema(_ schemaId: String) {
        self.schemaId = schemaId
        guard isReady else { return }
        _ = Rime.shared.setSchema(schemaId)
    }

    public var currentSchema: String {
        guard isReady else { return schemaId }
        let id = Rime.shared.status().schemaId
        return (id?.isEmpty == false) ? id! : schemaId
    }

    public var isAsciiMode: Bool {
        get {
            guard isReady else { return asciiModeCache }
            asciiModeCache = Rime.shared.status().isASCIIMode
            return asciiModeCache
        }
        set {
            asciiModeCache = newValue
            guard isReady else { return }
            _ = Rime.shared.asciiMode(newValue)
        }
    }

    // MARK: 按键与输入

    @discardableResult
    public func processKey(code: UInt32, modifiers: UInt32) -> Bool {
        guard isReady else { return false }
        return Rime.shared.inputKeyCode(Int32(bitPattern: code),
                                        modifier: Int32(bitPattern: modifiers))
    }

    public func setInput(_ input: String) {
        guard isReady else { return }
        // 糖衣层没有 setInput：先清组合串，再经逃生口用 RimeSimulateKeySequence
        // 整串送入（序列内仅拼音字母与分词符 '，无 { } 特殊记法，语义安全）。
        Rime.shared.cleanComposition()
        guard !input.isEmpty else { return }
        Rime.shared.API().simulateKeySequence(input, andSession: Rime.shared.getSession())
    }

    public func clearComposition() {
        guard isReady else { return }
        Rime.shared.cleanComposition()
    }

    // MARK: 状态读取

    public var composition: RimeComposition {
        guard isReady else { return .empty }
        return Self.makeComposition(ctx: Rime.shared.context(),
                                    input: Rime.shared.getInputKeys())
    }

    public var menu: RimeMenu {
        guard isReady else { return .empty }
        return Self.makeMenu(ctx: Rime.shared.context())
    }

    public func snapshot() -> (composition: RimeComposition, menu: RimeMenu) {
        guard isReady else { return (.empty, .empty) }
        // 单次 RimeGetContext（糖衣 context()）同时喂 composition 与 menu。
        let ctx = Rime.shared.context()
        return (Self.makeComposition(ctx: ctx, input: Rime.shared.getInputKeys()),
                Self.makeMenu(ctx: ctx))
    }

    private static func makeComposition(ctx: LRKContext, input: String) -> RimeComposition {
        RimeComposition(input: input, preedit: ctx.composition?.preedit ?? "")
    }

    private static func makeMenu(ctx: LRKContext) -> RimeMenu {
        guard let lrkMenu = ctx.menu else { return .empty }
        // LRKMenu.candidates 恒为空（LibrimeKit 不拷贝，见 RimeModels 注释）；
        // 分页换算改用引擎报告的 pageSize 与 numCandidates（当前页候选数）。
        let pageSize = max(Int(lrkMenu.pageSize), 1)
        let pageCount = Int(lrkMenu.numCandidates)
        let highlighted = Int(lrkMenu.highlightedCandidateIndex)
        return RimeMenu(
            candidates: [],
            pageNumber: Int(lrkMenu.pageNo),
            isLastPage: lrkMenu.isLastPage,
            pageSize: pageSize,
            currentPageCandidateCount: pageCount,
            highlightedIndex: (highlighted >= 0 && highlighted < pageCount) ? highlighted : nil
        )
    }

    public func candidatesSlice(from: Int, count: Int) -> [RimeCandidate] {
        guard isReady, from >= 0, count > 0 else { return [] }
        // 糖衣 getCandidate(index:count:) → ObjC getCandidateWithIndex：
        // 以 RimeCandidateListFromIndex 定位、iterator.index（0 起全量下标）
        // 为界收集 [from, from+count)，迭代量与 count 成正比而非总量。
        return Self.mapCandidates(Rime.shared.getCandidate(index: from, count: count))
    }

    public func allCandidates() -> [RimeCandidate] {
        guard isReady else { return [] }
        // 糖衣 candidateList() 走 RimeCandidateListBegin 迭代器，返回跨页全量候选。
        return Rime.shared.candidateList().map {
            RimeCandidate(text: $0.text, comment: $0.comment.isEmpty ? nil : $0.comment)
        }
    }

    public func drainCommitText() -> String? {
        guard isReady else { return nil }
        // 糖衣 getCommitText 内部走 RimeGetCommit：取走即清空，空串表示无提交。
        let text = Rime.shared.getCommitText()
        return text.isEmpty ? nil : text
    }

    // MARK: 候选操作

    public func selectCandidate(at index: Int) {
        guard isReady else { return }
        // 必须用 on-current-page 版本：旧的 select_candidate 在 rime_ice 上会被
        // 静默忽略（LibrimeKit 的 lrk_api.h 注释实测记录）。
        _ = Rime.shared.selectCandidateOnCurrentPage(index: index)
    }

    public func nextPage() {
        guard isReady else { return }
        _ = Rime.shared.changePage(backward: false)
    }

    public func previousPage() {
        guard isReady else { return }
        _ = Rime.shared.changePage(backward: true)
    }

    public func commitCurrentComposition() {
        guard isReady else { return }
        _ = Rime.shared.commitComposition()
    }

    // MARK: 工具

    private static func mapCandidates(_ list: [LRKCandidate]) -> [RimeCandidate] {
        list.map { c in
            let comment = c.comment ?? ""
            return RimeCandidate(text: c.text ?? "", comment: comment.isEmpty ? nil : comment)
        }
    }
}
