import UIKit

/// 键盘扩展入口：装配 Rime 引擎、候选栏与键盘面板，解释按键语义。
///
/// 数据流：按键 → 本类翻译为引擎调用（processKey / 选词 / 翻页）→ refresh()
/// 统一回收上屏文本并以引擎快照刷新候选栏。候选栏/展开列表给出的是全量下标，
/// 本类负责换算成引擎的「翻到目标页 + 选当前页下标」。
///
/// 布局状态：layoutMode（26 键 / 九宫格占位）持久化在 SettingsBridge 的
/// defaultLayout；page（字母/符号）为会话内临时状态，不落盘。
/// 九宫格界面本轮不实现（后续轮按 PLAN 第 3 节接 T9 状态机），切过去只显示
/// 占位页并可切回；切换本身与持久化是真实生效的。
final class KeyboardViewController: UIInputViewController {
    private enum LayoutMode { case full26, nineGrid }
    private enum Page { case letters, symbols }

    private let engine: RimeEngine = LibrimeKitRimeEngine()

    private let statusLabel = UILabel()
    private let candidateBar = CandidateBarView()
    private let candidateList = CandidateListView()
    private let fullKeyboard = FullKeyboardView()
    private let symbolKeyboard = SymbolKeyboardView()
    private let nineGridPlaceholder = UIView()
    private var heightConstraint: NSLayoutConstraint?

    private var layoutMode: LayoutMode = .full26
    private var page: Page = .letters
    private var candidatesExpanded = false
    private var capsOn = false
    /// 引擎每页候选数：从引擎返回的满页推得并缓存（展开点选换算页码用）。
    private var cachedPageSize: Int?

    private let candidateBarHeight: CGFloat = 44
    private let keyboardHeight: CGFloat = 216
    private let expandedListHeight: CGFloat = 308

