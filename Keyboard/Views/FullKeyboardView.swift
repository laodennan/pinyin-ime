import UIKit

/// 26 键全键盘视图：按 FullKeyboardLayout 的键位模型程序化排版（手工 frame 布局，
/// 权重决定键宽）。本视图只负责渲染与手势，按键语义经 onAction 交给
/// KeyboardViewController 解释。
///
/// 苹果式交互（实现轮 2）：
/// - 字母键走 PopupKeyTracker：按下弹放大镜、滑动跟随换键、抬起才输入；
/// - 元音键长按出四声变体条、第一行辅音键长按出对应数字（onVariantInput 直插）；
/// - 空格键抬起触发，长按切换为光标触控板（onSpaceTrackpad）；
/// - 退格连发 tick 经 onBackspaceHold 上报按住时长，VC 据此切整词删除。
final class FullKeyboardView: UIView {
    var onAction: ((KeyAction) -> Void)?
    /// 长按变体被选定：字面量字符串（声调字母/数字），VC 先提交组合串再直插。
    var onVariantInput: ((String) -> Void)?
    /// 空格长按触控板：(阶段, 自激活点起的水平累计位移)。
    var onSpaceTrackpad: ((SpaceTrackpadPhase, CGFloat) -> Void)?
    /// 退格连发 tick：参数为本次按住累计时长。
    var onBackspaceHold: ((TimeInterval) -> Void)?

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
    private var spaceButton: KeyButton?
    private var bottomRowContainer: [KeyButton] = []
    private var trackpadStartX: CGFloat = 0

    private var presenter: KeyPopupPresenter!
    private var tracker: PopupKeyTracker!

    private let hInset: CGFloat = 3
    private let hSpacing: CGFloat = 6
    private let vSpacing: CGFloat = 10

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        presenter = KeyPopupPresenter()
        tracker = PopupKeyTracker(presenter: presenter) { [weak self] point in
            self?.hitTestLetter(at: point)
        }
        tracker.onVariantInput = { [weak self] text in self?.onVariantInput?(text) }
        buildLetterRows()
        rebuildBottomRow()
        addSubview(presenter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: 长按变体数据

    /// 元音 → 四声变体；v 键 → ü 系列；第一行辅音 → 对应数字。
    /// 元音同时是第一行成员的（e/i/o/u）声调优先（苹果拼音键盘同此取舍），
    /// 数字让位给 q/w/r/t/y/p。
    static func variants(for ch: Character) -> [String] {
        switch ch {
        case "a": return ["ā", "á", "ǎ", "à"]
        case "e": return ["ē", "é", "ě", "è"]
        case "i": return ["ī", "í", "ǐ", "ì"]
        case "o": return ["ō", "ó", "ǒ", "ò"]
        case "u": return ["ū", "ú", "ǔ", "ù"]
        case "v": return ["ǖ", "ǘ", "ǚ", "ǜ", "ü"]
        case "q": return ["1"]
        case "w": return ["2"]
        case "r": return ["4"]
        case "t": return ["5"]
        case "y": return ["6"]
        case "p": return ["0"]
        default: return []
        }
    }

    // MARK: 构建

    private func makeButton(_ spec: KeySpec, fontSize: CGFloat = 22) -> KeyButton {
        let button = KeyButton()
        button.setTitle(spec.label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: fontSize)
        switch spec.action {
        case .letter(let ch):
            letterButtons[ch] = button
            // 语义动作仍走 onPress，但触发时机归 PopupKeyTracker（抬起/接管时）。
            button.defersActionToRelease = true
            button.onPress = { [weak self] in self?.onAction?(.letter(ch)) }
            button.onTouchEvent = { [weak self] btn, touch, phase in
                guard let self else { return }
                switch phase {
                case .began: self.tracker.touchBegan(btn, touch: touch, in: self)
                case .moved: self.tracker.touchMoved(touch, in: self)
                case .ended: self.tracker.touchEnded(touch, in: self)
                case .cancelled: self.tracker.touchCancelled(touch, in: self)
                }
            }
            let variants = Self.variants(for: ch)
            if !variants.isEmpty {
                let lp = UILongPressGestureRecognizer(target: self, action: #selector(letterLongPressed(_:)))
                lp.minimumPressDuration = 0.38
                lp.cancelsTouchesInView = false
                button.addGestureRecognizer(lp)
            }
        case .backspace:
            button.isFunctionKey = true
            button.repeatEnabled = true
            button.onPress = { [weak self] in self?.onAction?(.backspace) }
            button.onRepeatTick = { [weak self] elapsed in self?.onBackspaceHold?(elapsed) }
        case .shift:
            button.isFunctionKey = true
            shiftButton = button
            button.onPress = { [weak self] in self?.onAction?(.shift) }
        case .toggleAscii:
            button.isFunctionKey = true
            button.titleLabel?.font = .systemFont(ofSize: 16)
            asciiButton = button
            button.onPress = { [weak self] in self?.onAction?(.toggleAscii) }
        case .switchToSymbols, .switchToNineGrid:
            button.isFunctionKey = true
            button.titleLabel?.font = .systemFont(ofSize: 16)
            let action = spec.action
            button.onPress = { [weak self] in self?.onAction?(action) }
        case .nextKeyboard:
            button.isFunctionKey = true
            button.titleLabel?.font = .systemFont(ofSize: 16)
            button.onPress = { [weak self] in self?.onAction?(.nextKeyboard) }
        case .space:
            button.titleLabel?.font = .systemFont(ofSize: 16)
            button.defersActionToRelease = true
            button.firesActionOnReleaseLocally = true
            spaceButton = button
            button.onPress = { [weak self] in self?.onAction?(.space) }
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(spaceLongPressed(_:)))
            lp.minimumPressDuration = 0.35
            lp.cancelsTouchesInView = false
            button.addGestureRecognizer(lp)
        case .enter:
            button.isFunctionKey = true
            button.titleLabel?.font = .systemFont(ofSize: 16)
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
        if let presenter { bringSubviewToFront(presenter) }
        setNeedsLayout()
    }

    // MARK: 手势

    @objc private func letterLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              let button = recognizer.view as? KeyButton,
              let ch = letterButtons.first(where: { $0.value === button })?.key
        else { return }
        tracker.beginVariants(for: button, variants: Self.variants(for: ch),
                              at: recognizer.location(in: self), in: self)
    }

    @objc private func spaceLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard let space = spaceButton else { return }
        switch recognizer.state {
        case .began:
            space.suppressNextReleaseAction = true
            trackpadStartX = recognizer.location(in: self).x
            onSpaceTrackpad?(.began, 0)
        case .changed:
            onSpaceTrackpad?(.moved, recognizer.location(in: self).x - trackpadStartX)
        case .ended, .cancelled, .failed:
            onSpaceTrackpad?(.ended, 0)
        default:
            break
        }
    }

