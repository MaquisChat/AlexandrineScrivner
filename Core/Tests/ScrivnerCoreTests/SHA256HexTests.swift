import XCTest
@testable import ScrivnerCore

final class SHA256HexTests: XCTestCase {
    func testKnownVectors() {
        XCTAssertEqual(SHA256Hex.of(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256Hex.of(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256Hex.of(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        XCTAssertEqual(SHA256Hex.of(Data(repeating: 0x61, count: 1_000_000)),
                       "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
    func testFileHashMatchesDataHashAcrossChunks() throws {
        let data = Data((0..<2_500_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sha-\(UUID().uuidString).bin")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try SHA256Hex.ofFile(at: url), SHA256Hex.of(data))
    }
    func testMissingFileThrows() {
        XCTAssertThrowsError(try SHA256Hex.ofFile(at: URL(fileURLWithPath: "/nonexistent/file.bin")))
    }
    func testIsValid() {
        XCTAssertTrue(SHA256Hex.isValid(String(repeating: "a", count: 64)))
        XCTAssertFalse(SHA256Hex.isValid(String(repeating: "A", count: 64)))
        XCTAssertFalse(SHA256Hex.isValid(String(repeating: "a", count: 63)))
    }
}
