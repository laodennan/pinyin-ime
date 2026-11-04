import UIKit

/// 26 键全键盘视图：按 FullKeyboardLayout 的键位模型程序化排版（手工 frame 布局，
/// 权重决定键宽，不依赖 Auto Layout 的比例约束，行为可预期）。
/// 本视图只负责渲染与手势，按键语义经 onAction 交给 KeyboardViewController 解释。
final class FullKeyboardView: UIView {
    var onAction: ((KeyAction) -> Void)?

    /// 地球键是否显示（由宿主的 needsInputModeSwitchKey 决定）；变化时重建底行。
    var showsGlobeButton = false {
        didSet { if oldValue != showsGlobeButton { rebuildBottomRow() } }
    }

    /// 地球键的目标-动作接线：切换键盘必须走系统提供的 handleInputModeList
    /// （需要真实的触摸事件），故不用 onPress 闭包，而是把宿主（VC）的
    /// target/action 直接挂到按钮的 .allTouchEvents 上。未接线时退回闭包路径。
    weak var globeTarget: AnyObject?
    var globeAction: Selector?

    private var rowViews: [[KeyButton]] = []
    private var letterButtons: [Character: KeyButton] = [:]
    private var shiftButton: KeyButton?
    private var asciiButton: KeyButton?
    private var returnButton: KeyButton?
    private var bottomRowContainer: [KeyButton] = []

    private let hInset: CGFloat = 3
    private let hSpacing: CGFloat = 6
    private let vSpacing: CGFloat = 9

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        buildLetterRows()
        rebuildBottomRow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: 构建

    private func makeButton(_ spec: KeySpec, fontSize: CGFloat = 21) -> KeyButton {
        let button = KeyButton()
        button.setTitle(spec.label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: fontSize)
        switch spec.action {
        case .letter(let ch):
            letterButtons[ch] = button
            button.onPress = { [weak self] in self?.onAction?(.letter(ch)) }
        case .backspace:
            button.isFunctionKey = true
            button.repeatEnabled = true
            button.onPress = { [weak self] in self?.onAction?(.backspace) }
        case .shift:
            button.isFunctionKey = true
            shiftButton = button
            button.onPress = { [weak self] in self?.onAction?(.shift) }
        case .toggleAscii:
            button.isFunctionKey = true
            button.titleLabel?.font = .systemFont(ofSize: 15)
            asciiButton = button
            button.onPress = { [weak self] in self?.onAction?(.toggleAscii) }
        case .switchToSymbols, .switchToNineGrid, .nextKeyboard:
            button.isFunctionKey = true
            button.titleLabel?.font = .systemFont(ofSize: 15)
            let action = spec.action
            button.onPress = { [weak self] in self?.onAction?(action) }
        case .space:
            button.titleLabel?.font = .systemFont(ofSize: 15)
            button.onPress = { [weak self] in self?.onAction?(.space) }
        case .enter:
            button.isFunctionKey = true
            button.titleLabel?.font = .systemFont(ofSize: 15)
            returnButton = button
            button.onPress = { [weak self] in self?.onAction?(.enter) }
        }
        return button
    }

    private func buildLetterRows() {
        rowViews = FullKeyboardLayout.letterRows.map { row in
            row.map { spec in
                let button = makeButton(spec)
                addSubview(button)
                return button
            }
        }
    }

    private func rebuildBottomRow() {
        bottomRowContainer.forEach { $0.removeFromSuperview() }
        bottomRowContainer = []
        if showsGlobeButton {
            let globe = KeyButton()
            globe.setTitle("🌐", for: .normal)
            globe.titleLabel?.font = .systemFont(ofSize: 17)
            globe.isFunctionKey = true
            if let globeTarget, let globeAction {
                globe.addTarget(globeTarget, action: globeAction, for: .allTouchEvents)
            } else {
                globe.onPress = { [weak self] in self?.onAction?(.nextKeyboard) }
            }
            addSubview(globe)
            bottomRowContainer.append(globe)
        }
        for spec in FullKeyboardLayout.bottomRow {
            let button = makeButton(spec)
            addSubview(button)
            bottomRowContainer.append(button)
        }
        setNeedsLayout()
    }

    // MARK: 状态外观

    /// 大写状态（仅英文模式有意义）：⇧ 常态 / ⇪ 锁定态字形区分。
    func setCaps(_ caps: Bool) {
        shiftButton?.setTitle(caps ? "⇪" : "⇧", for: .normal)
    }

    /// 中/英状态：按钮显示当前模式（中 = 中文拼音，英 = ASCII 直输）。
    func setAsciiMode(_ ascii: Bool) {
        asciiButton?.setTitle(ascii ? "英" : "中", for: .normal)
    }

    func setReturnKeyTitle(_ title: String) {
        returnButton?.setTitle(title, for: .normal)
    }

    // MARK: 布局（手工 frame：行高均分，行内按权重分宽）

    override func layoutSubviews() {
        super.layoutSubviews()
        let allRows: [[(KeyButton, Double)]] = rowViews.enumerated().map { index, buttons in
            zip(buttons, FullKeyboardLayout.letterRows[index]).map { ($0.0, $0.1.widthWeight) }
        } + [bottomWeightsRow()]
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

    private func bottomWeightsRow() -> [(KeyButton, Double)] {
        var weights: [(KeyButton, Double)] = []
        var specs = FullKeyboardLayout.bottomRow
        if showsGlobeButton, let globe = bottomRowContainer.first {
            weights.append((globe, 1.1))
            specs = Array(FullKeyboardLayout.bottomRow)
            let rest = bottomRowContainer.dropFirst()
            for (button, spec) in zip(rest, specs) { weights.append((button, spec.widthWeight)) }
            return weights
        }
        for (button, spec) in zip(bottomRowContainer, specs) { weights.append((button, spec.widthWeight)) }
        return weights
    }
}
