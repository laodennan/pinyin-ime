import Foundation

/// 九宫格键位模型（仅数据）。数字键进入 T9Mapper 的 digitBuffer；
/// 不直接透传引擎（见 PLAN.md 3.2）。
public enum NineGridKeyAction: Equatable {
    case digit(Int)            // 1–9，进入 T9 切分（1 为分词键）
    case symbols               // 0 键区：符号（行为定版于步骤 4）
    case backspace             // T9 语义删除：弹一位数字后重算切分
    case spaceOrCommit         // 上屏首选 / 无组合时空格
    case enter
    case toggleAscii
    case switchToFull26        // 切回 26 键
    case nextKeyboard
}

public struct NineGridKeySpec: Equatable {
    public let label: String
    /// 键面副标（如 "abc"）。
    public let subLabel: String?
    public let action: NineGridKeyAction
    public init(label: String, subLabel: String?, action: NineGridKeyAction) {
        self.label = label
        self.subLabel = subLabel
        self.action = action
    }
}

public enum NineGridLayout {
    public static let grid: [[NineGridKeySpec]] = [
        [NineGridKeySpec(label: "1", subLabel: "分词", action: .digit(1)),
         NineGridKeySpec(label: "2", subLabel: "abc", action: .digit(2)),
         NineGridKeySpec(label: "3", subLabel: "def", action: .digit(3))],
        [NineGridKeySpec(label: "4", subLabel: "ghi", action: .digit(4)),
         NineGridKeySpec(label: "5", subLabel: "jkl", action: .digit(5)),
         NineGridKeySpec(label: "6", subLabel: "mno", action: .digit(6))],
        [NineGridKeySpec(label: "7", subLabel: "pqrs", action: .digit(7)),
         NineGridKeySpec(label: "8", subLabel: "tuv", action: .digit(8)),
         NineGridKeySpec(label: "9", subLabel: "wxyz", action: .digit(9))],
    ]
}