    // MARK: 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.16, alpha: 1)
                : UIColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1)
        }
        view.isMultipleTouchEnabled = true

        buildSubviews()
        restoreLayoutMode()
        startEngine()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let globe = needsInputModeSwitchKey
        fullKeyboard.showsGlobeButton = globe
        symbolKeyboard.showsGlobeButton = globe
        updateReturnKeyTitle()
        if engine.isReady { refresh() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 不 stop 引擎：切回键盘应秒开。userdb 的同步在内存警告与进程级
        // 回收前由系统时机触发 stop（见 didReceiveMemoryWarning）。
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // 键盘扩展内存红线紧（PLAN 2.1）：收到警告时至少把 userdb 同步落盘，
        // 即使随即被系统杀掉也不丢学习数据。引擎本体不销毁（finalize 不可逆）。
        engine.stop()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateReturnKeyTitle()
    }

    // MARK: 装配

    private func buildSubviews() {
        statusLabel.text = "正在准备词库…"
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 15)
        view.addSubview(statusLabel)

        candidateBar.onSelectCandidate = { [weak self] in self?.selectGlobalCandidate($0) }
        candidateBar.onExpand = { [weak self] in self?.setCandidatesExpanded(true) }
        view.addSubview(candidateBar)

        candidateList.onSelectCandidate = { [weak self] in self?.selectGlobalCandidate($0) }
        candidateList.onClose = { [weak self] in self?.setCandidatesExpanded(false) }
        candidateList.isHidden = true
        view.addSubview(candidateList)

        fullKeyboard.onAction = { [weak self] in self?.handleKeyAction($0) }
        fullKeyboard.globeTarget = self
        fullKeyboard.globeAction = #selector(handleInputModeList(from:with:))
        view.addSubview(fullKeyboard)

        symbolKeyboard.onSymbol = { [weak self] in self?.handleSymbol($0) }
        symbolKeyboard.onAction = { [weak self] in self?.handleSymbolPanelAction($0) }
        symbolKeyboard.globeTarget = self
        symbolKeyboard.globeAction = #selector(handleInputModeList(from:with:))
        symbolKeyboard.isHidden = true
        view.addSubview(symbolKeyboard)

        buildNineGridPlaceholder()
        view.addSubview(nineGridPlaceholder)

        heightConstraint = view.heightAnchor.constraint(equalToConstant: candidateBarHeight + keyboardHeight)
        heightConstraint?.priority = UILayoutPriority(999)
        heightConstraint?.isActive = true
        applyVisibility()
    }

    private func buildNineGridPlaceholder() {
        let label = UILabel()
        label.text = "九宫格布局开发中，下一版上线"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16)
        label.tag = 101
        nineGridPlaceholder.addSubview(label)
        let button = UIButton(type: .system)
        button.setTitle("切回 26 键", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16)
        button.tag = 102
        button.addTarget(self, action: #selector(switchToFull26), for: .touchUpInside)
        nineGridPlaceholder.addSubview(button)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        statusLabel.frame = CGRect(x: 0, y: candidateBarHeight, width: width, height: keyboardHeight)
        candidateBar.frame = CGRect(x: 0, y: 0, width: width, height: candidateBarHeight)
        let contentHeight = view.bounds.height - candidateBarHeight
        let contentFrame = CGRect(x: 0, y: candidateBarHeight, width: width, height: contentHeight)
        fullKeyboard.frame = contentFrame
        symbolKeyboard.frame = contentFrame
        candidateList.frame = contentFrame
        nineGridPlaceholder.frame = contentFrame
        if let label = nineGridPlaceholder.viewWithTag(101) {
            label.frame = CGRect(x: 16, y: contentHeight / 2 - 44, width: width - 32, height: 24)
        }
        if let button = nineGridPlaceholder.viewWithTag(102) {
            button.frame = CGRect(x: width / 2 - 70, y: contentHeight / 2 - 8, width: 140, height: 36)
        }
    }

    private func applyVisibility() {
        let ready = engine.isReady
        statusLabel.isHidden = ready
        candidateBar.isHidden = !ready
        let showNine = ready && layoutMode == .nineGrid
        nineGridPlaceholder.isHidden = !showNine
        candidateList.isHidden = !ready || showNine || !candidatesExpanded
        fullKeyboard.isHidden = !ready || showNine || candidatesExpanded || page != .letters
        symbolKeyboard.isHidden = !ready || showNine || candidatesExpanded || page != .symbols
    }

    // MARK: 引擎启动

    private func startEngine() {
        engine.onReady = { [weak self] in
            guard let self else { return }
            self.fullKeyboard.setAsciiMode(self.engine.isAsciiMode)
            self.applyVisibility()
            self.refresh()
        }
        // SharedData：扩展 bundle 根目录（CI 的 postBuildScript 整目录拷入 appex）。
        let sharedData = Bundle.main.url(forResource: "SharedData", withExtension: nil)
            ?? Bundle.main.bundleURL.appendingPathComponent("SharedData", isDirectory: true)
        // userdb：扩展自身沙盒的 Application Support/RimeUser（PLAN 4.2，
        // 不用 App Group——免费自签下 group 标识可能被签名工具改写）。
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let userData = support.appendingPathComponent("RimeUser", isDirectory: true)
        do {
            try engine.start(sharedDataDir: sharedData, userDataDir: userData)
        } catch {
            statusLabel.text = "引擎启动失败：\(error.localizedDescription)"
        }
    }

    // MARK: 状态刷新（所有引擎操作后统一走这里）

    private func refresh() {
        guard engine.isReady, layoutMode == .full26 else { return }
        if let commit = engine.drainCommitText() {
            textDocumentProxy.insertText(commit)
        }
        let menu = engine.menu
        if !menu.isLastPage, menu.candidates.count > 0 {
            cachedPageSize = menu.candidates.count
        }
        let all = engine.allCandidates()
        let highlighted = globalHighlightedIndex(menu: menu, totalCount: all.count)
        let preedit = engine.composition.preedit
        candidateBar.update(preedit: preedit, candidates: all, highlightedGlobalIndex: highlighted)
        if candidatesExpanded {
            candidateList.update(preedit: preedit, candidates: all, highlightedGlobalIndex: highlighted)
            if all.isEmpty { setCandidatesExpanded(false) }
        }
    }

    /// 当前页在全量候选中的起始下标：末页时由总数倒推，其余页由页号 × 页大小推。
    private func pageStartIndex(menu: RimeMenu, totalCount: Int) -> Int {
        if menu.isLastPage {
            return max(totalCount - menu.candidates.count, 0)
        }
        return menu.pageNumber * menu.candidates.count
    }

    private func globalHighlightedIndex(menu: RimeMenu, totalCount: Int) -> Int? {
        guard let local = menu.highlightedIndex else { return nil }
        return pageStartIndex(menu: menu, totalCount: totalCount) + local
    }

    // MARK: 候选点选（全量下标 → 翻页 + 页内下标）

    private func selectGlobalCandidate(_ globalIndex: Int) {
        guard engine.isReady else { return }
        let total = engine.allCandidates().count
        guard globalIndex >= 0, globalIndex < total else { return }
        let menu = engine.menu
        let pageSize = max(cachedPageSize ?? menu.candidates.count, 1)
        let targetPage = globalIndex / pageSize
        var guardCounter = 0
        while engine.menu.pageNumber < targetPage, guardCounter < 32 {
            engine.nextPage(); guardCounter += 1
        }
        while engine.menu.pageNumber > targetPage, guardCounter < 32 {
            engine.previousPage(); guardCounter += 1
        }
        engine.selectCandidate(at: globalIndex - targetPage * pageSize)
        refresh()
    }

    private func setCandidatesExpanded(_ expanded: Bool) {
        candidatesExpanded = expanded
        heightConstraint?.constant = candidateBarHeight + (expanded ? expandedListHeight : keyboardHeight)
        applyVisibility()
        if expanded { refresh() }
    }

    // MARK: 按键语义

    private var hasComposition: Bool {
        engine.isReady && !engine.composition.input.isEmpty
    }

    private func handleKeyAction(_ action: KeyAction) {
        UIDevice.current.playInputClick()
        guard engine.isReady else { return }
        switch action {
        case .letter(let ch):
            let scalar = (engine.isAsciiMode && capsOn) ? ch.uppercased() : String(ch)
            for s in scalar.unicodeScalars {
                engine.processKey(code: s.value, modifiers: 0)
            }
            refresh()
        case .backspace:
            handleBackspace()
        case .space:
            if hasComposition {
                engine.processKey(code: RimeKey.space, modifiers: 0)
                refresh()
            } else {
                textDocumentProxy.insertText(" ")
            }
        case .enter:
            if hasComposition {
                engine.processKey(code: RimeKey.return, modifiers: 0)
                refresh()
            } else {
                textDocumentProxy.insertText("\n")
            }
        case .shift:
            // 大小写仅在英文（ascii）模式有意义；中文模式下不响应，避免把
            // 大写字母喂进拼音会话产生怪切分。
            if engine.isAsciiMode {
                capsOn.toggle()
                fullKeyboard.setCaps(capsOn)
            }
        case .toggleAscii:
            engine.isAsciiMode.toggle()
            capsOn = false
            fullKeyboard.setCaps(false)
            fullKeyboard.setAsciiMode(engine.isAsciiMode)
            refresh()
        case .switchToSymbols:
            page = .symbols
            applyVisibility()
        case .switchToNineGrid:
            switchLayoutMode(.nineGrid)
        case .nextKeyboard:
            // 正常路径由 globeTarget/globeAction 直达 handleInputModeList，
            // 这里只是兜底（目标未接线时）。
            advanceToNextInputMode()
        }
    }

    private func handleBackspace() {
        if hasComposition {
            engine.processKey(code: RimeKey.backspace, modifiers: 0)
            refresh()
        } else {
            textDocumentProxy.deleteBackward()
        }
    }

    private func handleSymbol(_ symbol: String) {
        UIDevice.current.playInputClick()
        guard engine.isReady else { return }
        // 先把未上屏的组合串以首选提交，再直插符号字面量（见 SymbolLayout 注释）。
        if hasComposition {
            engine.commitCurrentComposition()
            if let commit = engine.drainCommitText() {
                textDocumentProxy.insertText(commit)
            }
        }
        textDocumentProxy.insertText(symbol)
        refresh()
    }

    private func handleSymbolPanelAction(_ action: SymbolPanelAction) {
        UIDevice.current.playInputClick()
        switch action {
        case .backToLetters:
            page = .letters
            applyVisibility()
        case .space:
            textDocumentProxy.insertText(" ")
        case .backspace:
            handleBackspace()
        case .enter:
            if hasComposition {
                engine.processKey(code: RimeKey.return, modifiers: 0)
                refresh()
            } else {
                textDocumentProxy.insertText("\n")
            }
        case .nextKeyboard:
            advanceToNextInputMode()
        }
    }

    // MARK: 布局切换（持久化到 SettingsBridge.defaultLayout）

    private func restoreLayoutMode() {
        let saved = SettingsBridge.defaults.string(forKey: SettingsKey.defaultLayout)
        layoutMode = (saved == "nineGrid") ? .nineGrid : .full26
    }

    private func switchLayoutMode(_ mode: LayoutMode) {
        layoutMode = mode
        SettingsBridge.defaults.set(mode == .nineGrid ? "nineGrid" : "full26",
                                    forKey: SettingsKey.defaultLayout)
        if candidatesExpanded { setCandidatesExpanded(false) }
        applyVisibility()
    }

    @objc private func switchToFull26() {
        switchLayoutMode(.full26)
        refresh()
    }

    // MARK: 回车键文案

    private func updateReturnKeyTitle() {
        let title: String
        switch textDocumentProxy.returnKeyType {
        case .search: title = "搜索"
        case .send: title = "发送"
        case .go: title = "前往"
        case .done: title = "完成"
        case .next: title = "下一项"
        case .join: title = "加入"
        default: title = "回车"
        }
        fullKeyboard.setReturnKeyTitle(title)
        symbolKeyboard.setReturnKeyTitle(title)
    }
}

extension KeyboardViewController: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
