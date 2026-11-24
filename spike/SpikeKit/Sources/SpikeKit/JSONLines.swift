import Foundation

/// One JSON object per line, so a file can be appended to and still read after a crash.
public enum JSONLines {
    public static func encodeLine<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    /// Decodes every line that parses. A half-written last line is counted, not fatal.
    public static func decode<T: Decodable>(_ type: T.Type, from text: String) -> (items: [T], skippedLines: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        var items: [T] = []
        var skipped = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if let item = try? decoder.decode(T.self, from: Data(line.utf8)) {
                items.append(item)
            } else {
                skipped += 1
            }
        }
        return (items, skipped)
    }
}
