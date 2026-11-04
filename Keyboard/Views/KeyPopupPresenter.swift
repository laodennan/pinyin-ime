import UIKit

/// 空格长按触控板的阶段回调（面板 → KeyboardViewController）。
/// moved 的 CGFloat 为自触控板激活点起算的水平累计位移（pt）。
enum SpaceTrackpadPhase {
    case began
    case moved
    case ended
}

/// 按键弹窗呈现器：两种形态——单键放大气泡、长按变体条。
///
/// 本视图覆盖整个面板且永不拦截触摸（isUserInteractionEnabled = false），
/// 只按面板坐标绘制。变体条的几何（条宽、格宽、下标换算）全部收在这里，
/// 保证「渲染出来的格子」与「手指位置换算出的下标」永远同源。
final class KeyPopupPresenter: UIView {
    private let bubble = UIView()
    private let bigLabel = UILabel()
    private var variantLabels: [UILabel] = []
    private var stripFrame: CGRect = .zero
    private var cellWidth: CGFloat = 42
    private(set) var variantCount = 0
    private(set) var selectedVariantIndex = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        bubble.layer.cornerRadius = 9
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOffset = CGSize(width: 0, height: 2)
        bubble.layer.shadowRadius = 6
        bubble.layer.shadowOpacity = 0.25
        bubble.isHidden = true
        bigLabel.textAlignment = .center
        bubble.addSubview(bigLabel)
        addSubview(bubble)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyBubbleColors() {
        bubble.backgroundColor = UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(white: 0.32, alpha: 1) : .white
        }
        bigLabel.textColor = UIColor { tc in
            tc.userInterfaceStyle == .dark ? .white : .black
        }
    }

    /// 放大镜气泡：居中悬于键上方，宽不小于键宽，高 56，底边距键顶 3pt。
    func showMagnifier(above keyFrame: CGRect, text: String) {
        clearVariants()
        variantCount = 0
        applyBubbleColors()
        bigLabel.font = .systemFont(ofSize: 32)
        bigLabel.text = text
        bigLabel.isHidden = false
        let w = max(keyFrame.width, 54)
        let h: CGFloat = 56
        let x = clamp(keyFrame.midX - w / 2, 4, max(bounds.width - w - 4, 4))
        bubble.frame = CGRect(x: x, y: keyFrame.minY - h - 3, width: w, height: h)
        bigLabel.frame = bubble.bounds
        bubble.isHidden = false
    }

    /// 变体条：以键为中心水平展开（贴边时整体钳制进面板），选中格高亮。
    func showVariants(above keyFrame: CGRect, variants: [String], selected: Int) {
        applyBubbleColors()
        bigLabel.isHidden = true
        clearVariants()
        variantCount = variants.count
        selectedVariantIndex = selected
        let h: CGFloat = 56
        let w = max(keyFrame.width + 12, CGFloat(variants.count) * 42)
        let x = clamp(keyFrame.midX - w / 2, 4, max(bounds.width - w - 4, 4))
        stripFrame = CGRect(x: x, y: keyFrame.minY - h - 3, width: w, height: h)
        bubble.frame = stripFrame
        // 格宽按钳制后的实际条宽均分——与 variantIndex(forPanelX:) 的换算同源。
        cellWidth = w / CGFloat(max(variants.count, 1))
        for (i, value) in variants.enumerated() {
            let label = UILabel()
            label.text = value
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 23)
            label.frame = CGRect(x: CGFloat(i) * cellWidth, y: 4, width: cellWidth, height: h - 8)
            label.layer.cornerRadius = 6
            label.clipsToBounds = true
            bubble.addSubview(label)
            variantLabels.append(label)
        }
        refreshVariantColors()
        bubble.isHidden = false
    }

    /// 面板坐标 x → 变体下标（钳制在有效范围内）。
    func variantIndex(forPanelX x: CGFloat) -> Int {
        guard variantCount > 0 else { return 0 }
        let idx = Int((x - stripFrame.minX) / cellWidth)
        return min(max(idx, 0), variantCount - 1)
    }

    func selectVariant(_ index: Int) {
        guard index != selectedVariantIndex, index >= 0, index < variantCount else { return }
        selectedVariantIndex = index
        refreshVariantColors()
    }

    func hide() {
        bubble.isHidden = true
        clearVariants()
        variantCount = 0
    }

    private func refreshVariantColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        for (i, label) in variantLabels.enumerated() {
            let selected = i == selectedVariantIndex
            label.backgroundColor = selected ? UIColor.systemBlue.withAlphaComponent(0.9) : .clear
            label.textColor = selected ? .white : (dark ? .white : .black)
        }
    }

    private func clearVariants() {
        variantLabels.forEach { $0.removeFromSuperview() }
        variantLabels = []
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }
}

