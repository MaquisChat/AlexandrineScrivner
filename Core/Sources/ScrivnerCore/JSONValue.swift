import Foundation

public struct JSONParseError: Error, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// A JSON value whose objects keep their keys in order, with a writer whose output is the same
/// on every platform. `session.json` is written with this so the file can be compared byte for byte.
public indirect enum JSONValue: Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    /// The first value under `key` when this is an object; otherwise nil.
    public subscript(key: String) -> JSONValue? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.first { $0.key == key }?.value
    }
}

extension JSONValue: Equatable {
    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.bool(let a), .bool(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.object(let a), .object(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: return false
        }
    }
}

// MARK: - Writing

extension JSONValue {
    /// Two-space indent, `"key": value`, one element per line except arrays of plain values,
    /// and a newline at the end.
    public func written() -> String {
        var out = ""
        write(into: &out, indent: 0)
        out += "\n"
        return out
    }

    private var isScalar: Bool {
        switch self {
        case .array, .object: return false
        default: return true
        }
    }

    private func write(into out: inout String, indent: Int) {
        let pad = String(repeating: " ", count: indent)
        let inner = String(repeating: " ", count: indent + 2)
        switch self {
        case .null:
            out += "null"
        case .bool(let value):
            out += value ? "true" : "false"
        case .int(let value):
            out += String(value)
        case .double(let value):
            out += value.isFinite ? "\(value)" : "null"
        case .string(let value):
            out += Self.quoted(value)
        case .array(let items):
            if items.isEmpty {
                out += "[]"
            } else if items.allSatisfy(\.isScalar) {
                out += "["
                for (index, item) in items.enumerated() {
                    if index > 0 { out += ", " }
                    item.write(into: &out, indent: indent)
                }
                out += "]"
            } else {
                out += "[\n"
                for (index, item) in items.enumerated() {
                    out += inner
                    item.write(into: &out, indent: indent + 2)
                    out += index == items.count - 1 ? "\n" : ",\n"
                }
                out += pad + "]"
            }
        case .object(let pairs):
            if pairs.isEmpty {
                out += "{}"
            } else {
                out += "{\n"
                for (index, pair) in pairs.enumerated() {
                    out += inner + Self.quoted(pair.key) + ": "
                    pair.value.write(into: &out, indent: indent + 2)
                    out += index == pairs.count - 1 ? "\n" : ",\n"
                }
                out += pad + "}"
            }
        }
    }

    private static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}

// MARK: - Parsing

extension JSONValue {
    /// Strict: one value, nothing after it, no trailing commas, no duplicate keys in an object.
    public static func parse(_ text: String) throws -> JSONValue {
        var parser = Parser(bytes: Array(text.utf8))
        parser.skipWhitespace()
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.atEnd else { throw parser.error("unexpected text after the value") }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var position = 0

        var atEnd: Bool { position >= bytes.count }

        func error(_ message: String) -> JSONParseError {
            JSONParseError(message: "\(message) at byte \(position)")
        }

        mutating func skipWhitespace() {
            while position < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[position]) {
                position += 1
            }
        }

        mutating func value(depth: Int) throws -> JSONValue {
            guard depth < 200 else { throw error("nested too deeply") }
            guard position < bytes.count else { throw error("unexpected end") }
            switch bytes[position] {
            case UInt8(ascii: "{"): return try object(depth: depth)
            case UInt8(ascii: "["): return try array(depth: depth)
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try number()
            default: throw error("unexpected character")
            }
        }

        mutating func literal(_ word: String) throws {
            let expected = Array(word.utf8)
            guard position + expected.count <= bytes.count,
                  Array(bytes[position..<(position + expected.count)]) == expected else {
                throw error("unexpected word")
            }
            position += expected.count
        }

        mutating func object(depth: Int) throws -> JSONValue {
            position += 1       // {
            var pairs: [(key: String, value: JSONValue)] = []
            var seen = Set<String>()
            skipWhitespace()
            if position < bytes.count, bytes[position] == UInt8(ascii: "}") {
                position += 1
                return .object(pairs)
            }
            while true {
                skipWhitespace()
                guard position < bytes.count, bytes[position] == UInt8(ascii: "\"") else { throw error("expected a key") }
                let key = try string()
                guard seen.insert(key).inserted else { throw error("the key \"\(key)\" appears twice") }
                skipWhitespace()
                guard position < bytes.count, bytes[position] == UInt8(ascii: ":") else { throw error("expected a colon") }
                position += 1
                skipWhitespace()
                pairs.append((key, try value(depth: depth + 1)))
                skipWhitespace()
                guard position < bytes.count else { throw error("unexpected end") }
                if bytes[position] == UInt8(ascii: ",") {
                    position += 1
                } else if bytes[position] == UInt8(ascii: "}") {
                    position += 1
                    return .object(pairs)
                } else {
                    throw error("expected a comma or the end of the object")
                }
            }
        }

