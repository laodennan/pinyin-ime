import UIKit

/// 九宫格（T9）面板（实现轮 4 重做）：照苹果原生简体拼音九宫格——整宽
/// 5 列 × 4 行，无左侧音节条、无右侧功能列；音节选项已搬进候选栏顶部。
///
/// 键位语义全部经 onAction 交 VC 解释，本视图只管渲染与手势：
/// - 字母键（ABC…WXYZ=T9 数字 2–9）与标点键走 PopupKeyTracker：
///   按下弹气泡（字母组 / 「，」）、滑动跟随、抬起输入；
/// - 标点键长按出变体条 [，。？！、；：]，选定经 onVariantInput 直插（VC）；
/// - 中英键点按切换中/英（抬起触发），长按 = 切回 26 键（气泡提示「26键」，
///   长按成立时抑制本次点按，长按处理直接发 .switchToFull26）；
/// - 选定键 = 空格/选词（抬起触发），长按切换为光标触控板（onSpaceTrackpad）；
/// - 退格连发；所有键统一底色（不设 isFunctionKey），仅确认键可 isAccent。
/// 地球键（如需显示）放在网格下方一条 44pt 行里居左，同 FullKeyboardView
/// 的处理（目标-动作直挂 handleInputModeList，需要真实触摸事件）。
final class NineGridView: UIView {
    var onAction: ((NineGridKeyAction) -> Void)?
    /// 标点长按变体被选定：字面量字符串，VC 先提交组合串再直插。
    var onVariantInput: ((String) -> Void)?
    var onSpaceTrackpad: ((SpaceTrackpadPhase, CGFloat) -> Void)?

    /// 地球键的目标-动作接线（见类注释）。VC 的注入晚于本视图 init，
    /// 故用 didSet 挂接；未接线时退回 onAction(.nextKeyboard)。
    weak var globeTarget: AnyObject? {
        didSet { wireGlobe() }
    }
    var globeAction: Selector? {
        didSet { wireGlobe() }
    }
    private var globeWired = false

    private func wireGlobe() {
        guard !globeWired, let globeTarget, let globeAction else { return }
        globeWired = true
        globeButton.onPress = nil
        globeButton.addTarget(globeTarget, action: globeAction, for: .allTouchEvents)
    }
    var showsGlobeButton = false {
        didSet {
            if oldValue != showsGlobeButton {
                globeButton.isHidden = !showsGlobeButton
                setNeedsLayout()
            }
        }
    }

    private let globeButton = KeyButton()
    private var placedButtons: [(button: KeyButton, placement: NineGridKeyPlacement)] = []
    private var digitButtons: [KeyButton] = []
    private var punctButton: KeyButton?
    private var returnButton: KeyButton?
    private var asciiButton: KeyButton?
    private var spaceButton: KeyButton?
    private var trackpadStartX: CGFloat = 0

    private var presenter: KeyPopupPresenter!
    private var tracker: PopupKeyTracker!

    private let hInset: CGFloat = 3
    private let hSpacing: CGFloat = 6
    private let vSpacing: CGFloat = 10
    private let globeRowHeight: CGFloat = 44

