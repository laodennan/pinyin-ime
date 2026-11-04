import UIKit

/// 键盘扩展入口（步骤 0 骨架：占位键盘，能输入字母/退格，证明扩展链路通）。
///
/// 后续步骤接入点：
/// - 步骤 1：viewDidLoad 中启动 RimeEngine（sharedDataDir = bundle 内 SharedData，
///   userDataDir = 扩展沙盒 Library/RimeUserData，见 PLAN.md 4.2），
///   字母键改走 engine.processKey，候选栏读 engine.menu；
/// - 步骤 3：换上 FullKeyboardLayout 的完整 UI 与候选栏展开/分页；
/// - 步骤 4：九宫格模式下按键先进 T9 状态机（digitBuffer → T9Mapper.segment
///   → engine.setInput），不透传数字给引擎。
final class KeyboardViewController: UIInputViewController {
    private let placeholderLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        placeholderLabel.text = "拼音键盘（骨架）"
        placeholderLabel.textAlignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
        // TODO(步骤 1): 在此启动 RimeEngine 并构建候选栏 + 26 键 UI。
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // TODO(步骤 1): 若引擎未启动则启动；已启动则同步 ascii_mode 等状态。
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // TODO(步骤 1): 不在此 stop 引擎（切回键盘应秒开）；仅在 didReceiveMemoryWarning
        // 或扩展终止时 stop 并确保持久化 userdb。
    }

    // 占位输入（步骤 1 后删除，改由 UI 层按键回调调用）：
    func placeholderInsert(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    func placeholderBackspace() {
        textDocumentProxy.deleteBackward()
    }
}
