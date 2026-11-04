import UIKit

/// 键盘扩展入口：装配 Rime 引擎、候选栏与三块面板（26 键 / 九宫格 / 符号），
/// 解释按键语义。
///
/// 数据流：按键 → 本类翻译为引擎调用（processKey / 选词 / 翻页 / setInput）
/// → refresh() 统一回收上屏文本并以引擎快照刷新候选栏。候选栏/展开列表给出
/// 的是全量下标，本类负责换算成引擎的「翻到目标页 + 选当前页下标」。
///
/// 九宫格（实现轮 2，PLAN 3.2）：数字串由 T9Session 在应用层切分为拼音后
/// 以 setInput 喂引擎；候选仍取自引擎。候选部分上屏后引擎输入缩短，
/// syncT9Consumption() 把少掉的字母数换算成音节数、从数字串头部扣除。
///
/// 苹果式交互（实现轮 2）：Shift 一次性大写/双击锁定、双击空格出句点、
/// 回车键情境文案+强调色、退格长按加速（≥2.5s 整词删）、空格触控板移
/// 光标、宿主侧变化（切输入框/移光标）时自动提交未上屏组合串。所有经
/// proxy 的文本改动统一走 proxyInsert/proxyDelete 并登记「自家编辑预期」，
/// 供 textDidChange/selectionDidChange 区分回声与宿主变化（尽力而为，
/// 误判边界见 PLAN 实现轮 2 追记）。
///
/// 布局状态：layoutMode（26 键 / 九宫格）持久化在 SettingsBridge 的
/// defaultLayout；page（字母/符号）为会话内临时状态，不落盘；从符号页
/// 返回时回到进入前的布局。
///
/// 首屏不阻塞（PLAN 9.5）：viewDidLoad / viewWillAppear 路径上没有任何等
/// 引擎的同步调用；引擎未就绪时先画按键骨架、候选栏留空，状态文案以半
/// 透明遮罩浮于键区上方，就绪回调后再刷新。T9Session 的构建（读
/// syllables.txt + 生成映射）推迟到首次切入九宫格时懒加载，不进首屏路径。
final class KeyboardViewController: UIInputViewController {
    private enum LayoutMode { case full26, nineGrid }
    private enum Page { case letters, symbols }
    private enum ShiftState { case off, oneShot, locked }

    private let engine: RimeEngine = LibrimeKitRimeEngine()

    private let statusLabel = UILabel()
    private let candidateBar = CandidateBarView()
    private let candidateList = CandidateListView()
    private let fullKeyboard = FullKeyboardView()
    private let symbolKeyboard = SymbolKeyboardView()
    private let nineGrid = NineGridView()
    private var heightConstraint: NSLayoutConstraint?

    private var layoutMode: LayoutMode = .full26
    private var page: Page = .letters
    private var candidatesExpanded = false
    private var shiftState: ShiftState = .off
    private var lastShiftTapTime: TimeInterval = 0
    /// 引擎每页候选数：从引擎返回的满页推得并缓存（展开点选换算页码用）。
    private var cachedPageSize: Int?

    // T9 状态（懒构建，见类注释）。
    private var t9: T9Session?
    /// 上次与引擎同步过的 T9 切分（消费同步时与引擎现输入比对用）。
    private var t9SyncedSegmentation: [String] = []

    // 双击空格 / 触控板 / 宿主变化检测。
    private var lastSpaceInsertTime: TimeInterval = 0
    private var trackpadConsumedSteps = 0
    private var selfEditExpectation: String?
    private var hasSelfEditExpectation = false
    private var selfEditSelectionEcho = false

    private let candidateBarHeight: CGFloat = 40
    private let keyboardHeight: CGFloat = 236
    private let expandedListHeight: CGFloat = 308

    // MARK: 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.keyboardBackgroundColor
        view.isMultipleTouchEnabled = true

