import Foundation

/// 九宫格键位模型（仅数据）。数字键进入 T9Session 的数字串，不直接透传引擎
/// （见 PLAN.md 3.2）。布局仿苹果中文九宫格：左侧拼音选择条（视图层）、
/// 主区 4 行 × 3 列、右侧功能列（回车/26 键/符号）。
public enum NineGridKeyAction: Equatable {
    case digit(Int)            // 1–9：1 在有数字串时为分词键、无串时打开符号页（VC 解释）
    case symbolsPage           // 打开符号页
    case backspace             // T9 语义删除：弹一位数字后重算切分
    case spaceOrCommit         // 0 键：上屏首选 / 无组合时空格；长按为光标触控板（视图层手势）
    case enter
    case toggleAscii           // 中/英切换
    case switchToFull26        // 切回 26 键
    case nextKeyboard          // 地球键
}

public struct NineGridKeySpec: Equatable {
    public let label: String
    /// 键面副标（如 "abc"、"空格"），小字显示在键面下部。
    public let subLabel: String?
    public let action: NineGridKeyAction
    public init(label: String, subLabel: String?, action: NineGridKeyAction) {
        self.label = label
        self.subLabel = subLabel
        self.action = action
    }
}

public enum NineGridLayout {
    /// 主区：4 行 × 3 列。第四行依次为 中/英、0（空格）、退格。
    public static let grid: [[NineGridKeySpec]] = [
        [NineGridKeySpec(label: "1", subLabel: "，。？！", action: .digit(1)),
         NineGridKeySpec(label: "2", subLabel: "abc", action: .digit(2)),
         NineGridKeySpec(label: "3", subLabel: "def", action: .digit(3))],
        [NineGridKeySpec(label: "4", subLabel: "ghi", action: .digit(4)),
         NineGridKeySpec(label: "5", subLabel: "jkl", action: .digit(5)),
         NineGridKeySpec(label: "6", subLabel: "mno", action: .digit(6))],
        [NineGridKeySpec(label: "7", subLabel: "pqrs", action: .digit(7)),
         NineGridKeySpec(label: "8", subLabel: "tuv", action: .digit(8)),
         NineGridKeySpec(label: "9", subLabel: "wxyz", action: .digit(9))],
        [NineGridKeySpec(label: "中", subLabel: nil, action: .toggleAscii),
         NineGridKeySpec(label: "0", subLabel: "空格", action: .spaceOrCommit),
         NineGridKeySpec(label: "⌫", subLabel: nil, action: .backspace)],
    ]

    /// 右侧功能列（自上而下）：回车（占两行高）、26 键、符号。
    public static let sideColumn: [NineGridKeySpec] = [
        NineGridKeySpec(label: "回车", subLabel: nil, action: .enter),
        NineGridKeySpec(label: "26键", subLabel: nil, action: .switchToFull26),
        NineGridKeySpec(label: "符", subLabel: nil, action: .symbolsPage),
    ]
}
