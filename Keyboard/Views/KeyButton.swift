import UIKit

/// 键盘按键按钮：按下变色反馈 + 可选长按连发（退格用）。
///
/// 连发语义：按下先立即触发一次 onPress；持续按住超过 delay 后以 interval
/// 间隔重复触发 onRepeat（缺省等于 onPress）。松手/移出/取消即停。
/// 多点触控：每个按钮独立计时，互不干扰；宿主 view 需开 isMultipleTouchEnabled。
final class KeyButton: UIButton {
    var onPress: (() -> Void)?
    var onRepeat: (() -> Void)?
    /// 是否启用长按连发（退格键为 true）。
    var repeatEnabled = false
    var repeatDelay: TimeInterval = 0.45
    var repeatInterval: TimeInterval = 0.055

    /// 功能键（退格/回车/切换类）用稍深的底色，与字母键区分。
    var isFunctionKey = false {
        didSet { refreshColors() }
    }

    private var delayTimer: Timer?
    private var repeatTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel?.textAlignment = .center
        layer.cornerRadius = 5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 0.28
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        refreshColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        // 动态色随深浅色模式切换（键盘扩展跟随宿主 App 的外观）。
        let normal: UIColor = isFunctionKey
            ? UIColor { tc in tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.28, alpha: 1) : UIColor(red: 0.72, green: 0.74, blue: 0.78, alpha: 1) }
            : UIColor { tc in tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.42, alpha: 1) : .white }
        let highlighted: UIColor = UIColor { tc in tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.22, alpha: 1) : UIColor(red: 0.62, green: 0.64, blue: 0.69, alpha: 1) }
        backgroundColor = isHighlighted ? highlighted : normal
        setTitleColor(UIColor { tc in tc.userInterfaceStyle == .dark ? .white : .black }, for: .normal)
    }

    @objc private func touchDown() {
        onPress?()
        guard repeatEnabled else { return }
        stopTimers()
        delayTimer = Timer.scheduledTimer(withTimeInterval: repeatDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: self.repeatInterval, repeats: true) { [weak self] _ in
                guard let self else { return }
                if let onRepeat = self.onRepeat { onRepeat() } else { self.onPress?() }
            }
        }
    }

    @objc private func touchEnded() {
        stopTimers()
    }

    private func stopTimers() {
        delayTimer?.invalidate(); delayTimer = nil
        repeatTimer?.invalidate(); repeatTimer = nil
    }

    deinit { stopTimers() }
}
