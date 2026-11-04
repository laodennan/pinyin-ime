import UIKit

/// 候选栏：左侧预编辑文本（拼音），中部横向滚动候选条，右侧展开按钮。
///
/// 候选条展示的是**全量候选**（引擎 allCandidates()，跨页），点选时回调给出
/// 全量下标，由 KeyboardViewController 换算成「翻页 + 选当前页」执行。
/// 高亮下标同样是全量下标（= 页号 × 页大小 + 页内高亮，VC 侧换算后传入）。
final class CandidateBarView: UIView {
    var onSelectCandidate: ((Int) -> Void)?
    var onExpand: (() -> Void)?

    private let preeditLabel = UILabel()
    private let scrollView = UIScrollView()
    private let expandButton = UIButton(type: .system)
    private var candidateButtons: [UIButton] = []

    private(set) var candidates: [RimeCandidate] = []
    private var highlightedGlobalIndex: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        preeditLabel.font = .systemFont(ofSize: 16)
        preeditLabel.lineBreakMode = .byTruncatingHead
        addSubview(preeditLabel)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.isMultipleTouchEnabled = true
        addSubview(scrollView)

        expandButton.setTitle("⌄", for: .normal)
        expandButton.titleLabel?.font = .systemFont(ofSize: 22)
        expandButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        addSubview(expandButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 以引擎最新状态刷新：preedit、全部候选、高亮的全量下标。
    /// candidates 为空时展开按钮隐藏；条内内容回到开头。
    func update(preedit: String, candidates: [RimeCandidate], highlightedGlobalIndex: Int?) {
        preeditLabel.text = preedit
        self.candidates = candidates
        self.highlightedGlobalIndex = highlightedGlobalIndex
        expandButton.isHidden = candidates.count <= 1
        rebuildButtons()
        scrollView.setContentOffset(.zero, animated: false)
        setNeedsLayout()
    }

    private func rebuildButtons() {
        candidateButtons.forEach { $0.removeFromSuperview() }
        candidateButtons = candidates.enumerated().map { index, candidate in
            let button = UIButton(type: .system)
            button.setTitle(candidate.text, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 20)
            button.tag = index
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 9, bottom: 0, right: 9)
            button.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
            if index == highlightedGlobalIndex {
                button.backgroundColor = UIColor { tc in
                    tc.userInterfaceStyle == .dark
                        ? UIColor(white: 0.35, alpha: 1)
                        : UIColor(red: 0.85, green: 0.87, blue: 0.92, alpha: 1)
                }
                button.layer.cornerRadius = 6
            }
            button.setTitleColor(UIColor { tc in tc.userInterfaceStyle == .dark ? .white : .black }, for: .normal)
            scrollView.addSubview(button)
            return button
        }
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        onSelectCandidate?(sender.tag)
    }

    @objc private func expandTapped() {
        onExpand?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let barHeight = bounds.height
        // 预编辑区：按文本量宽，但最多占 38%。
        let preeditWidth = min(preeditLabel.intrinsicContentSize.width + 16, bounds.width * 0.38)
        preeditLabel.frame = CGRect(x: 8, y: 0, width: max(preeditWidth - 8, 0), height: barHeight)
        let expandWidth: CGFloat = expandButton.isHidden ? 0 : 38
        expandButton.frame = CGRect(x: bounds.width - expandWidth, y: 0, width: expandWidth, height: barHeight)
        scrollView.frame = CGRect(x: preeditWidth, y: 0,
                                  width: bounds.width - preeditWidth - expandWidth, height: barHeight)
        var x: CGFloat = 0
        for button in candidateButtons {
            let w = button.intrinsicContentSize.width
            button.frame = CGRect(x: x, y: 4, width: w, height: barHeight - 8)
            x += w + 2
        }
        scrollView.contentSize = CGSize(width: x, height: barHeight)
    }
}

/// 候选展开列表：候选多时铺满键盘区逐行点选，顶部带关闭按钮。
/// 行内显示「候选文本 + 注释（拼音）」，点选回调全量下标。
final class CandidateListView: UIView {
    var onSelectCandidate: ((Int) -> Void)?
    var onClose: (() -> Void)?

    private let headerLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var candidates: [RimeCandidate] = []
    private var highlightedGlobalIndex: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        headerLabel.font = .systemFont(ofSize: 15)
        addSubview(headerLabel)
        closeButton.setTitle("收起 ⌃", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 15)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(closeButton)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 46
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        addSubview(tableView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(preedit: String, candidates: [RimeCandidate], highlightedGlobalIndex: Int?) {
        headerLabel.text = preedit
        self.candidates = candidates
        self.highlightedGlobalIndex = highlightedGlobalIndex
        tableView.reloadData()
        setNeedsLayout()
    }

    @objc private func closeTapped() { onClose?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        headerLabel.frame = CGRect(x: 12, y: 0, width: bounds.width - 110, height: 36)
        closeButton.frame = CGRect(x: bounds.width - 98, y: 0, width: 90, height: 36)
        tableView.frame = CGRect(x: 0, y: 36, width: bounds.width, height: bounds.height - 36)
    }
}

extension CandidateListView: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        candidates.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseId = "candidate"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseId)
            ?? UITableViewCell(style: .value1, reuseIdentifier: reuseId)
        let candidate = candidates[indexPath.row]
        cell.textLabel?.text = candidate.text
        cell.textLabel?.font = .systemFont(ofSize: 19)
        cell.detailTextLabel?.text = candidate.comment
        cell.backgroundColor = indexPath.row == highlightedGlobalIndex
            ? UIColor(white: 0.5, alpha: 0.18) : .clear
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelectCandidate?(indexPath.row)
    }
}
