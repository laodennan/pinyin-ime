import Foundation

/// 引擎无关的候选值类型（桥接层向 UI 暴露的唯一数据形态，
/// 使 UI 不直接依赖 LibrimeKit/C API 的类型）。
public struct RimeCandidate: Equatable {
    public let text: String
    /// 候选注释。Rime 中常为对应拼音——T9 层用它反推已消耗的数字位数（见 PLAN.md 3.2）。
    public let comment: String?
    public init(text: String, comment: String?) {
        self.text = text
        self.comment = comment
    }
}

/// 当前输入组合串状态（对应 Rime context 的 composition）。
public struct RimeComposition: Equatable {
    /// 原始输入（如 "nihao" 或带分词符的 "ni'hao"）。
    public let input: String
    /// 引擎给出的预编辑文本（如 "ni hao"，带音节分隔空格）。
    public let preedit: String
    public init(input: String, preedit: String) {
        self.input = input
        self.preedit = preedit
    }

    public static let empty = RimeComposition(input: "", preedit: "")
}

/// 一页候选菜单（对应 Rime context 的 menu）。
public struct RimeMenu: Equatable {
    /// 当前页候选。注意：LibrimeKit 的 getContext 出于性能**不拷贝** menu 的
    /// 候选数组（lrk_api.m 注释明示），桥接层拿到的恒为空——UI 显示用的
    /// 全量候选走 allCandidates()，分页换算只用下面三个引擎报告值，
    /// 绝不要拿 candidates.count 当页大小（v0.2 选字错位的根因）。
    public let candidates: [RimeCandidate]
    public let pageNumber: Int
    public let isLastPage: Bool
    /// 引擎报告的每页候选数（schema 的 menu.page_size，雾凇为 5）。
    public let pageSize: Int
    /// 当前页实际候选数（末页可能小于 pageSize）。
    public let currentPageCandidateCount: Int
    /// 当前高亮候选在整页中的下标（无则为 nil）。
    public let highlightedIndex: Int?
    public init(candidates: [RimeCandidate], pageNumber: Int, isLastPage: Bool, pageSize: Int, currentPageCandidateCount: Int, highlightedIndex: Int?) {
        self.candidates = candidates
        self.pageNumber = pageNumber
        self.isLastPage = isLastPage
        self.pageSize = pageSize
        self.currentPageCandidateCount = currentPageCandidateCount
        self.highlightedIndex = highlightedIndex
    }

    public static let empty = RimeMenu(candidates: [], pageNumber: 0, isLastPage: true, pageSize: 5, currentPageCandidateCount: 0, highlightedIndex: nil)
}
