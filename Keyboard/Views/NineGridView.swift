import UIKit

/// 九宫格（T9）面板：左侧拼音选择条 + 主区 4×3 数字键 + 右侧功能列。
///
/// 数字键与 26 键同样走「按下弹窗、滑动跟随、抬起输入」（PopupKeyTracker），
/// 弹窗只显示数字本体。0 键兼空格：点按（抬起触发）走 .spaceOrCommit 语义，
/// 长按切换为光标触控板（onSpaceTrackpad），与 26 键空格同一套回调约定。
/// 地球键（如需显示）固定在音节条列底部，音节条滚动区随之缩短。
final class NineGridView: UIView {
    var onAction: ((NineGridKeyAction) -> Void)?
    var onPinSyllables: (([String]) -> Void)?
    var onSpaceTrackpad: ((SpaceTrackpadPhase, CGFloat) -> Void)?

    /// 地球键的目标-动作接线（同 FullKeyboardView：切换键盘必须走
    /// handleInputModeList 的真实触摸事件）。VC 的注入晚于本视图 init，
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

    private let stripScroll = UIScrollView()
    private var stripButtons: [UIButton] = []
    private var stripEntries: [(label: String, syllables: [String])] = []
    private let globeButton = KeyButton()

    private var gridButtons: [[KeyButton]] = []
    private var digitButtons: [KeyButton] = []
    private var sideButtons: [KeyButton] = []
    private var returnButton: KeyButton?
    private var asciiButton: KeyButton?
    private var spaceButton: KeyButton?
    private var trackpadStartX: CGFloat = 0

    private var presenter: KeyPopupPresenter!
    private var tracker: PopupKeyTracker!

