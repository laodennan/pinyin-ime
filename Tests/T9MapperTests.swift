import XCTest
@testable import PinyinKeyboard

/// T9Mapper 基础自洽性测试（骨架）：保证映射表由音节清单正确生成、
/// 典型切分成立。步骤 4 扩充边界用例（pinned 锁定、无法切分的尾巴等）。
final class T9MapperTests: XCTestCase {
    private let mapper = T9Mapper(syllables: ["ni", "hao", "zhong", "guo", "wo", "men"])

    func testSyllableEncoding() {
        XCTAssertEqual(mapper.syllableToDigits["ni"], "64")
        XCTAssertEqual(mapper.syllableToDigits["hao"], "426")
        XCTAssertEqual(Set(mapper.digitsToSyllables["64"] ?? []), ["ni"])
    }

    func testSegmentation() {
        XCTAssertEqual(mapper.segment(digits: "64426"), ["ni", "hao"])
        XCTAssertEqual(mapper.segment(digits: "94664486"), ["zhong", "guo"])
    }

    func testPinnedSegmentation() {
        XCTAssertEqual(mapper.segment(digits: "64426", pinned: ["ni"]), ["ni", "hao"])
        XCTAssertNil(mapper.segment(digits: "64426", pinned: ["hao"]))
    }
}