    /// 标点键长按变体（顺序同苹果：点按的「，」在首位）。
    static let punctVariants = ["，", "。", "？", "！", "、", "；", "："]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        presenter = KeyPopupPresenter()
        tracker = PopupKeyTracker(presenter: presenter) { [weak self] point in
            self?.hitTestTracked(at: point)
        }
        tracker.onVariantInput = { [weak self] text in self?.onVariantInput?(text) }
        // 气泡文案：字母键显示字母组（= 键面标题）；标点键显示点按将插入的「，」。
        tracker.textForKey = { [weak self] button in
            if let self, button === self.punctButton { return "，" }
            return button.title(for: .normal) ?? ""
        }
        buildGrid()
        buildGlobe()
        addSubview(presenter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: 构建

    private func buildGlobe() {
        globeButton.setTitle("🌐", for: .normal)
        globeButton.titleLabel?.font = .systemFont(ofSize: 17)
        globeButton.isFunctionKey = true
        globeButton.isHidden = true
        globeButton.onPress = { [weak self] in self?.onAction?(.nextKeyboard) }
        addSubview(globeButton)
    }

    private func wireTracker(_ button: KeyButton) {
        button.onTouchEvent = { [weak self] btn, touch, phase in
            guard let self else { return }
            switch phase {
            case .began: self.tracker.touchBegan(btn, touch: touch, in: self)
            case .moved: self.tracker.touchMoved(touch, in: self)
            case .ended: self.tracker.touchEnded(touch, in: self)
            case .cancelled: self.tracker.touchCancelled(touch, in: self)
            }
        }
    }

    private func buildGrid() {
        for placement in NineGridLayout.placements {
            let spec = placement.spec
            let button = KeyButton()
            button.setTitle(spec.label, for: .normal)
            let action = spec.action
            switch spec.action {
            case .digit:
                button.titleLabel?.font = .systemFont(ofSize: 21)
                button.defersActionToRelease = true
                button.onPress = { [weak self] in self?.onAction?(action) }
                wireTracker(button)
                digitButtons.append(button)
            case .punctuation:
                button.titleLabel?.font = .systemFont(ofSize: 15)
                button.defersActionToRelease = true
                button.onPress = { [weak self] in self?.onAction?(action) }
                wireTracker(button)
                let lp = UILongPressGestureRecognizer(target: self, action: #selector(punctLongPressed(_:)))
                lp.minimumPressDuration = 0.38
                lp.cancelsTouchesInView = false
                button.addGestureRecognizer(lp)
                punctButton = button
            case .backspace:
                button.titleLabel?.font = .systemFont(ofSize: 19)
                button.repeatEnabled = true
                button.onPress = { [weak self] in self?.onAction?(action) }
            case .toggleAscii:
                button.titleLabel?.font = .systemFont(ofSize: 16)
                // 抬起才触发点按语义：长按（切 26 键）成立时来得及抑制。
                button.defersActionToRelease = true
                button.firesActionOnReleaseLocally = true
                button.onPress = { [weak self] in self?.onAction?(action) }
                let lp = UILongPressGestureRecognizer(target: self, action: #selector(asciiLongPressed(_:)))
                lp.minimumPressDuration = 0.38
                lp.cancelsTouchesInView = false
                button.addGestureRecognizer(lp)
                asciiButton = button
            case .spaceOrCommit:
                button.titleLabel?.font = .systemFont(ofSize: 16)
                button.defersActionToRelease = true
                button.firesActionOnReleaseLocally = true
                button.onPress = { [weak self] in self?.onAction?(action) }
                let lp = UILongPressGestureRecognizer(target: self, action: #selector(spaceLongPressed(_:)))
                lp.minimumPressDuration = 0.35
                lp.cancelsTouchesInView = false
                button.addGestureRecognizer(lp)
                spaceButton = button
            case .enter:
                button.titleLabel?.font = .systemFont(ofSize: 16)
                button.onPress = { [weak self] in self?.onAction?(action) }
                returnButton = button
            case .symbolsEmojiPage:
                button.titleLabel?.font = .systemFont(ofSize: 20)
                button.onPress = { [weak self] in self?.onAction?(action) }
            default:
                // symbolsPage / separator / toggleSyllables：即时触发。
                button.titleLabel?.font = .systemFont(ofSize: 16)
                button.onPress = { [weak self] in self?.onAction?(action) }
            }
            addSubview(button)
            placedButtons.append((button, placement))
        }
    }

    // MARK: 状态外观

    /// 中/英状态：中文模式键面标「ABC」（点按去英文），英文模式标「拼音」。
    func setAsciiMode(_ ascii: Bool) {
        asciiButton?.setTitle(ascii ? "拼音" : "ABC", for: .normal)
    }

    func setReturnKeyTitle(_ title: String) {
        returnButton?.setTitle(title, for: .normal)
    }

    func setReturnKeyAccent(_ accent: Bool) {
        returnButton?.isAccent = accent
    }

    // MARK: 手势

    @objc private func punctLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              let button = recognizer.view as? KeyButton
        else { return }
        tracker.beginVariants(for: button, variants: Self.punctVariants,
                              at: recognizer.location(in: self), in: self)
    }

    /// 中英键长按 = 切回 26 键：气泡提示 + 抑制本次点按的中英切换。
    @objc private func asciiLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard let button = asciiButton else { return }
        switch recognizer.state {
        case .began:
            button.suppressNextReleaseAction = true
            presenter.showMagnifier(above: button.frame, text: "26键")
            onAction?(.switchToFull26)
        case .ended, .cancelled, .failed:
            presenter.hide()
        default:
            break
        }
    }

    /// 选定键长按 = 光标触控板（同 26 键空格的约定）。
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

    // MARK: 命中测试（弹窗滑动跟随：字母键 + 标点键）

    private func hitTestTracked(at point: CGPoint) -> KeyButton? {
        var tracked = digitButtons
        if let punctButton { tracked.append(punctButton) }
        if let hit = tracked.first(where: { $0.frame.contains(point) }) { return hit }
        // 行列间隙吸附最近键，避免滑动途中弹窗闪烁消失。
        return tracked.first(where: { $0.frame.insetBy(dx: -3, dy: -5).contains(point) })
    }

    // MARK: 布局

    override func layoutSubviews() {
        super.layoutSubviews()
        presenter.frame = bounds
        let globeHeight: CGFloat = showsGlobeButton ? globeRowHeight : 0
        globeButton.frame = CGRect(x: 0, y: bounds.height - globeHeight,
                                   width: 56, height: globeHeight)
        let gridHeight = bounds.height - globeHeight
        let cellWidth = (bounds.width - hInset * 2
                         - hSpacing * CGFloat(NineGridLayout.columnCount - 1))
                        / CGFloat(NineGridLayout.columnCount)
        let rowHeight = (gridHeight - vSpacing * CGFloat(NineGridLayout.rowCount - 1))
                        / CGFloat(NineGridLayout.rowCount)
        for (button, placement) in placedButtons {
            let x = hInset + CGFloat(placement.col) * (cellWidth + hSpacing)
            let y = CGFloat(placement.row) * (rowHeight + vSpacing)
            let w = cellWidth * CGFloat(placement.colSpan)
                    + hSpacing * CGFloat(placement.colSpan - 1)
            let h = rowHeight * CGFloat(placement.rowSpan)
                    + vSpacing * CGFloat(placement.rowSpan - 1)
            button.frame = CGRect(x: x, y: y, width: w, height: h)
        }
    }
}