    private let stripWidth: CGFloat = 56
    private let sideWidth: CGFloat = 54
    private let hSpacing: CGFloat = 6
    private let vSpacing: CGFloat = 10

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        presenter = KeyPopupPresenter()
        tracker = PopupKeyTracker(presenter: presenter) { [weak self] point in
            self?.hitTestDigit(at: point)
        }
        buildStrip()
        buildGrid()
        buildSideColumn()
        addSubview(presenter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: 构建

    private func buildStrip() {
        stripScroll.showsVerticalScrollIndicator = false
        stripScroll.isMultipleTouchEnabled = true
        addSubview(stripScroll)

        globeButton.setTitle("🌐", for: .normal)
        globeButton.titleLabel?.font = .systemFont(ofSize: 17)
        globeButton.isFunctionKey = true
        globeButton.isHidden = true
        globeButton.onPress = { [weak self] in self?.onAction?(.nextKeyboard) }
        addSubview(globeButton)
    }

    private func makeDigitButton(_ spec: NineGridKeySpec) -> KeyButton {
        let button = KeyButton()
        button.setTitle(spec.label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 23)
        button.keySubLabel = spec.subLabel
        button.defersActionToRelease = true
        let action = spec.action
        button.onPress = { [weak self] in self?.onAction?(action) }
        button.onTouchEvent = { [weak self] btn, touch, phase in
            guard let self else { return }
            switch phase {
            case .began: self.tracker.touchBegan(btn, touch: touch, in: self)
            case .moved: self.tracker.touchMoved(touch, in: self)
            case .ended: self.tracker.touchEnded(touch, in: self)
            case .cancelled: self.tracker.touchCancelled(touch, in: self)
            }
        }
        digitButtons.append(button)
        addSubview(button)
        return button
    }

    private func buildGrid() {
        gridButtons = NineGridLayout.grid.map { row in
            row.map { spec in
                switch spec.action {
                case .digit:
                    return makeDigitButton(spec)
                case .toggleAscii:
                    let button = KeyButton()
                    button.setTitle(spec.label, for: .normal)
                    button.titleLabel?.font = .systemFont(ofSize: 16)
                    button.isFunctionKey = true
                    button.onPress = { [weak self] in self?.onAction?(.toggleAscii) }
                    asciiButton = button
                    addSubview(button)
                    return button
                case .spaceOrCommit:
                    let button = KeyButton()
                    button.setTitle(spec.label, for: .normal)
                    button.titleLabel?.font = .systemFont(ofSize: 23)
                    button.keySubLabel = spec.subLabel
                    button.defersActionToRelease = true
                    button.firesActionOnReleaseLocally = true
                    button.onPress = { [weak self] in self?.onAction?(.spaceOrCommit) }
                    let lp = UILongPressGestureRecognizer(target: self, action: #selector(spaceLongPressed(_:)))
                    lp.minimumPressDuration = 0.35
                    lp.cancelsTouchesInView = false
                    button.addGestureRecognizer(lp)
                    spaceButton = button
                    addSubview(button)
                    return button
                case .backspace:
                    let button = KeyButton()
                    button.setTitle(spec.label, for: .normal)
                    button.titleLabel?.font = .systemFont(ofSize: 19)
                    button.isFunctionKey = true
                    button.repeatEnabled = true
                    button.onPress = { [weak self] in self?.onAction?(.backspace) }
                    addSubview(button)
                    return button
                default:
                    // grid 模型里只有以上四类动作；其余动作都在 sideColumn。
                    let button = KeyButton()
                    button.setTitle(spec.label, for: .normal)
                    addSubview(button)
                    return button
                }
            }
        }
    }

    private func buildSideColumn() {
        sideButtons = NineGridLayout.sideColumn.map { spec in
            let button = KeyButton()
            button.setTitle(spec.label, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 16)
            button.isFunctionKey = true
            let action = spec.action
            button.onPress = { [weak self] in self?.onAction?(action) }
            if spec.action == .enter { returnButton = button }
            addSubview(button)
            return button
        }
    }

    // MARK: 状态外观

    func setAsciiMode(_ ascii: Bool) {
        asciiButton?.setTitle(ascii ? "英" : "中", for: .normal)
    }

    func setReturnKeyTitle(_ title: String) {
        returnButton?.setTitle(title, for: .normal)
    }

    func setReturnKeyAccent(_ accent: Bool) {
        returnButton?.isAccent = accent
    }

    // MARK: 音节条

    /// 以当前数字串的切分选项重建音节条（点选即锁定对应音节序列）。
    func updateSyllableStrip(entries: [(label: String, syllables: [String])]) {
        stripEntries = entries
        stripButtons.forEach { $0.removeFromSuperview() }
        stripButtons = entries.enumerated().map { index, entry in
            let button = UIButton(type: .system)
            button.setTitle(entry.label, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15)
            button.tag = index
            button.layer.cornerRadius = 6
            button.backgroundColor = UIColor { tc in
                tc.userInterfaceStyle == .dark
                    ? UIColor(white: 0.28, alpha: 1)
                    : UIColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1)
            }
            button.setTitleColor(UIColor { tc in
                tc.userInterfaceStyle == .dark ? .white : .black
            }, for: .normal)
            button.addTarget(self, action: #selector(stripTapped(_:)), for: .touchUpInside)
            stripScroll.addSubview(button)
            return button
        }
        stripScroll.setContentOffset(.zero, animated: false)
        setNeedsLayout()
    }

    @objc private func stripTapped(_ sender: UIButton) {
        guard stripEntries.indices.contains(sender.tag) else { return }
        onPinSyllables?(stripEntries[sender.tag].syllables)
    }

    // MARK: 触控板（0 键长按）

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

    // MARK: 命中测试（弹窗滑动跟随）

    private func hitTestDigit(at point: CGPoint) -> KeyButton? {
        if let hit = digitButtons.first(where: { $0.frame.contains(point) }) { return hit }
        // 行列间隙吸附最近键，避免滑动途中弹窗闪烁消失。
        return digitButtons.first(where: { $0.frame.insetBy(dx: -3, dy: -5).contains(point) })
    }

    // MARK: 布局

    override func layoutSubviews() {
        super.layoutSubviews()
        presenter.frame = bounds
        let globeHeight: CGFloat = showsGlobeButton ? 44 : 0
        stripScroll.frame = CGRect(x: 0, y: 0, width: stripWidth,
                                   height: bounds.height - globeHeight)
        globeButton.frame = CGRect(x: 0, y: bounds.height - globeHeight,
                                   width: stripWidth, height: globeHeight)
        // 音节条内按钮纵向堆叠。
        var stripY: CGFloat = 0
        for button in stripButtons {
            button.frame = CGRect(x: 3, y: stripY, width: stripWidth - 6, height: 34)
            stripY += 34 + 6
        }
        stripScroll.contentSize = CGSize(width: stripWidth, height: stripY)

        let gridX = stripWidth + hSpacing
        let gridWidth = bounds.width - gridX - sideWidth - hSpacing
        let rowCount = CGFloat(NineGridLayout.grid.count)
        let rowHeight = (bounds.height - vSpacing * (rowCount - 1)) / rowCount
        for (rowIndex, row) in gridButtons.enumerated() {
            let y = CGFloat(rowIndex) * (rowHeight + vSpacing)
            let cellWidth = (gridWidth - hSpacing * CGFloat(row.count - 1)) / CGFloat(row.count)
            for (colIndex, button) in row.enumerated() {
                button.frame = CGRect(x: gridX + CGFloat(colIndex) * (cellWidth + hSpacing),
                                      y: y, width: cellWidth, height: rowHeight)
            }
        }
        // 右侧列：回车占前两行高，26 键/符各占一行。
        let sideX = bounds.width - sideWidth
        if sideButtons.count == 3 {
            sideButtons[0].frame = CGRect(x: sideX, y: 0, width: sideWidth,
                                          height: rowHeight * 2 + vSpacing)
            sideButtons[1].frame = CGRect(x: sideX, y: rowHeight * 2 + vSpacing * 2,
                                          width: sideWidth, height: rowHeight)
            sideButtons[2].frame = CGRect(x: sideX, y: rowHeight * 3 + vSpacing * 3,
                                          width: sideWidth, height: rowHeight)
        }
    }
}
