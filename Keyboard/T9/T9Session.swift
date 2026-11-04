import Foundation

/// 九宫格输入状态机（PLAN 3.2）：维护数字串、锁定音节与分词断点，
/// 每次变更后重算最优切分；喂给引擎的拼音串只来自本类的 feedString，
/// 引擎永远只看到字母（全拼会话），删除/锁定/消费同步都在本层闭环。
///
/// 切分规则：在「覆盖位数最多」优先的前提下取音节数最少的切分；
/// 尾部数字暂时无法切分时（还没打完），只喂已切分的前缀，尾巴留在
/// unsegmentedTail 里待后续按键补全。断点（分词键）约束任何音节不得跨越。
final class T9Session {
    let mapper: T9Mapper

    private(set) var digits: String = ""
    private(set) var pinned: [String] = []
    /// 强制断点集合：元素为绝对数字偏移（在该偏移之后必须断开）。
    private var breaks: Set<Int> = []

    /// 当前切分（pinned + 尾部最优切分），只覆盖 segmentedDigitCount 位数字。
    private(set) var segmentation: [String] = []
    private(set) var segmentedDigitCount: Int = 0

    private lazy var maxSyllableDigits: Int =
        mapper.syllableToDigits.values.map { $0.count }.max() ?? 6

    init(mapper: T9Mapper) {
        self.mapper = mapper
    }

    var isActive: Bool { !digits.isEmpty }
    /// 尚未切分出去的尾部数字（用户还没打完的部分）。
    var unsegmentedTail: String { String(digits.dropFirst(segmentedDigitCount)) }
    /// 喂引擎的输入串（音节以 ' 连接），如 "ni'hao"；无切分时为空串。
    var feedString: String { segmentation.joined(separator: "'") }

    private var pinnedDigitCount: Int {
        pinned.compactMap { mapper.syllableToDigits[$0] }.joined().count
    }

    // MARK: 编辑

    func reset() {
        digits = ""
        pinned = []
        breaks = []
        recompute()
    }

    func appendDigit(_ d: Int) {
        guard (2...9).contains(d) else { return }
        digits.append(Character(String(d)))
        recompute()
    }

    /// 分词键：在当前数字串末尾打一个强制断点。断点不在现有切分边界上时
    /// 先记下，后续数字补齐使边界到达此处时自然生效（DP 约束一直在）。
    func insertSeparator() {
        guard !digits.isEmpty else { return }
        breaks.insert(digits.count)
        recompute()
    }