        mutating func array(depth: Int) throws -> JSONValue {
            position += 1       // [
            var items: [JSONValue] = []
            skipWhitespace()
            if position < bytes.count, bytes[position] == UInt8(ascii: "]") {
                position += 1
                return .array(items)
            }
            while true {
                skipWhitespace()
                items.append(try value(depth: depth + 1))
                skipWhitespace()
                guard position < bytes.count else { throw error("unexpected end") }
                if bytes[position] == UInt8(ascii: ",") {
                    position += 1
                } else if bytes[position] == UInt8(ascii: "]") {
                    position += 1
                    return .array(items)
                } else {
                    throw error("expected a comma or the end of the list")
                }
            }
        }

        mutating func string() throws -> String {
            position += 1       // opening quote
            var scalars = String.UnicodeScalarView()
            var raw: [UInt8] = []
            func flush(_ raw: inout [UInt8], into scalars: inout String.UnicodeScalarView) throws {
                guard !raw.isEmpty else { return }
                guard let text = String(validating: raw, as: UTF8.self) else {
                    throw JSONParseError(message: "text is not valid UTF-8")
                }
                scalars.append(contentsOf: text.unicodeScalars)
                raw.removeAll()
            }
            while true {
                guard position < bytes.count else { throw error("the text never ends") }
                let byte = bytes[position]
                if byte == UInt8(ascii: "\"") {
                    position += 1
                    try flush(&raw, into: &scalars)
                    return String(scalars)
                }
                if byte < 0x20 { throw error("a control character inside text") }
                if byte != UInt8(ascii: "\\") {
                    raw.append(byte)
                    position += 1
                    continue
                }
                try flush(&raw, into: &scalars)
                position += 1
                guard position < bytes.count else { throw error("the text never ends") }
                let escape = bytes[position]
                position += 1
                switch escape {
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "/"): scalars.append("/")
                case UInt8(ascii: "b"): scalars.append("\u{08}")
                case UInt8(ascii: "f"): scalars.append("\u{0C}")
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "u"):
                    var code = try hex4()
                    if (0xD800...0xDBFF).contains(code) {
                        guard position + 1 < bytes.count, bytes[position] == UInt8(ascii: "\\"),
                              bytes[position + 1] == UInt8(ascii: "u") else { throw error("half of a character pair") }
                        position += 2
                        let low = try hex4()
                        guard (0xDC00...0xDFFF).contains(low) else { throw error("half of a character pair") }
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let scalar = Unicode.Scalar(code) else { throw error("not a character") }
                    scalars.append(scalar)
                default:
                    throw error("unknown escape")
                }
            }
        }

        mutating func hex4() throws -> UInt32 {
            guard position + 4 <= bytes.count else { throw error("short \\u escape") }
            var value: UInt32 = 0
            for _ in 0..<4 {
                let byte = bytes[position]
                let digit: UInt32
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
                case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a")) + 10
                case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A")) + 10
                default: throw error("bad \\u escape")
                }
                value = value * 16 + digit
                position += 1
            }
            return value
        }

        mutating func number() throws -> JSONValue {
            let start = position
            func isDigit(_ byte: UInt8) -> Bool { byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }
            if bytes[position] == UInt8(ascii: "-") { position += 1 }
            guard position < bytes.count, isDigit(bytes[position]) else { throw error("bad number") }
            if bytes[position] == UInt8(ascii: "0") {
                position += 1
                if position < bytes.count, isDigit(bytes[position]) { throw error("a number may not start with 0") }
            } else {
                while position < bytes.count, isDigit(bytes[position]) { position += 1 }
            }
            var isWhole = true
            if position < bytes.count, bytes[position] == UInt8(ascii: ".") {
                isWhole = false
                position += 1
                guard position < bytes.count, isDigit(bytes[position]) else { throw error("bad number") }
                while position < bytes.count, isDigit(bytes[position]) { position += 1 }
            }
            if position < bytes.count, bytes[position] == UInt8(ascii: "e") || bytes[position] == UInt8(ascii: "E") {
                isWhole = false
                position += 1
                if position < bytes.count, bytes[position] == UInt8(ascii: "+") || bytes[position] == UInt8(ascii: "-") {
                    position += 1
                }
                guard position < bytes.count, isDigit(bytes[position]) else { throw error("bad number") }
                while position < bytes.count, isDigit(bytes[position]) { position += 1 }
            }
            let text = String(decoding: bytes[start..<position], as: UTF8.self)
            if isWhole, let whole = Int(text) {
                return .int(whole)
            }
            guard let value = Double(text) else { throw error("bad number") }
            return .double(value)
        }
    }
}
