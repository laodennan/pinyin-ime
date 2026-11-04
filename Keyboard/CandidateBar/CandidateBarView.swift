import UIKit

/// 候选栏：可选的顶部音节选项行（九宫格）+ 主行（左侧预编辑文本、中部
/// 横向滚动候选条、右侧展开按钮）。
///
/// 候选条展示的是引擎候选的**有界切片**（VC 用 candidatesSlice 取前 48），
/// 点选时回调给出全量下标，由 KeyboardViewController 换算成「翻页 + 选
/// 当前页」执行。高亮下标同样是全量下标（= 页号 × 页大小 + 页内高亮，
/// VC 侧换算后传入）。
///
/// 音节行（实现轮 4）：数据来自 T9Session.stripOptions()，VC 在 refresh
/// 时经 setSyllableRow 灌入；点选回调 onPinSyllables 锁定音节序列。
/// 行可见时本视图期望高度 76、否则 40（VC 读 syllableRowVisible 定高）。
///
/// 性能（实现轮 4）：候选按钮与音节 chips 均池化复用——只改标题/高亮/
/// 可见性，不再每键整表重建；preedit 文本未变时不重置候选条滚动偏移。
final class CandidateBarView: UIView {
    var onSelectCandidate: ((Int) -> Void)?
    var onExpand: (() -> Void)?
    var onPinSyllables: (([String]) -> Void)?

    /// 音节行高（可见时主行之上额外占这么多）。
    static let syllableRowHeight: CGFloat = 36

    private let syllableScroll = UIScrollView()
    private let preeditLabel = UILabel()
    private let scrollView = UIScrollView()
    private let expandButton = UIButton(type: .system)
    private var candidateButtons: [UIButton] = []
    private var chipButtons: [UIButton] = []
    private var chipEntries: [(label: String, syllables: [String])] = []
    private var chipKey: [String] = []

    private(set) var candidates: [RimeCandidate] = []
    private var highlightedGlobalIndex: Int?
    private var lastPreeditText: String?
    /// 音节行当前是否可见（VC 据此决定候选栏总高 76 / 40）。
    private(set) var syllableRowVisible = false