        buildSubviews()
        restoreLayoutMode()
        startEngine()
    }

    /// 键盘底色（苹果观感：浅 #D1D3D9 / 深 #242426）。
    private static let keyboardBackgroundColor = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.141, alpha: 1)
            : UIColor(red: 0.820, green: 0.827, blue: 0.851, alpha: 1)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let globe = needsInputModeSwitchKey
        fullKeyboard.showsGlobeButton = globe
        symbolKeyboard.showsGlobeButton = globe
        nineGrid.showsGlobeButton = globe
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
        handlePossibleHostChange()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        handlePossibleHostChange()
    }

    // MARK: 装配

    private func buildSubviews() {
        statusLabel.text = "正在准备词库…"
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 15)
        // 遮罩式状态文案：半透明底色让底下的按键骨架隐约可见（明示「键盘已
        // 画出、引擎未就绪」），且不拦截触摸——按键在就绪前由 isReady 守卫
        // 统一失效，不靠遮罩挡（PLAN 9.5）。
        statusLabel.backgroundColor = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.141, alpha: 0.88)
                : UIColor(red: 0.820, green: 0.827, blue: 0.851, alpha: 0.88)
        }
        statusLabel.isUserInteractionEnabled = false
        view.addSubview(statusLabel)

        candidateBar.onSelectCandidate = { [weak self] in self?.selectGlobalCandidate($0) }
        candidateBar.onExpand = { [weak self] in self?.setCandidatesExpanded(true) }
        view.addSubview(candidateBar)

        candidateList.onSelectCandidate = { [weak self] in self?.selectGlobalCandidate($0) }
        candidateList.onClose = { [weak self] in self?.setCandidatesExpanded(false) }
        candidateList.isHidden = true
        view.addSubview(candidateList)

        fullKeyboard.onAction = { [weak self] in self?.handleKeyAction($0) }
        fullKeyboard.onVariantInput = { [weak self] in self?.handleVariantInput($0) }
        fullKeyboard.onSpaceTrackpad = { [weak self] in self?.handleSpaceTrackpad($0, dx: $1) }
        fullKeyboard.onBackspaceHold = { [weak self] in self?.handleBackspace(heldFor: $0) }
        fullKeyboard.globeTarget = self
        fullKeyboard.globeAction = #selector(handleInputModeList(from:with:))
        view.addSubview(fullKeyboard)

        symbolKeyboard.onSymbol = { [weak self] in self?.handleSymbol($0) }
        symbolKeyboard.onAction = { [weak self] in self?.handleSymbolPanelAction($0) }
        symbolKeyboard.onBackspaceHold = { [weak self] in self?.handleBackspace(heldFor: $0) }
        symbolKeyboard.globeTarget = self
        symbolKeyboard.globeAction = #selector(handleInputModeList(from:with:))
        symbolKeyboard.isHidden = true
        view.addSubview(symbolKeyboard)

        nineGrid.onAction = { [weak self] in self?.handleNineGridAction($0) }
        nineGrid.onPinSyllables = { [weak self] in self?.handlePinSyllables($0) }
        nineGrid.onSpaceTrackpad = { [weak self] in self?.handleSpaceTrackpad($0, dx: $1) }
        nineGrid.globeTarget = self
        nineGrid.globeAction = #selector(handleInputModeList(from:with:))
        nineGrid.isHidden = true
        view.addSubview(nineGrid)

        heightConstraint = view.heightAnchor.constraint(equalToConstant: candidateBarHeight + keyboardHeight)
        heightConstraint?.priority = UILayoutPriority(999)
        heightConstraint?.isActive = true
        applyVisibility()
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
        nineGrid.frame = contentFrame
    }

    private func applyVisibility() {
        // 首屏不阻塞：可见性只由布局/页/展开状态决定，不等引擎就绪（PLAN 9.5）。
        statusLabel.isHidden = engine.isReady
        view.bringSubviewToFront(statusLabel)
        candidateBar.isHidden = false
        candidateList.isHidden = !candidatesExpanded
        symbolKeyboard.isHidden = candidatesExpanded || page != .symbols
        fullKeyboard.isHidden = candidatesExpanded || page != .letters || layoutMode != .full26
        nineGrid.isHidden = candidatesExpanded || page != .letters || layoutMode != .nineGrid
    }

    // MARK: 引擎启动

    private func startEngine() {
        engine.onReady = { [weak self] in
            guard let self else { return }
            self.fullKeyboard.setAsciiMode(self.engine.isAsciiMode)
            self.nineGrid.setAsciiMode(self.engine.isAsciiMode)
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

    // MARK: proxy 改动统一入口（登记自家编辑预期，供宿主变化检测）

    private func proxyInsert(_ text: String) {
        textDocumentProxy.insertText(text)
        noteSelfEdit()
    }

    private func proxyDelete(_ count: Int = 1) {
        for _ in 0..<max(count, 1) { textDocumentProxy.deleteBackward() }
        noteSelfEdit()
    }

    private func noteSelfEdit() {
        selfEditExpectation = textDocumentProxy.documentContextBeforeInput
        hasSelfEditExpectation = true
        selfEditSelectionEcho = true
    }

    /// 宿主侧变化检测：textDidChange/selectionDidChange 里，若变化不是自家
    /// 编辑的回声且有未上屏组合串，则先提交（苹果行为）。判定为尽力而为：
    /// 自家编辑后登记的光标前文本与当前一致 → 回声；仅剩选择回声标记 →
    /// 吞掉一次（避免部分上屏后残余组合串被误提交）。
    private func handlePossibleHostChange() {
        guard engine.isReady else { return }
        guard hasComposition else {
            hasSelfEditExpectation = false
            selfEditSelectionEcho = false
            return
        }
        if hasSelfEditExpectation {
            hasSelfEditExpectation = false
            if selfEditExpectation == textDocumentProxy.documentContextBeforeInput {
                return
            }
            selfEditSelectionEcho = false
        } else if selfEditSelectionEcho {
            selfEditSelectionEcho = false
            return
        }
        commitCompositionIfAny()
        refresh()
    }

    // MARK: 状态刷新（所有引擎操作后统一走这里）

    private func refresh() {
        guard engine.isReady else { return }
        if let commit = engine.drainCommitText() {
            proxyInsert(commit)
        }
        if layoutMode == .nineGrid, page == .letters {
            syncT9Consumption()
        }
        updateCandidateUI()
        if layoutMode == .nineGrid {
            nineGrid.updateSyllableStrip(entries: t9?.stripOptions() ?? [])
        }
        if !hasComposition {
            hasSelfEditExpectation = false
            selfEditSelectionEcho = false
        }
    }

    private func updateCandidateUI() {
        let menu = engine.menu
        if !menu.isLastPage, menu.candidates.count > 0 {
            cachedPageSize = menu.candidates.count
        }
        let all = engine.allCandidates()
        let highlighted = globalHighlightedIndex(menu: menu, totalCount: all.count)
        let preedit = displayPreedit(enginePreedit: engine.composition.preedit)
        candidateBar.update(preedit: preedit, candidates: all, highlightedGlobalIndex: highlighted)
        if candidatesExpanded {
            candidateList.update(preedit: preedit, candidates: all, highlightedGlobalIndex: highlighted)
            if all.isEmpty { setCandidatesExpanded(false) }
        }
    }

    /// 候选栏预编辑文本：九宫格用前端渲染（切分拼音 + 数字串，PLAN 3.2），
    /// 其余情况用引擎 preedit。
    private func displayPreedit(enginePreedit: String) -> String {
        if layoutMode == .nineGrid, page == .letters, let t9, t9.isActive {
            var segText = t9.segmentation.joined(separator: " ")
            if !t9.unsegmentedTail.isEmpty {
                segText += (segText.isEmpty ? "" : " ") + t9.unsegmentedTail
            }
            return segText.isEmpty ? t9.digits : "\(segText)（\(t9.digits)）"
        }
        return enginePreedit
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

    // MARK: 共享按键语义（26 键 / 九宫格 / 符号页共用）

    private var hasComposition: Bool {
        engine.isReady && !engine.composition.input.isEmpty
    }

    /// 把未上屏组合串以当前高亮候选提交并取走文本（符号/变体直插、
    /// 宿主变化、触控板激活前的统一前置动作）。九宫格下连带清掉数字串状态。
    private func commitCompositionIfAny() {
        guard hasComposition else { return }
        engine.commitCurrentComposition()
        if let commit = engine.drainCommitText() {
            proxyInsert(commit)
        }
        if layoutMode == .nineGrid {
            t9?.reset()
            t9SyncedSegmentation = []
        }
    }

    private func handleSpace() {
        // 九宫格下只有不可切分的数字串时，空格视为放弃该串并插入空格。
        if layoutMode == .nineGrid, page == .letters, let t9, t9.isActive, t9.feedString.isEmpty {
            t9.reset()
            t9SyncedSegmentation = []
            engine.clearComposition()
            insertSpaceWithDoubleTapLogic()
            refresh()
            return
        }
        if hasComposition {
            engine.processKey(code: RimeKey.space, modifiers: 0)
            refresh()
        } else {
            insertSpaceWithDoubleTapLogic()
        }
    }

    /// 无组合串时的空格：0.3s 内连按两次 → 英文出「. 」、中文出「。」
    /// （把刚插入的那个空格替换掉）。判定只挂在「上屏后的空格插入」上，
    /// 有组合串时空格恒为选词，不会误入此路。
    private func insertSpaceWithDoubleTapLogic() {
        let now = Date().timeIntervalSince1970
        if now - lastSpaceInsertTime < 0.3,
           textDocumentProxy.documentContextBeforeInput?.hasSuffix(" ") == true {
            proxyDelete(1)
            proxyInsert(engine.isAsciiMode ? ". " : "。")
            lastSpaceInsertTime = 0
            return
        }
        proxyInsert(" ")
        lastSpaceInsertTime = now
    }

    private func handleEnter() {
        if hasComposition {
            // 苹果行为：回车先把组合串以高亮候选上屏，而不是透传原始拼音。
            engine.commitCurrentComposition()
            if let commit = engine.drainCommitText() {
                proxyInsert(commit)
            } else if hasComposition {
                // 兜底：commitComposition 未产生提交时退回引擎回车键语义。
                engine.processKey(code: RimeKey.return, modifiers: 0)
                if let commit = engine.drainCommitText() { proxyInsert(commit) }
            }
            refresh()
        } else {
            proxyInsert("\n")
        }
    }

    private func handleBackspace(heldFor: TimeInterval? = nil) {
        // 九宫格：只要数字串还活着，退格恒为「弹一位数字重算」（与当前页无关）。
        if layoutMode == .nineGrid, let t9, t9.isActive {
            t9.removeLastDigit()
            if t9.isActive {
                syncT9Feed()
            } else {
                engine.clearComposition()
                t9SyncedSegmentation = []
            }
            refresh()
            return
        }
        if hasComposition {
            engine.processKey(code: RimeKey.backspace, modifiers: 0)
            refresh()
        } else if let heldFor, heldFor >= 2.5 {
            deleteWordBackward()
        } else {
            proxyDelete(1)
        }
    }

    /// 整词删除：删掉光标前的一个词（连同其前的空白），边界为
    /// 空格/换行与中英文标点；对照 documentContextBeforeInput 计算，
    /// 拿不到上下文时退化为删一个字。
    private func deleteWordBackward() {
        guard let context = textDocumentProxy.documentContextBeforeInput, !context.isEmpty else {
            proxyDelete(1)
            return
        }
        let separators: Set<Character> = [" ", "\n", "\t",
            "，", "。", "！", "？", "、", "；", "：", "·", "—", "…",
            "（", "）", "「", "」", "“", "”",
            ",", ".", "!", "?", ";", ":", "(", ")", "\"", "'"]
        let chars = Array(context)
        var count = 0
        var i = chars.count - 1
        while i >= 0, chars[i] == " " || chars[i] == "\n" || chars[i] == "\t" {
            count += 1; i -= 1
        }
        while i >= 0, !separators.contains(chars[i]) {
            count += 1; i -= 1
        }
        proxyDelete(max(count, 1))
    }

    private func handleShift() {
        // 大小写仅在英文（ascii）模式有意义；中文模式下不响应，避免把
        // 大写字母喂进拼音会话产生怪切分。
        guard engine.isAsciiMode else { return }
        let now = Date().timeIntervalSince1970
        switch shiftState {
        case .locked:
            shiftState = .off
        case .oneShot:
            // 一次性大写期间快速再击 = 双击 → 锁定；慢速再击 = 取消。
            shiftState = (now - lastShiftTapTime < 0.35) ? .locked : .off
        case .off:
            shiftState = .oneShot
        }
        lastShiftTapTime = now
        fullKeyboard.setShiftState(oneShot: shiftState == .oneShot,
                                   locked: shiftState == .locked)
    }

    private func toggleAsciiMode() {
        engine.isAsciiMode.toggle()
        shiftState = .off
        lastShiftTapTime = 0
        fullKeyboard.setShiftState(oneShot: false, locked: false)
        fullKeyboard.setAsciiMode(engine.isAsciiMode)
        nineGrid.setAsciiMode(engine.isAsciiMode)
        if engine.isAsciiMode, layoutMode == .nineGrid {
            // 英文模式下九宫格数字键直插数字，T9 状态先清掉防残留。
            t9?.reset()
            t9SyncedSegmentation = []
            engine.clearComposition()
        }
        refresh()
    }

    /// 长按变体输入（声调字母/数字）：与符号页同一语义——先提交组合串，
    /// 再把字面量直插文档（这类字符本就不是拼音输入的一部分）。
    private func handleVariantInput(_ text: String) {
        UIDevice.current.playInputClick()
        guard engine.isReady else { return }
        commitCompositionIfAny()
        proxyInsert(text)
        refresh()
    }

    /// 空格触控板：长按激活后按水平位移移光标（约 20pt 一格）。
    /// 激活时先提交未上屏组合串（苹果行为：先上屏再移光标）。
    private func handleSpaceTrackpad(_ phase: SpaceTrackpadPhase, dx: CGFloat) {
        switch phase {
        case .began:
            commitCompositionIfAny()
            trackpadConsumedSteps = 0
            refresh()
        case .moved:
            let steps = Int(dx / 20)
            let delta = steps - trackpadConsumedSteps
            if delta != 0 {
                textDocumentProxy.adjustTextPosition(byCharacterOffset: delta)
                trackpadConsumedSteps = steps
                noteSelfEdit()
            }
        case .ended:
            trackpadConsumedSteps = 0
        }
    }

    // MARK: 26 键按键语义

    private func handleKeyAction(_ action: KeyAction) {
        UIDevice.current.playInputClick()
        guard engine.isReady else { return }
        switch action {
        case .letter(let ch):
            let upper = engine.isAsciiMode && shiftState != .off
            let scalar = upper ? ch.uppercased() : String(ch)
            for s in scalar.unicodeScalars {
                engine.processKey(code: s.value, modifiers: 0)
            }
            if engine.isAsciiMode, shiftState == .oneShot {
                shiftState = .off
                fullKeyboard.setShiftState(oneShot: false, locked: false)
            }
            refresh()
        case .backspace:
            handleBackspace()
        case .space:
            handleSpace()
        case .enter:
            handleEnter()
        case .shift:
            handleShift()
        case .toggleAscii:
            toggleAsciiMode()
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

    // MARK: 九宫格按键语义

    private func ensureT9() -> T9Session? {
        if let t9 { return t9 }
        guard let mapper = T9Mapper(bundle: .main) else { return nil }
        let session = T9Session(mapper: mapper)
        t9 = session
        return session
    }

    private func handleNineGridAction(_ action: NineGridKeyAction) {
        UIDevice.current.playInputClick()
        guard engine.isReady else { return }
        switch action {
        case .digit(let d):
            handleT9Digit(d)
        case .symbolsPage:
            page = .symbols
            applyVisibility()
        case .backspace:
            handleBackspace()
        case .spaceOrCommit:
            handleSpace()
        case .enter:
            handleEnter()
        case .toggleAscii:
            toggleAsciiMode()
        case .switchToFull26:
            switchLayoutMode(.full26)
        case .nextKeyboard:
            advanceToNextInputMode()
        }
    }

    private func handleT9Digit(_ d: Int) {
        if engine.isAsciiMode {
            // 英文模式：数字直插（多击出字母的 T9 英文输入本轮不做）。
            proxyInsert(String(d))
            return
        }
        guard let t9 = ensureT9() else { return }
        if d == 1 {
            if t9.isActive {
                t9.insertSeparator()
                syncT9Feed()
                refresh()
            } else {
                // 无数字串时 1 键即符号入口（键面副标 ，。？！ 的语义）。
                page = .symbols
                applyVisibility()
            }
            return
        }
        t9.appendDigit(d)
        syncT9Feed()
        refresh()
    }

    private func handlePinSyllables(_ syllables: [String]) {
        UIDevice.current.playInputClick()
        guard engine.isReady, let t9 else { return }
        t9.pin(syllables)
        syncT9Feed()
        refresh()
    }

    /// 让引擎输入与 T9 当前切分保持一致，并更新同步快照。
    private func syncT9Feed() {
        guard let t9 else { return }
        if engine.composition.input != t9.feedString {
            engine.setInput(t9.feedString)
        }
        t9SyncedSegmentation = t9.segmentation
    }

    /// 候选上屏（点选/空格选词）后引擎输入缩短：把比同步快照少掉的字母数
    /// 换算成音节数，从数字串头部扣除。不用候选 comment 反推——rime_ice
    /// 译文候选的 comment 常为空或不稳定，输入字母差是更硬的信号；
    /// 字母差对不齐音节边界时不动数字串，等后续 syncT9Feed 校正引擎侧。
    private func syncT9Consumption() {
        guard let t9, t9.isActive else {
            if t9 != nil { t9SyncedSegmentation = [] }
            return
        }
        let engineLetters = engine.composition.input.filter { $0 != "'" }.count
        let syncedLetters = t9SyncedSegmentation.joined().count
        guard engineLetters < syncedLetters else { return }
        let consumedLetters = syncedLetters - engineLetters
        var accumulated = 0
        var syllableCount = 0
        for syllable in t9SyncedSegmentation {
            if accumulated >= consumedLetters { break }
            accumulated += syllable.count
            syllableCount += 1
        }
        if accumulated == consumedLetters, syllableCount > 0 {
            t9.consumeSyllables(syllableCount)
        } else if engineLetters == 0 {
            t9.consumeSyllables(t9SyncedSegmentation.count)
        }
        syncT9Feed()
    }

    // MARK: 符号页语义

    private func handleSymbol(_ symbol: String) {
        UIDevice.current.playInputClick()
        guard engine.isReady else { return }
        // 先把未上屏的组合串以首选提交，再直插符号字面量（见 SymbolLayout 注释）。
        commitCompositionIfAny()
        proxyInsert(symbol)
        refresh()
    }

    private func handleSymbolPanelAction(_ action: SymbolPanelAction) {
        UIDevice.current.playInputClick()
        switch action {
        case .backToLetters:
            page = .letters
            applyVisibility()
        case .space:
            insertSpaceWithDoubleTapLogic()
        case .backspace:
            handleBackspace()
        case .enter:
            handleEnter()
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
        if mode != layoutMode {
            if mode == .nineGrid {
                // 以引擎当前输入（字母）重建 T9 数字串，已输入内容不丢。
                if let session = ensureT9() {
                    session.loadFromPinyin(engine.isReady ? engine.composition.input : "")
                    syncT9Feed()
                }
            } else {
                // 回 26 键：引擎里仍是同一字母会话，直接沿用；T9 状态作废。
                t9?.reset()
                t9SyncedSegmentation = []
            }
            layoutMode = mode
            SettingsBridge.defaults.set(mode == .nineGrid ? "nineGrid" : "full26",
                                        forKey: SettingsKey.defaultLayout)
        }
        if candidatesExpanded { setCandidatesExpanded(false) }
        page = .letters
        applyVisibility()
        refresh()
    }

    // MARK: 回车键文案（情境化：文案 + .search/.send 强调色）

    private func updateReturnKeyTitle() {
        let title: String
        var accent = false
        switch textDocumentProxy.returnKeyType {
        case .search: title = "搜索"; accent = true
        case .send: title = "发送"; accent = true
        case .go: title = "前往"
        case .done: title = "完成"
        case .next: title = "下一项"
        case .join: title = "加入"
        default: title = "回车"
        }
        fullKeyboard.setReturnKeyTitle(title)
        fullKeyboard.setReturnKeyAccent(accent)
        symbolKeyboard.setReturnKeyTitle(title)
        symbolKeyboard.setReturnKeyAccent(accent)
        nineGrid.setReturnKeyTitle(title)
        nineGrid.setReturnKeyAccent(accent)
    }
}

extension KeyboardViewController: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
