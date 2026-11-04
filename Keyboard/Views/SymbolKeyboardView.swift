import UIKit

/// 符号面板底部行动作（字母页的 KeyAction 不含「返回字母页」，故单列）。
enum SymbolPanelAction {
    case backToLetters
    case space
    case backspace
    case enter
    case nextKeyboard
}

/// 符号/数字页视图：键位来自 SymbolLayout 数据模型，字面量点击经 onSymbol
/// 交给 KeyboardViewController（先提交组合串再直插，见 SymbolLayout 注释）。
final class SymbolKeyboardView: UIView {
    var onSymbol: ((String) -> Void)?
    var onAction: ((SymbolPanelAction) -> Void)?
    var showsGlobeButton = false {
        didSet { if oldValue != showsGlobeButton { rebuildBottomRow() } }
    }
    /// 地球键目标-动作接线（同 FullKeyboardView 的说明）。
    weak var globeTarget: AnyObject?
    var globeAction: Selector?

    private var rows: [[KeyButton]] = []
    private var bottomRow: [KeyButton] = []
    private var returnButton: KeyButton?

    private let hInset: CGFloat = 3
    private let hSpacing: CGFloat = 5
    private let vSpacing: CGFloat = 9

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        let allRows = [SymbolLayout.digitRow] + SymbolLayout.punctRows + [SymbolLayout.extraRow]
        rows = allRows.map { row in
            row.map { symbol in
                let button = KeyButton()
                button.setTitle(symbol, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 19)
                button.onPress = { [weak self] in self?.onSymbol?(symbol) }
                addSubview(button)
                return button
            }
        }
        rebuildBottomRow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func rebuildBottomRow() {
        bottomRow.forEach { $0.removeFromSuperview() }
        bottomRow = []
        func add(_ title: String, font: CGFloat = 15, function: Bool = true,
                 repeatable: Bool = false, action: @escaping () -> Void) -> KeyButton {
            let button = KeyButton()
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: font)
            button.isFunctionKey = function
            button.repeatEnabled = repeatable
            button.onPress = action
            addSubview(button)
            bottomRow.append(button)
            return button
        }
        if showsGlobeButton {
            let globe = add("🌐", font: 17) { [weak self] in self?.onAction?(.nextKeyboard) }
            if let globeTarget, let globeAction {
                globe.onPress = nil
                globe.addTarget(globeTarget, action: globeAction, for: .allTouchEvents)
            }
        }
        _ = add("ABC") { [weak self] in self?.onAction?(.backToLetters) }
        _ = add("空格", function: false) { [weak self] in self?.onAction?(.space) }
        _ = add("⌫", font: 19, repeatable: true) { [weak self] in self?.onAction?(.backspace) }
        returnButton = add("回车") { [weak self] in self?.onAction?(.enter) }
        setNeedsLayout()
    }

    func setReturnKeyTitle(_ title: String) {
        returnButton?.setTitle(title, for: .normal)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bottomWeights: [Double] = (showsGlobeButton ? [1.1] : []) + [1.3, 3.4, 1.3, 1.3]
        let allRows: [[(KeyButton, Double)]] = rows.map { row in row.map { ($0, 1.0) } }
            + [Array(zip(bottomRow, bottomWeights))]
        let rowCount = CGFloat(allRows.count)
        guard rowCount > 0 else { return }
        let rowHeight = (bounds.height - vSpacing * (rowCount - 1)) / rowCount
        for (rowIndex, row) in allRows.enumerated() {
            let totalWeight = row.reduce(0) { $0 + $1.1 }
            let available = bounds.width - hInset * 2 - hSpacing * CGFloat(row.count - 1)
            var x = hInset
            let y = CGFloat(rowIndex) * (rowHeight + vSpacing)
            for (button, weight) in row {
                let w = available * CGFloat(weight / totalWeight)
                button.frame = CGRect(x: x, y: y, width: w, height: rowHeight)
                x += w + hSpacing
            }
        }
    }
}
