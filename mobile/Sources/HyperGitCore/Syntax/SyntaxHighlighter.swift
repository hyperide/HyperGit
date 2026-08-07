// SyntaxHighlighter — lightweight regex-based tokenizer for the file viewer.
// Not a full lexer/parser: one alternation regex per language flags comments,
// string literals, numbers and a curated keyword list; everything else renders
// as plain text. Covers Swift, JavaScript/TypeScript, Python, and a shared
// C-family keyword set (C/C++/Objective-C/Java/Kotlin/Go/C#). Anything else
// (JSON/YAML/HTML/CSS/shell/markdown/…) is `.plain` — no highlighting.
// Deliberately basic per issue #5's "file viewer (with basic highlighting)".
// Two classes of known limitation:
//
// Simply absent (renders as plain code, not wrong, just unhighlighted): no
// nested Swift block comments, no JS template literals, no hex numbers.
//
// Actively wrong (real code gets mislabeled as something else) — each of
// these is pinned by a test, not just described here, so a change to the
// behavior is a deliberate, reviewed choice rather than an unnoticed
// regression:
//   - Multiline/triple-quoted strings (Swift `"""…"""`, Python
//     `"""docstring"""`) tokenize as an empty string plus stray quotes, and
//     their contents get highlighted as ordinary code in between.
//   - Go backtick raw strings (`` `...` ``) aren't recognized as a string at
//     all, so `//`-looking content inside one can be mislabeled as a real
//     comment.
//   - Rust is excluded from `.cFamily` entirely (maps to `.plain`): its
//     lifetime syntax (`fn f<'a>(x: &'a str)`) collides with the shared
//     single-quote string pattern and swallows real code into a bogus
//     string span.
//
// Tokens are guaranteed non-overlapping and returned in document order
// (an artifact of `enumerateMatches` scanning left to right through one
// alternation) — callers may rely on this. `range` is a UTF-16 `NSRange`
// over the exact `text` passed in.
import Foundation

public struct SyntaxToken: Sendable, Hashable {
    public enum Kind: Sendable { case keyword, string, comment, number }
    public let range: NSRange
    public let kind: Kind

    public init(range: NSRange, kind: Kind) {
        self.range = range
        self.kind = kind
    }
}

public enum SyntaxLanguage: Sendable, Equatable, CaseIterable {
    case swift, javascript, python, cFamily, plain

    /// Detect a language from a file extension — a leading dot, if present, is
    /// stripped first, and matching is case-insensitive.
    public static func detect(extension ext: String?) -> SyntaxLanguage {
        var normalized = ext?.lowercased()
        if normalized?.hasPrefix(".") == true { normalized?.removeFirst() }
        switch normalized {
        case "swift": return .swift
        case "js", "jsx", "ts", "tsx", "mjs", "cjs": return .javascript
        case "py", "pyw": return .python
        case "c", "h", "cpp", "cc", "cxx", "hpp", "hh",
             "java", "kt", "kts", "go", "cs", "m", "mm":
            return .cFamily
        // Rust is NOT mapped to .cFamily — see the file header: its lifetime
        // syntax breaks the shared single-quote string pattern.
        case "rs": return .plain
        default: return .plain
        }
    }
}

public enum SyntaxHighlighter {
    /// Files above this size (UTF-16 code units) skip highlighting — regex
    /// scanning + per-token range work scale badly; the viewer still shows
    /// the raw text.
    public static let maxHighlightableLength = 200_000

    /// Whether `tokens(in:language:)` would attempt highlighting for text of
    /// `utf16Length` UTF-16 code units in `language` — lets a caller
    /// distinguish "skipped: unsupported language or file too large" from
    /// "genuinely no tokens found" without duplicating the cap/language
    /// checks itself. Keys off the same `regexes` table `tokens` uses, so the
    /// two conditions can't diverge even though they're separate calls. The
    /// label spells out the unit because the natural mistake — passing a
    /// `String`'s `.count` (`Character` count) instead — silently diverges
    /// from it for non-ASCII text.
    public static func canHighlight(utf16Length: Int, language: SyntaxLanguage) -> Bool {
        regexes[language] != nil && utf16Length <= maxHighlightableLength
    }

    /// Convenience overload for a `String` in hand.
    public static func canHighlight(text: String, language: SyntaxLanguage) -> Bool {
        canHighlight(utf16Length: text.utf16.count, language: language)
    }

