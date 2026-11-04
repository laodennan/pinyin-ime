import UIKit

/// 符号面板底部行动作（字母页的 KeyAction 不含「返回字母页」，故单列）。
enum SymbolPanelAction {
    case backToLetters
    case space
    case backspace
    case enter
    case nextKeyboard
}

/// 符号/数字页视图：顶部一行业签（符号 / 表情），内容区二选一，底部行
/// （ABC/空格/退格/回车/地球）两页签共用。键位来自 SymbolLayout 数据
/// 模型，字面量点击经 onSymbol 交给 KeyboardViewController（先提交组合
/// 串再直插，见 SymbolLayout 注释）；表情点按走同一 onSymbol 路径。
/// 默认显示符号页签；VC 从九宫格「😊」进入时调 showEmojiTab()，
/// 从「123/#@¥/符」进入时调 showSymbolTab()。
final class SymbolKeyboardView: UIView {
    var onSymbol: ((String) -> Void)?
    var onAction: ((SymbolPanelAction) -> Void)?
    /// 退格连发 tick：参数为本次按住累计时长（同 26 键面板的约定）。
    var onBackspaceHold: ((TimeInterval) -> Void)?
    var showsGlobeButton = false {
        didSet { if oldValue != showsGlobeButton { rebuildBottomRow() } }
    }
    /// 地球键目标-动作接线（同 FullKeyboardView 的说明）。
    weak var globeTarget: AnyObject?
    var globeAction: Selector?

    private var rows: [[KeyButton]] = []
    private var bottomRow: [KeyButton] = []
    private var returnButton: KeyButton?
    private let symbolTabButton = UIButton(type: .system)
    private let emojiTabButton = UIButton(type: .system)
    private var emojiButtons: [UIButton] = []
    private var showsEmoji = false

    private let hInset: CGFloat = 3
    private let hSpacing: CGFloat = 5
    private let vSpacing: CGFloat = 10
    private let tabRowHeight: CGFloat = 34

    private static let tabSelectedBackground = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.35, alpha: 1)
            : UIColor(red: 0.85, green: 0.87, blue: 0.92, alpha: 1)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        buildTabs()
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
        emojiButtons = SymbolLayout.emojiGrid.enumerated().map { index, emoji in
            let button = UIButton(type: .system)
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 26)
            button.tag = index
            button.isHidden = true
            button.addTarget(self, action: #selector(emojiTapped(_:)), for: .touchUpInside)
            addSubview(button)
            return button
        }
        rebuildBottomRow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: 页签

    private func buildTabs() {
        symbolTabButton.setTitle("符号", for: .normal)
        symbolTabButton.addTarget(self, action: #selector(symbolTabTapped), for: .touchUpInside)
        emojiTabButton.setTitle("表情", for: .normal)
        emojiTabButton.addTarget(self, action: #selector(emojiTabTapped), for: .touchUpInside)
        for button in [symbolTabButton, emojiTabButton] {
            button.titleLabel?.font = .systemFont(ofSize: 15)
            button.setTitleColor(.label, for: .normal)
            button.layer.cornerRadius = 8
            addSubview(button)
        }
        refreshTabAppearance()
    }

    private func refreshTabAppearance() {
        symbolTabButton.backgroundColor = showsEmoji ? .clear : Self.tabSelectedBackground
        emojiTabButton.backgroundColor = showsEmoji ? Self.tabSelectedBackground : .clear
    }

    @objc private func symbolTabTapped() { showSymbolTab() }
    @objc private func emojiTabTapped() { showEmojiTab() }

    @objc private func emojiTapped(_ sender: UIButton) {
        guard SymbolLayout.emojiGrid.indices.contains(sender.tag) else { return }
        onSymbol?(SymbolLayout.emojiGrid[sender.tag])
    }

    /// 切到表情页签（九宫格「😊」入口）。
    func showEmojiTab() {
        guard !showsEmoji else { return }
        showsEmoji = true
        refreshTabAppearance()
        setNeedsLayout()
    }

    /// 切到符号页签（「123/#@¥/符」入口与页签点按）。
    func showSymbolTab() {
        guard showsEmoji else { return }
        showsEmoji = false
        refreshTabAppearance()
        setNeedsLayout()
    }

    // MARK: 底部行

    private func rebuildBottomRow() {
        bottomRow.forEach { $0.removeFromSuperview() }
        bottomRow = []
        func add(_ title: String, font: CGFloat = 16, function: Bool = true,
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
        let backspace = add("⌫", font: 19, repeatable: true) { [weak self] in self?.onAction?(.backspace) }
        backspace.onRepeatTick = { [weak self] elapsed in self?.onBackspaceHold?(elapsed) }
        returnButton = add("回车") { [weak self] in self?.onAction?(.enter) }
        setNeedsLayout()
    }

    func setReturnKeyTitle(_ title: String) {
        returnButton?.setTitle(title, for: .normal)
    }

    /// 回车键强调（.search/.send 场景的系统蓝，同 26 键面板）。
    func setReturnKeyAccent(_ accent: Bool) {
        returnButton?.isAccent = accent
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 页签行。
        symbolTabButton.frame = CGRect(x: hInset, y: 3, width: 68, height: tabRowHeight - 6)
        emojiTabButton.frame = CGRect(x: hInset + 68 + 6, y: 3, width: 68, height: tabRowHeight - 6)
        // 内容区：4 行内容 + 1 行底部行（两页签共用）。
        let regionY = tabRowHeight
        let regionHeight = bounds.height - tabRowHeight
        let rowHeight = (regionHeight - vSpacing * 4) / 5
        let bottomWeights: [Double] = (showsGlobeButton ? [1.1] : []) + [1.3, 3.4, 1.3, 1.3]
        let allRows: [[(KeyButton, Double)]] = rows.map { row in row.map { ($0, 1.0) } }
            + [Array(zip(bottomRow, bottomWeights))]
        for (rowIndex, row) in allRows.enumerated() {
            let isBottomRow = rowIndex == allRows.count - 1
            let totalWeight = row.reduce(0) { $0 + $1.1 }
            let available = bounds.width - hInset * 2 - hSpacing * CGFloat(row.count - 1)
            var x = hInset
            let y = regionY + CGFloat(rowIndex) * (rowHeight + vSpacing)
            for (button, weight) in row {
                let w = available * CGFloat(weight / totalWeight)
                button.frame = CGRect(x: x, y: y, width: w, height: rowHeight)
                x += w + hSpacing
                if !isBottomRow { button.isHidden = showsEmoji }
            }
        }
        // 表情网格：占内容区上方 4 行的面积，9 列 × 4 行。
        let gridHeight = rowHeight * 4 + vSpacing * 3
        let cellWidth = (bounds.width - hInset * 2) / 9
        let cellHeight = gridHeight / 4
        for (index, button) in emojiButtons.enumerated() {
            let col = index % 9
            let row = index / 9
            button.frame = CGRect(x: hInset + CGFloat(col) * cellWidth,
                                  y: regionY + CGFloat(row) * cellHeight,
                                  width: cellWidth, height: cellHeight)
            button.isHidden = !showsEmoji
        }
    }
}