    private static let highlightBackground = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.35, alpha: 1)
            : UIColor(red: 0.85, green: 0.87, blue: 0.92, alpha: 1)
    }
    private static let chipBackground = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.28, alpha: 1)
            : UIColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1)
    }
    private static let labelColor = UIColor { tc in
        tc.userInterfaceStyle == .dark ? .white : .black
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        syllableScroll.showsHorizontalScrollIndicator = false
        syllableScroll.isMultipleTouchEnabled = true
        syllableScroll.isHidden = true
        addSubview(syllableScroll)

        preeditLabel.font = .systemFont(ofSize: 16)
        preeditLabel.lineBreakMode = .byTruncatingHead
        addSubview(preeditLabel)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.isMultipleTouchEnabled = true
        addSubview(scrollView)

        expandButton.setTitle("⌄", for: .normal)
        expandButton.titleLabel?.font = .systemFont(ofSize: 22)
        // 系统按钮默认蓝 tint 与苹果观感不符，显式钉成 label 色。
        expandButton.setTitleColor(.label, for: .normal)
        expandButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        addSubview(expandButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 以引擎最新状态刷新：preedit、候选切片、高亮的全量下标。
    /// 按钮池复用：逐个改标题/高亮/可见性；preedit 未变时保留滚动偏移。
    func update(preedit: String, candidates: [RimeCandidate], highlightedGlobalIndex: Int?) {
        let preeditChanged = preedit != lastPreeditText
        lastPreeditText = preedit
        preeditLabel.text = preedit
        self.candidates = candidates
        self.highlightedGlobalIndex = highlightedGlobalIndex
        expandButton.isHidden = candidates.count <= 1
        while candidateButtons.count < candidates.count {
            candidateButtons.append(makeCandidateButton())
        }
        for (index, button) in candidateButtons.enumerated() {
            guard index < candidates.count else {
                button.isHidden = true
                continue
            }
            button.isHidden = false
            button.tag = index
            button.setTitle(candidates[index].text, for: .normal)
            button.backgroundColor = index == highlightedGlobalIndex
                ? Self.highlightBackground : .clear
        }
        if preeditChanged {
            scrollView.setContentOffset(.zero, animated: false)
        }
        setNeedsLayout()
    }

    private func makeCandidateButton() -> UIButton {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 20)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 9, bottom: 0, right: 9)
        button.layer.cornerRadius = 6
        button.setTitleColor(Self.labelColor, for: .normal)
        button.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
        scrollView.addSubview(button)
        return button
    }

    // MARK: 音节选项行

    /// 灌入音节选项并定可见性（entries 为空时恒不可见）。内容未变时不重建
    /// chips（stripOptions 在组合不变的 refresh 里会重复产出同一批选项）。
    func setSyllableRow(entries: [(label: String, syllables: [String])], visible: Bool) {
        let show = visible && !entries.isEmpty
        let key = entries.map { $0.label + "\u{1}" + $0.syllables.joined(separator: "'") }
        if show != syllableRowVisible || key != chipKey {
            syllableRowVisible = show
            chipKey = key
            chipEntries = entries
            syncChips()
        }
        setNeedsLayout()
    }

    private func syncChips() {
        while chipButtons.count < chipEntries.count {
            chipButtons.append(makeChipButton())
        }
        for (index, button) in chipButtons.enumerated() {
            guard index < chipEntries.count else {
                button.isHidden = true
                continue
            }
            button.isHidden = false
            button.tag = index
            button.setTitle(chipEntries[index].label, for: .normal)
        }
        syllableScroll.setContentOffset(.zero, animated: false)
    }

    private func makeChipButton() -> UIButton {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 15)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        button.layer.cornerRadius = 6
        button.backgroundColor = Self.chipBackground
        button.setTitleColor(Self.labelColor, for: .normal)
        button.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
        syllableScroll.addSubview(button)
        return button
    }

    @objc private func chipTapped(_ sender: UIButton) {
        guard chipEntries.indices.contains(sender.tag) else { return }
        onPinSyllables?(chipEntries[sender.tag].syllables)
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        onSelectCandidate?(sender.tag)
    }

    @objc private func expandTapped() {
        onExpand?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rowHeight: CGFloat = syllableRowVisible ? Self.syllableRowHeight : 0
        syllableScroll.isHidden = !syllableRowVisible
        syllableScroll.frame = CGRect(x: 0, y: 0, width: bounds.width, height: rowHeight)
        if syllableRowVisible {
            var chipX: CGFloat = 8
            for button in chipButtons where !button.isHidden {
                let w = button.intrinsicContentSize.width
                button.frame = CGRect(x: chipX, y: 4, width: w, height: rowHeight - 8)
                chipX += w + 6
            }
            syllableScroll.contentSize = CGSize(width: chipX, height: rowHeight)
        }
        let barHeight = bounds.height - rowHeight
        // 预编辑区：按文本量宽，但最多占 38%。
        let preeditWidth = min(preeditLabel.intrinsicContentSize.width + 16, bounds.width * 0.38)
        preeditLabel.frame = CGRect(x: 8, y: rowHeight, width: max(preeditWidth - 8, 0), height: barHeight)
        let expandWidth: CGFloat = expandButton.isHidden ? 0 : 38
        expandButton.frame = CGRect(x: bounds.width - expandWidth, y: rowHeight, width: expandWidth, height: barHeight)
        scrollView.frame = CGRect(x: preeditWidth, y: rowHeight,
                                  width: bounds.width - preeditWidth - expandWidth, height: barHeight)
        var x: CGFloat = 0
        for button in candidateButtons where !button.isHidden {
            let w = button.intrinsicContentSize.width
            button.frame = CGRect(x: x, y: rowHeight + 4, width: w, height: barHeight - 8)
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
        // 同候选栏展开箭头：钉成 label 色，不用系统蓝。
        closeButton.setTitleColor(.label, for: .normal)
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