    public static func tokens(in text: String, language: SyntaxLanguage) -> [SyntaxToken] {
        guard let regex = regexes[language] else { return [] }
        let ns = text as NSString
        guard ns.length <= maxHighlightableLength else { return [] }
        var result: [SyntaxToken] = []
        result.reserveCapacity(ns.length / 16)
        let full = NSRange(location: 0, length: ns.length)
        regex.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, let kind = matchedKind(match) else { return }
            result.append(SyntaxToken(range: match.range, kind: kind))
        }
        return result
    }

    /// Named capture groups double as the token kind; return whichever one matched.
    private static let namedKinds: [(String, SyntaxToken.Kind)] = [
        ("comment", .comment), ("string", .string), ("number", .number), ("keyword", .keyword),
    ]
    private static func matchedKind(_ match: NSTextCheckingResult) -> SyntaxToken.Kind? {
        for (name, kind) in namedKinds where match.range(withName: name).location != NSNotFound {
            return kind
        }
        return nil
    }

    /// One compiled regex per highlightable language, built once at first access.
    /// Patterns are static, hand-written strings, so a compile failure here is a
    /// programmer error — `try!` makes that loud instead of silently disabling
    /// highlighting (and silently recompiling on every call).
    private static let regexes: [SyntaxLanguage: NSRegularExpression] = {
        var map: [SyntaxLanguage: NSRegularExpression] = [:]
        for language in SyntaxLanguage.allCases {
            guard let pattern = pattern(for: language) else { continue }
            map[language] = try! NSRegularExpression(pattern: pattern)
        }
        return map
    }()

    private static func pattern(for language: SyntaxLanguage) -> String? {
        guard language != .plain else { return nil }
        let string = #"(?<string>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')"#
        let number = #"(?<number>\b\d+(?:\.\d+)?\b)"#
        let parts = [commentPattern(for: language), string, number, keywordPattern(for: language)]
        let joined = parts.compactMap { $0 }
        return joined.isEmpty ? nil : joined.joined(separator: "|")
    }

    private static func commentPattern(for language: SyntaxLanguage) -> String? {
        switch language {
        case .python: return #"(?<comment>#[^\n]*)"#
        // Block-comment body is `[^*]*\*+(?:[^/*][^*]*\*+)*` rather than `.*?` —
        // consumes runs of non-`*` in one step instead of retrying one character
        // at a time from every `/*`, which is O(n²) on a file with many
        // unterminated `/*` sequences (adversarial or just malformed input).
        case .swift, .javascript, .cFamily:
            return #"(?<comment>//[^\n]*|/\*[^*]*\*+(?:[^/*][^*]*\*+)*/)"#
        case .plain: return nil
        }
    }

    private static func keywordPattern(for language: SyntaxLanguage) -> String? {
        let words = keywords(for: language)
        guard !words.isEmpty else { return nil }
        // Escaped even though today's lists are plain identifiers — a keyword
        // added later with a regex metacharacter must not silently corrupt
        // the alternation (or trip the `try!` compile below).
        let escaped = words.map { NSRegularExpression.escapedPattern(for: $0) }
        return #"(?<keyword>\b(?:"# + escaped.joined(separator: "|") + #")\b)"#
    }

    private static func keywords(for language: SyntaxLanguage) -> [String] {
        switch language {
        case .swift: return Self.swiftKeywords
        case .javascript: return Self.javascriptKeywords
        case .python: return Self.pythonKeywords
        case .cFamily: return Self.cFamilyKeywords
        case .plain: return []
        }
    }

    private static let swiftKeywords = [
        "func", "var", "let", "if", "else", "guard", "return", "struct", "class", "enum",
        "protocol", "extension", "import", "for", "while", "switch", "case", "default",
        "break", "continue", "in", "is", "as", "try", "catch", "throw", "throws", "async",
        "await", "public", "private", "internal", "fileprivate", "static", "final", "init",
        "self", "Self", "nil", "true", "false", "where", "typealias", "associatedtype",
        "some", "any", "do", "defer", "inout", "mutating",
    ]
    private static let javascriptKeywords = [
        "function", "var", "let", "const", "if", "else", "return", "class", "extends",
        "import", "export", "from", "for", "while", "switch", "case", "default", "break",
        "continue", "in", "of", "try", "catch", "finally", "throw", "async", "await", "new",
        "this", "super", "null", "undefined", "true", "false", "typeof", "instanceof",
        "yield", "static", "interface", "type", "implements", "enum", "public", "private",
        "protected", "readonly",
    ]
    private static let pythonKeywords = [
        "def", "class", "if", "elif", "else", "return", "import", "from", "as", "for",
        "while", "break", "continue", "pass", "try", "except", "finally", "raise", "with",
        "lambda", "yield", "async", "await", "in", "is", "not", "and", "or", "None", "True",
        "False", "self", "global", "nonlocal", "assert", "del",
    ]
    // C/C++/Objective-C/Java/Kotlin/Go/C# only — no "fn" (Rust) or "let"
    // (Swift/JS/Rust): neither is a keyword in any language actually mapped
    // to .cFamily, and both would mislabel an ordinary identifier by that
    // name in a real C/Java/Go file.
    private static let cFamilyKeywords = [
        "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue",
        "return", "class", "struct", "enum", "interface", "public", "private", "protected",
        "static", "final", "void", "int", "float", "double", "char", "bool", "string", "true",
        "false", "null", "nullptr", "new", "delete", "import", "package", "func",
        "var", "const", "namespace", "using", "template", "typedef", "extends", "implements",
        "throw", "try", "catch", "async", "await",
    ]
}
