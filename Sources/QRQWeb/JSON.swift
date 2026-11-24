// A small JSON reader and writer, so the Wasm build needs no Foundation (JSONDecoder/JSONEncoder would
// bring in FoundationEssentials and roughly double the download).

enum JSON {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([(String, JSON)])

    subscript(key: String) -> JSON? {
        if case .object(let members) = self { return members.first { $0.0 == key }?.1 }
        return nil
    }

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var double: Double? { if case .number(let n) = self { return n }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var array: [JSON]? { if case .array(let a) = self { return a }; return nil }

    // MARK: Writing

    var text: String {
        var out = ""
        write(to: &out)
        return out
    }

    func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n):
            if !n.isFinite { out += "null" }
            else if n == n.rounded(), abs(n) < 1e15 { out += String(Int64(n)) }
            else { out += String(n) } // Swift's shortest round-trip form, which is valid JSON
        case .string(let s): JSON.quote(s, into: &out)
        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += "," }
                item.write(to: &out)
            }
            out += "]"
        case .object(let members):
            out += "{"
            for (i, (key, value)) in members.enumerated() {
                if i > 0 { out += "," }
                JSON.quote(key, into: &out)
                out += ":"
                value.write(to: &out)
            }
            out += "}"
        }
    }

    private static func quote(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
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
    }

    // MARK: Reading

    static func parse(_ bytes: [UInt8]) -> JSON? {
        var p = Parser(bytes: bytes)
        guard let value = p.value() else { return nil }
        p.skipSpace()
        return p.at == bytes.count ? value : nil
    }

    private struct Parser {
        let bytes: [UInt8]
        var at = 0

        mutating func skipSpace() {
            while at < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[at]) { at += 1 }
        }

        mutating func literal(_ word: String) -> Bool {
            let w = Array(word.utf8)
            guard at + w.count <= bytes.count, Array(bytes[at..<at + w.count]) == w else { return false }
            at += w.count
            return true
        }

        mutating func value() -> JSON? {
            skipSpace()
            guard at < bytes.count else { return nil }
            switch bytes[at] {
            case UInt8(ascii: "{"):
                at += 1
                var members: [(String, JSON)] = []
                skipSpace()
                if at < bytes.count, bytes[at] == UInt8(ascii: "}") { at += 1; return .object(members) }
                while true {
                    skipSpace()
                    guard let key = string() else { return nil }
                    skipSpace()
                    guard at < bytes.count, bytes[at] == UInt8(ascii: ":") else { return nil }
                    at += 1
                    guard let v = value() else { return nil }
                    members.append((key, v))
                    skipSpace()
                    guard at < bytes.count else { return nil }
                    if bytes[at] == UInt8(ascii: ",") { at += 1; continue }
                    if bytes[at] == UInt8(ascii: "}") { at += 1; return .object(members) }
                    return nil
                }
            case UInt8(ascii: "["):
                at += 1
                var items: [JSON] = []
                skipSpace()
                if at < bytes.count, bytes[at] == UInt8(ascii: "]") { at += 1; return .array(items) }
                while true {
                    guard let v = value() else { return nil }
                    items.append(v)
                    skipSpace()
                    guard at < bytes.count else { return nil }
                    if bytes[at] == UInt8(ascii: ",") { at += 1; continue }
                    if bytes[at] == UInt8(ascii: "]") { at += 1; return .array(items) }
                    return nil
                }
            case UInt8(ascii: "\""): return string().map(JSON.string)
            case UInt8(ascii: "t"): return literal("true") ? .bool(true) : nil
            case UInt8(ascii: "f"): return literal("false") ? .bool(false) : nil
            case UInt8(ascii: "n"): return literal("null") ? .null : nil
            default:
                let start = at
                while at < bytes.count, "+-0123456789.eE".utf8.contains(bytes[at]) { at += 1 }
                return Double(String(decoding: bytes[start..<at], as: UTF8.self)).map(JSON.number)
            }
        }

        mutating func string() -> String? {
            guard at < bytes.count, bytes[at] == UInt8(ascii: "\"") else { return nil }
            at += 1
            var scalars = String.UnicodeScalarView()
            var run: [UInt8] = []
            func flush() {
                scalars.append(contentsOf: String(decoding: run, as: UTF8.self).unicodeScalars)
                run.removeAll()
            }
            while at < bytes.count {
                let b = bytes[at]
                at += 1
                if b == UInt8(ascii: "\"") { flush(); return String(scalars) }
                guard b == UInt8(ascii: "\\") else { run.append(b); continue }
                flush()
                guard at < bytes.count else { return nil }
                let e = bytes[at]
                at += 1
                switch e {
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "b"): scalars.append("\u{08}")
                case UInt8(ascii: "f"): scalars.append("\u{0C}")
                case UInt8(ascii: "u"):
                    guard at + 4 <= bytes.count,
                          let code = UInt32(String(decoding: bytes[at..<at + 4], as: UTF8.self), radix: 16) else { return nil }
                    at += 4
                    // Surrogate pairs aren't needed for settings text; anything unpaired becomes U+FFFD.
                    scalars.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                default: scalars.append(Unicode.Scalar(e))
                }
            }
            return nil
        }
    }
}
