import Foundation

/// 九宫格键位模型（仅数据）。实现轮 4 起照苹果原生简体拼音九宫格：
/// 整宽 5 列 × 4 行、无左侧音节条、无右侧功能列。字母键进 T9Session 的
/// 数字串（键面只标字母组），不直接透传引擎（见 PLAN.md 3.2）。
public enum NineGridKeyAction: Equatable {
    case digit(Int)            // 2–9（键面 ABC…WXYZ）：进 T9 数字串（VC 解释）
    case symbolsPage           // 123 / #@¥：打开符号页（符号页签）
    case symbolsEmojiPage      // 😊：打开符号页并切到表情页签
    case punctuation           // ，。？！：点按插「，」；长按变体由视图走 onVariantInput
    case separator             // 分隔：T9 数字串活跃时插入分词断点（VC 解释）
    case backspace             // T9 语义删除：弹一位数字后重算切分
    case spaceOrCommit         // 选定：上屏首选 / 无组合时空格；长按为光标触控板（视图层手势）
    case enter                 // 确认（跨两行）：回车语义，文案走 VC 的情境标题
    case toggleAscii           // 中英切换：点按切中/英；长按切回 26 键（视图层手势直接发 switchToFull26）
    case toggleSyllables       // 选拼音：手动开关候选栏顶部的音节选项行
    case switchToFull26        // 切回 26 键（由中英键长按手势发出）
    case nextKeyboard          // 地球键
}

public struct NineGridKeySpec: Equatable {
    public let label: String
    /// 键面副标（实现轮 4 起九宫格不用副标，恒为 nil；保留字段供模型复用）。
    public let subLabel: String?
    public let action: NineGridKeyAction
    public init(label: String, subLabel: String? = nil, action: NineGridKeyAction) {
        self.label = label
        self.subLabel = subLabel
        self.action = action
    }
}

/// 键位摆放：0 起的行列 + 跨行/跨列数（确认纵向跨 2 行、选定横向跨 2 列）。
public struct NineGridKeyPlacement: Equatable {
    public let spec: NineGridKeySpec
    public let row: Int
    public let col: Int
    public let rowSpan: Int
    public let colSpan: Int
    public init(spec: NineGridKeySpec, row: Int, col: Int, rowSpan: Int = 1, colSpan: Int = 1) {
        self.spec = spec
        self.row = row
        self.col = col
        self.rowSpan = rowSpan
        self.colSpan = colSpan
    }
}

public enum NineGridLayout {
    public static let columnCount = 5
    public static let rowCount = 4

    /// 苹果式布局（用户截图实测）：
    /// R1 [123] [，。？！] [ABC] [DEF] [⌫]
    /// R2 [#@¥] [GHI] [JKL] [MNO] [分隔]
    /// R3 [中英] [PQRS] [TUV] [WXYZ] [确认（跨 R3–R4）]
    /// R4 [😊] [选拼音] [选定（跨 2 列）]
    /// 中英键键面随模式翻转：中文模式标「ABC」、英文模式标「拼音」
    /// （视图 setAsciiMode 负责改字，此处给中文模式的初始值）。
    public static let placements: [NineGridKeyPlacement] = [
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "123", action: .symbolsPage), row: 0, col: 0),
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "，。？！", action: .punctuation), row: 0, col: 1),
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "ABC", action: .digit(2)), row: 0, col: 2),
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "DEF", action: .digit(3)), row: 0, col: 3),
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "⌫", action: .backspace), row: 0, col: 4),

        NineGridKeyPlacement(spec: NineGridKeySpec(label: "#@¥", action: .symbolsPage), row: 1, col: 0),
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "GHI", action: .digit(4)), row: 1, col: 1),
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "JKL", action: .digit(5)), row: 1, col: 2),
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "MNO", action: .digit(6)), row: 1, col: 3),
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "分隔", action: .separator), row: 1, col: 4),

        NineGridKeyPlacement(spec: NineGridKeySpec(label: "ABC", action: .toggleAscii), row: 2, col: 0),
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "PQRS", action: .digit(7)), row: 2, col: 1),
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "TUV", action: .digit(8)), row: 2, col: 2),
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "WXYZ", action: .digit(9)), row: 2, col: 3),
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "确认", action: .enter), row: 2, col: 4, rowSpan: 2),

        NineGridKeyPlacement(spec: NineGridKeySpec(label: "😊", action: .symbolsEmojiPage), row: 3, col: 0),
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "选拼音", action: .toggleSyllables), row: 3, col: 1),
        NineGridKeyPlacement(spec: NineGridKeySpec(label: "选定", action: .spaceOrCommit), row: 3, col: 2, colSpan: 2),
    ]
}
