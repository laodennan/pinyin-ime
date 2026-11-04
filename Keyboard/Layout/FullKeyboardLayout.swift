import Foundation

/// 26 键全键盘的键位模型（仅数据，渲染在键盘 UI 层）。
/// 字母键直接把字符透传 RimeEngine.processKey；功能键由 UI 层解释。
public enum KeyAction: Equatable {
    case letter(Character)     // 透传引擎
    case backspace
    case space                 // 上屏首选 / 无组合时输入空格
    case enter
    case shift                 // 英文模式大小写（中文模式下行为待定版）
    case toggleAscii           // 中/英切换
    case switchToSymbols       // 符号页
    case switchToNineGrid      // 切到九宫格
    case nextKeyboard          // 地球键：advanceToNextInputMode
}

public struct KeySpec: Equatable {
    public let label: String
    public let action: KeyAction
    /// 相对宽度权重（普通键 1.0）。
    public let widthWeight: Double
    public init(label: String, action: KeyAction, widthWeight: Double = 1.0) {
        self.label = label
        self.action = action
        self.widthWeight = widthWeight
    }
}

public enum FullKeyboardLayout {
    public static let letterRows: [[KeySpec]] = [
        "qwertyuiop".map { KeySpec(label: String($0), action: .letter($0)) },
        "asdfghjkl".map { KeySpec(label: String($0), action: .letter($0)) },
        [KeySpec(label: "⇧", action: .shift, widthWeight: 1.4)]
            + "zxcvbnm".map { KeySpec(label: String($0), action: .letter($0)) }
            + [KeySpec(label: "⌫", action: .backspace, widthWeight: 1.4)],
    ]

    public static let bottomRow: [KeySpec] = [
        KeySpec(label: "符", action: .switchToSymbols, widthWeight: 1.2),
        KeySpec(label: "中/英", action: .toggleAscii, widthWeight: 1.2),
        KeySpec(label: "空格", action: .space, widthWeight: 4.0),
        KeySpec(label: "九宫格", action: .switchToNineGrid, widthWeight: 1.4),
        KeySpec(label: "回车", action: .enter, widthWeight: 1.4),
    ]
}