/// 面板级按键追踪：实现苹果式「按下弹放大镜、滑动跟随换键、抬起才输入」。
///
/// 单触摸追踪：追踪期间第二个触摸按下时，先把当前键按已选定提交再接管新
/// 触摸（快速连打不丢字、弹窗不冲突）。长按变体由面板的
/// UILongPressGestureRecognizer 在触发时调 beginVariants 接入；变体激活后
/// 本次触摸的移动改为变体选择、抬起改为输入选中的变体字面量。
/// 被追踪的按键自身须设 defersActionToRelease（按下不触发语义），
/// 其语义动作统一由本类在抬起/接管时经 onPress 触发。
final class PopupKeyTracker {
    /// 变体被选定输入时回调（面板转交 VC：先提交组合串再直插字面量）。
    var onVariantInput: ((String) -> Void)?
    /// 放大镜显示文本（缺省取键面标题；面板可覆写）。
    var textForKey: (KeyButton) -> String = { $0.title(for: .normal) ?? "" }

    private let presenter: KeyPopupPresenter
    private let hitTest: (CGPoint) -> KeyButton?
    private var activeTouch: UITouch?
    private var currentKey: KeyButton?
    private var activeVariants: [String]?

    init(presenter: KeyPopupPresenter, hitTest: @escaping (CGPoint) -> KeyButton?) {
        self.presenter = presenter
        self.hitTest = hitTest
    }

    func touchBegan(_ button: KeyButton, touch: UITouch, in view: UIView) {
        if let active = activeTouch, active != touch {
            commitCurrent()
        }
        activeTouch = touch
        currentKey = button
        activeVariants = nil
        button.isHighlighted = true
        presenter.showMagnifier(above: button.frame, text: textForKey(button))
    }

    func touchMoved(_ touch: UITouch, in view: UIView) {
        guard touch == activeTouch else { return }
        let point = touch.location(in: view)
        if activeVariants != nil {
            presenter.selectVariant(presenter.variantIndex(forPanelX: point.x))
            return
        }
        let hit = hitTest(point)
        if hit != currentKey {
            currentKey?.isHighlighted = false
            currentKey = hit
            if let hit {
                hit.isHighlighted = true
                presenter.showMagnifier(above: hit.frame, text: textForKey(hit))
            } else {
                presenter.hide()
            }
        }
    }

    func touchEnded(_ touch: UITouch, in view: UIView) {
        guard touch == activeTouch else { return }
        commitCurrent()
    }

    func touchCancelled(_ touch: UITouch, in view: UIView) {
        guard touch == activeTouch else { return }
        cleanup()
    }

    /// 长按变体激活：把当前追踪切换为变体选择（初始选中按手势落点换算）。
    func beginVariants(for button: KeyButton, variants: [String], at point: CGPoint, in view: UIView) {
        guard activeTouch != nil, currentKey == button, !variants.isEmpty else { return }
        activeVariants = variants
        presenter.showVariants(above: button.frame, variants: variants, selected: 0)
        presenter.selectVariant(presenter.variantIndex(forPanelX: point.x))
    }

    /// 面板切页/隐藏时强制收尾（不提交）。
    func cancel() { cleanup() }

    private func commitCurrent() {
        if let variants = activeVariants {
            onVariantInput?(variants[presenter.selectedVariantIndex])
        } else {
            currentKey?.onPress?()
        }
        cleanup()
    }

    private func cleanup() {
        currentKey?.isHighlighted = false
        currentKey = nil
        activeTouch = nil
        activeVariants = nil
        presenter.hide()
    }
}
