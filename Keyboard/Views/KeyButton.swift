import UIKit

/// 触摸跟踪阶段（面板级弹窗跟随用，见 PopupKeyTracker）。
enum KeyTouchPhase {
    case began, moved, ended, cancelled
}

/// 键盘按键按钮。
///
/// 两种触发模式：
/// - 即时模式（缺省）：按下（touchDown）即触发 onPress；repeatEnabled 时
///   按下先触发一次、0.4s 后以 55ms 间隔连发（退格用）。连发 tick 若设了
///   onRepeatTick 则走它（带已按住时长，VC 据此切换整词删除），否则走
///   onRepeat ?? onPress。
/// - 延迟模式（defersActionToRelease，字母/数字键用）：按下不触发语义，
///   由面板的 PopupKeyTracker 在抬起时触发最终落键的 onPress（苹果式
///   「弹窗跟随、抬起输入」）；空格键则设 firesActionOnReleaseLocally，
///   由本键在抬起（仍在键内且未被触控板抑制）时自行触发。
///
/// 多点触控：每个按钮独立计时，互不干扰；宿主 view 需开 isMultipleTouchEnabled。
final class KeyButton: UIButton {
    var onPress: (() -> Void)?
    var onRepeat: (() -> Void)?
    /// 连发 tick 回调（参数为本次按住的累计时长）；设置后优先于 onRepeat/onPress。
    var onRepeatTick: ((TimeInterval) -> Void)?
    /// 是否启用长按连发（退格键为 true）。
    var repeatEnabled = false
    var repeatDelay: TimeInterval = 0.4
    var repeatInterval: TimeInterval = 0.055

    /// 功能键（退格/回车/切换类）用稍深的底色，与字母键区分。
    var isFunctionKey = false {
        didSet { refreshColors() }
    }
    /// 强调态（回车键在 .search/.send 场景）：系统蓝底白字，仿苹果。
    var isAccent = false {
        didSet { refreshColors() }
    }
    /// 锁定态（Shift 一次性大写/大写锁定）：底色反白与普通功能键区分。
    var isLatched = false {
        didSet { refreshColors() }
    }

    /// 延迟触发：按下不触发 onPress（见类注释）。
    var defersActionToRelease = false
    /// 延迟触发时由本键在抬起时自行触发 onPress（空格键用；
    /// 字母键为 false，抬起触发归 PopupKeyTracker）。
    var firesActionOnReleaseLocally = false
    /// 触摸事件转发（面板级弹窗跟随）：(按键, 触摸, 阶段)。
    var onTouchEvent: ((KeyButton, UITouch, KeyTouchPhase) -> Void)?
    /// 本次抬起触发被抑制（空格长按进入触控板后由面板置位）：抬起时消费一次后清零。
    var suppressNextReleaseAction = false

    /// 键面副标（九宫格数字键的字母组，如 "abc"）：小字显示在键面下部。
    var keySubLabel: String? {
        didSet {
            subLabelView.text = keySubLabel
            subLabelView.isHidden = keySubLabel == nil
            titleEdgeInsets = keySubLabel == nil
                ? .zero
                : UIEdgeInsets(top: -11, left: 0, bottom: 0, right: 0)
        }
    }
    private let subLabelView = UILabel()

    private var delayTimer: Timer?
    private var repeatTimer: Timer?
    private var pressStartDate: Date?

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel?.textAlignment = .center
        layer.cornerRadius = 5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 0.28
        subLabelView.font = .systemFont(ofSize: 10)
        subLabelView.textAlignment = .center
        subLabelView.isHidden = true
        subLabelView.textColor = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.6)
                : UIColor(white: 0, alpha: 0.55)
        }
        addSubview(subLabelView)
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        refreshColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !subLabelView.isHidden {
            subLabelView.frame = CGRect(x: 0, y: bounds.height - 17, width: bounds.width, height: 13)
        }
    }

    override var isHighlighted: Bool {
        didSet { refreshColors() }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous) {
            refreshColors()
        }
    }

    private func refreshColors() {
        // 配色按苹果自带键盘观感（PLAN 实现轮 2）：浅色底 #D1D3D9（VC 背景）、
        // 字母键白、功能键 #ACB4BE；深色底 #242426、字母键 #46464A、功能键 #2E2E30。
        let normal: UIColor
        if isAccent {
            normal = .systemBlue
        } else if isLatched {
            normal = UIColor { tc in tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.45, alpha: 1) : .white }
        } else if isFunctionKey {
            normal = UIColor { tc in tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.18, alpha: 1)
                : UIColor(red: 0.675, green: 0.706, blue: 0.745, alpha: 1) }
        } else {
            normal = UIColor { tc in tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.275, alpha: 1) : .white }
        }
        let highlighted: UIColor = isAccent
            ? UIColor.systemBlue.withAlphaComponent(0.75)
            : UIColor { tc in tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.38, alpha: 1)
                : UIColor(red: 0.62, green: 0.64, blue: 0.69, alpha: 1) }
        backgroundColor = isHighlighted ? highlighted : normal
        let title: UIColor = isAccent
            ? .white
            : UIColor { tc in tc.userInterfaceStyle == .dark ? .white : .black }
        setTitleColor(title, for: .normal)
    }

    @objc private func touchDown() {
        // 延迟模式下按下不触发语义（等抬起）；连发也不启动（延迟键均不连发）。
        guard !defersActionToRelease else { return }
        onPress?()
        guard repeatEnabled else { return }
        stopTimers()
        pressStartDate = Date()
        delayTimer = Timer.scheduledTimer(withTimeInterval: repeatDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: self.repeatInterval, repeats: true) { [weak self] _ in
                guard let self else { return }
                if let onRepeatTick = self.onRepeatTick, let start = self.pressStartDate {
                    onRepeatTick(Date().timeIntervalSince(start))
                } else if let onRepeat = self.onRepeat {
                    onRepeat()
                } else {
                    self.onPress?()
                }
            }
        }
    }

    @objc private func touchEnded() {
        stopTimers()
        pressStartDate = nil
    }

    // MARK: 触摸转发与本地抬起触发

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        suppressNextReleaseAction = false
        if let touch = touches.first { onTouchEvent?(self, touch, .began) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        if let touch = touches.first { onTouchEvent?(self, touch, .moved) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if let touch = touches.first {
            // 本地抬起触发（空格）：仍在键面（上下放宽）且未被触控板抑制时才触发。
            if defersActionToRelease, firesActionOnReleaseLocally {
                if suppressNextReleaseAction {
                    suppressNextReleaseAction = false
                } else if bounds.insetBy(dx: -6, dy: -10).contains(touch.location(in: self)) {
                    onPress?()
                }
            }
            onTouchEvent?(self, touch, .ended)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        suppressNextReleaseAction = false
        if let touch = touches.first { onTouchEvent?(self, touch, .cancelled) }
    }

    private func stopTimers() {
        delayTimer?.invalidate(); delayTimer = nil
        repeatTimer?.invalidate(); repeatTimer = nil
    }

    deinit { stopTimers() }
}