    func removeLastDigit() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
        while pinnedDigitCount > digits.count, !pinned.isEmpty {
            pinned.removeLast()
        }
        breaks = breaks.filter { $0 <= digits.count }
        recompute()
    }

    /// 音节条点选锁定：syllables 必须是紧接现有 pinned 之后、与尾部数字
    /// 对齐的音节序列（音节条的选项正是这样生成的），不对齐则忽略。
    func pin(_ syllables: [String]) {
        let tailDigits = String(digits.dropFirst(pinnedDigitCount))
        let pinDigits = syllables.compactMap { mapper.syllableToDigits[$0] }.joined()
        guard !pinDigits.isEmpty, tailDigits.hasPrefix(pinDigits) else { return }
        pinned += syllables
        recompute()
    }

    /// 引擎部分上屏后的同步：消耗切分头部 count 个音节所对应的数字，
    /// 断点随之平移（PLAN 3.2 的已消耗位数反推在本层以音节为单位执行，
    /// 调用方负责把引擎输入的字母差换算成音节数）。
    func consumeSyllables(_ count: Int) {
        guard count > 0 else { return }
        let consumed = Array(segmentation.prefix(count))
        let digitCount = consumed.compactMap { mapper.syllableToDigits[$0] }.joined().count
        guard digitCount > 0 else { return }
        digits = String(digits.dropFirst(min(digitCount, digits.count)))
        if count <= pinned.count {
            pinned = Array(pinned.dropFirst(count))
        } else {
            pinned = []
        }
        breaks = Set(breaks.compactMap { $0 > digitCount ? $0 - digitCount : nil })
        recompute()
    }

    /// 从全拼字母串重建（26 键切到九宫格时保输入不丢）：字母逐个映射回
    /// 数字后重新切分。切分结果可能与原分词不同（DP 取最优），属预期。
    func loadFromPinyin(_ pinyin: String) {
        reset()
        for ch in pinyin where ch != "'" {
            if let d = T9Mapper.letterToDigit[ch] {
                digits.append(d)
            }
        }
        recompute()
    }

    // MARK: 音节条

    /// 音节条选项：可作为下一段开头的单音节（按数字长度降序、长者优先）在前，
    /// 整串候选切分（多音节整条锁定）在后；总量截断到 10 条。
    func stripOptions() -> [(label: String, syllables: [String])] {
        let tail = String(digits.dropFirst(pinnedDigitCount))
        guard !tail.isEmpty else { return [] }
        var options: [(label: String, syllables: [String])] = []
        var seen = Set<String>()
        for len in stride(from: min(maxSyllableDigits, tail.count), through: 1, by: -1) {
            let piece = String(tail.prefix(len))
            guard let sylls = mapper.digitsToSyllables[piece] else { continue }
            let rest = String(tail.dropFirst(len))
            for syllable in sylls {
                // 其后剩余要么用完、要么至少能起个头（可切分前缀或音节前缀），
                // 否则这个选项是死路，不上条。
                guard rest.isEmpty
                        || bestSegmentation(of: rest, breaks: []).covered > 0
                        || mapper.isDigitPrefix(rest) else { continue }
                if seen.insert(syllable).inserted {
                    options.append((label: syllable, syllables: [syllable]))
                }
            }
        }
        for seg in segmentAllTail(limit: 4) where seg.count > 1 {
            let label = seg.joined(separator: " ")
            if seen.insert(label).inserted {
                options.append((label: label, syllables: seg))
            }
        }
        return Array(options.prefix(10))
    }

    // MARK: 切分核心（DP，尊重断点）

    private var tailBreaks: Set<Int> {
        let base = pinnedDigitCount
        return Set(breaks.compactMap { $0 > base ? $0 - base : nil })
    }

    private func recompute() {
        let tail = String(digits.dropFirst(pinnedDigitCount))
        let result = bestSegmentation(of: tail, breaks: tailBreaks)
        segmentation = pinned + result.segments
        segmentedDigitCount = pinnedDigitCount + result.covered
    }

    /// 对数字串求最优切分：覆盖位数最多优先，其次音节数最少。
    /// 断点约束：任何音节的跨度 (start, end) 不得有断点 b 落入 start < b < end。
    private func bestSegmentation(of tail: String, breaks: Set<Int>)
        -> (segments: [String], covered: Int) {
        let chars = Array(tail)
        let n = chars.count
        guard n > 0 else { return ([], 0) }
        // best[i]：恰好覆盖前 i 位的切分（音节数最少者）。
        var best: [[String]?] = Array(repeating: nil, count: n + 1)
        best[0] = []
        for end in 1...n {
            for start in 0..<end where end - start <= maxSyllableDigits {
                guard let prev = best[start] else { continue }
                if breaks.contains(where: { $0 > start && $0 < end }) { continue }
                let piece = String(chars[start..<end])
                guard let sylls = mapper.digitsToSyllables[piece] else { continue }
                for syllable in sylls {
                    let candidate = prev + [syllable]
                    if let current = best[end] {
                        if candidate.count < current.count { best[end] = candidate }
                    } else {
                        best[end] = candidate
                    }
                }
            }
        }
        var covered = n
        while covered > 0, best[covered] == nil { covered -= 1 }
        return (best[covered] ?? [], covered)
    }

    /// 枚举尾部的完整切分（至多 limit 条，按音节数升序），音节条的整条锁定用。
    /// 带节点预算防长串组合爆炸。
    private func segmentAllTail(limit: Int) -> [[String]] {
        let tail = String(digits.dropFirst(pinnedDigitCount))
        let chars = Array(tail)
        guard !chars.isEmpty else { return [] }
        let breaksRel = tailBreaks
        var results: [[String]] = []
        var budget = 400
        func dfs(_ pos: Int, _ acc: [String]) {
            guard results.count < limit, budget > 0 else { return }
            budget -= 1
            if pos == chars.count {
                results.append(acc)
                return
            }
            for len in 1...min(maxSyllableDigits, chars.count - pos) {
                if breaksRel.contains(where: { $0 > pos && $0 < pos + len }) { continue }
                let piece = String(chars[pos..<(pos + len)])
                guard let sylls = mapper.digitsToSyllables[piece] else { continue }
                for syllable in sylls {
                    dfs(pos + len, acc + [syllable])
                }
            }
        }
        dfs(0, [])
        results.sort { $0.count < $1.count }
        return results
    }
}
