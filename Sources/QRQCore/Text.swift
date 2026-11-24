// String helpers that would otherwise come from Foundation. QRQCore builds without Foundation for the
// web version (WebAssembly), where Foundation would add megabytes to the download: use these instead of
// Foundation's string methods.

extension StringProtocol {
    /// The text without spaces or tabs at either end (Foundation's `trimmingCharacters(in: .whitespaces)`).
    public func trimmingSpaces() -> String {
        let isSpace: (Character) -> Bool = { $0.isWhitespace && !$0.isNewline }
        guard let first = firstIndex(where: { !isSpace($0) }), let last = lastIndex(where: { !isSpace($0) }) else { return "" }
        return String(self[first...last])
    }
}
