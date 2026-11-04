import Foundation

/// 应用层 T9：把九宫格数字序列切分为拼音音节，再喂给 Rime 的全拼会话。
/// 设计依据见 PLAN.md 第 3 节（Hamster 的 HamsterKit 同款实现路线）。
///
/// 核心构件（均由 syllables.txt 程序化生成，不手写映射表）：
/// - digitToSyllables：数字串 → 该数字串恰好对应的音节列表；
/// - 以「音节的数字编码」构建前缀集合，用于切分时的可行性剪枝（等价于 Hamster 的 Trie）；
/// - segment(digits:)：动态规划求最优切分。
public final class T9Mapper {
    /// 字母 → 九宫格数字（标准电话键盘；ü 以 v 记）。
    public static let letterToDigit: [Character: Character] = [
        "a": "2", "b": "2", "c": "2",
        "d": "3", "e": "3", "f": "3",
        "g": "4", "h": "4", "i": "4",
        "j": "5", "k": "5", "l": "5",
        "m": "6", "n": "6", "o": "6",
        "p": "7", "q": "7", "r": "7", "s": "7",
        "t": "8", "u": "8", "v": "8",
        "w": "9", "x": "9", "y": "9", "z": "9",
    ]

    /// 全部合法音节。
    public let syllables: [String]
    /// 音节 → 数字编码。
    public let syllableToDigits: [String: String]
    /// 数字编码 → 音节列表。
    public let digitsToSyllables: [String: [String]]
    /// 全部数字编码的前缀集合（含完整编码本身），供切分剪枝/Trie 式前缀查询。
    private let digitPrefixes: Set<String>

    public init(syllables: [String]) {
        self.syllables = syllables
        var toDigits: [String: String] = [:]
        var toSyllables: [String: [String]] = [:]
        var prefixes = Set<String>()
        for syllable in syllables {
            let code = syllable.map { Self.letterToDigit[$0]! }.map(String.init).joined()
            toDigits[syllable] = code
            toSyllables[code, default: []].append(syllable)
            for i in 1...code.count { prefixes.insert(String(code.prefix(i))) }
        }
        self.syllableToDigits = toDigits
        self.digitsToSyllables = toSyllables
        self.digitPrefixes = prefixes
    }

    /// 从打包资源 syllables.txt 加载（空格/换行分隔）。
    /// 资源可能被打进 appex 根目录，也可能保留 T9/ 子目录层级，两种都试。
    public convenience init?(bundle: Bundle = .main, resource: String = "syllables") {
        let url = bundle.url(forResource: resource, withExtension: "txt")
            ?? bundle.url(forResource: resource, withExtension: "txt", subdirectory: "T9")
        guard let url,
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let list = raw.split { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }
            .map(String.init)
            .filter { !$0.hasPrefix("#") }
        self.init(syllables: list)
    }

    /// 某个数字串是否可能是某个音节编码的前缀（切分剪枝用）。
    public func isDigitPrefix(_ digits: String) -> Bool { digitPrefixes.contains(digits) }

    /// 对数字串求最优切分：完整覆盖、音节数最少优先。
    /// pinned 为用户已锁定的前缀音节（音节条点选），切分必须以其开头。
    /// 返回 nil 表示当前数字串无法被完整切分（尾巴尚未打完时会出现）；
    /// 调用方（T9 输入状态机，步骤 4 实现）此时应对最长可切分前缀调用本方法、
    /// 尾部数字暂存，待后续按键补全。
    public func segment(digits: String, pinned: [String] = []) -> [String]? {
        let results = segmentAll(digits: digits, pinned: pinned, limit: 1)
        return results.first
    }

    /// 返回前 limit 个候选切分（按音节数升序），供音节条/调试使用。
    public func segmentAll(digits: String, pinned: [String] = [], limit: Int = 8) -> [[String]] {
        let chars = Array(digits)
        let pinnedDigits = pinned.compactMap { syllableToDigits[$0] }.joined()
        guard digits.hasPrefix(pinnedDigits) else { return [] }

        // DP：best[i] = 覆盖前 i 位数字的切分（音节数最少者优先，保留多解的前几名）。
        var best: [[[String]]] = Array(repeating: [], count: chars.count + 1)
        best[0] = [[]]
        for end in 1...chars.count {
            var candidates: [[String]] = []
            for start in 0..<end {
                let piece = String(chars[start..<end])
                guard let sylls = digitsToSyllables[piece], !best[start].isEmpty else { continue }
                for prefixSeg in best[start] {
                    for syll in sylls { candidates.append(prefixSeg + [syll]) }
                }
            }
            candidates.sort { $0.count < $1.count }
            best[end] = Array(candidates.prefix(limit))
        }
        return best[chars.count].filter { seg in
            pinned.isEmpty || seg.starts(with: pinned)
        }
    }
}