    private func hitTestLetter(at point: CGPoint) -> KeyButton? {
        let buttons = Array(letterButtons.values)
        if let hit = buttons.first(where: { $0.frame.contains(point) }) { return hit }
        // 行列间隙吸附最近键，避免滑动途中弹窗闪烁消失。
        return buttons.first(where: { $0.frame.insetBy(dx: -3, dy: -5).contains(point) })
    }

    // MARK: 状态外观

    /// Shift 状态：一次性大写与大写锁定都反白键面，锁定另用 ⇪ 字形区分。
    func setShiftState(oneShot: Bool, locked: Bool) {
        shiftButton?.setTitle(locked ? "⇪" : "⇧", for: .normal)
        shiftButton?.isLatched = oneShot || locked
    }

    /// 中/英状态：按钮显示当前模式（中 = 中文拼音，英 = ASCII 直输）。
    func setAsciiMode(_ ascii: Bool) {
        asciiButton?.setTitle(ascii ? "英" : "中", for: .normal)
    }

    func setReturnKeyTitle(_ title: String) {
        returnButton?.setTitle(title, for: .normal)
    }

    /// 回车键强调（.search/.send 场景的系统蓝）。
    func setReturnKeyAccent(_ accent: Bool) {
        returnButton?.isAccent = accent
    }

    // MARK: 布局（手工 frame：行高均分，行内按权重分宽）

    override func layoutSubviews() {
        super.layoutSubviews()
        presenter.frame = bounds
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
        let specs = FullKeyboardLayout.bottomRow
        if showsGlobeButton, let globe = bottomRowContainer.first {
            weights.append((globe, 1.1))
            let rest = bottomRowContainer.dropFirst()
            for (button, spec) in zip(rest, specs) { weights.append((button, spec.widthWeight)) }
            return weights
        }
        for (button, spec) in zip(bottomRowContainer, specs) { weights.append((button, spec.widthWeight)) }
        return weights
    }
}
