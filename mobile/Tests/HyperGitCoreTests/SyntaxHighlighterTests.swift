// Tests exercise the real tokenizer regex/decisions — no SwiftUI, no mocks.
import Testing
import Foundation
@testable import HyperGitCore

@Suite("SyntaxHighlighter")
struct SyntaxHighlighterTests {
    private func kinds(_ text: String, _ language: SyntaxLanguage) -> [(String, SyntaxToken.Kind)] {
        let ns = text as NSString
        return SyntaxHighlighter.tokens(in: text, language: language)
            .sorted { $0.range.location < $1.range.location }
            .map { (ns.substring(with: $0.range), $0.kind) }
    }

    @Test("detects language from extension, case-insensitively and dot-optional")
    func languageDetection() {
        #expect(SyntaxLanguage.detect(extension: "swift") == .swift)
        #expect(SyntaxLanguage.detect(extension: "SWIFT") == .swift)
        #expect(SyntaxLanguage.detect(extension: ".swift") == .swift)
        #expect(SyntaxLanguage.detect(extension: ".TS") == .javascript)
        #expect(SyntaxLanguage.detect(extension: "ts") == .javascript)
        #expect(SyntaxLanguage.detect(extension: "tsx") == .javascript)
        #expect(SyntaxLanguage.detect(extension: "py") == .python)
        #expect(SyntaxLanguage.detect(extension: "go") == .cFamily)
        #expect(SyntaxLanguage.detect(extension: "md") == .plain)
        #expect(SyntaxLanguage.detect(extension: nil) == .plain)
        // Rust is excluded from .cFamily, not just unmapped — see the file
        // header: its `'a` lifetimes collide with the shared string pattern.
        #expect(SyntaxLanguage.detect(extension: "rs") == .plain)
    }

    @Test("Rust is plain, not cFamily — lifetimes would otherwise mislabel code as a string")
    func rustLifetimesDoNotBreakOnPlain() {
        let text = "fn f<'a>(x: &'a str) -> &'a str { x }"
        // The actual exclusion rationale, demonstrated rather than asserted:
        // .cFamily's shared single-quote string pattern DOES swallow the
        // `'a>(x: &'` span (lifetime-quote to lifetime-quote) into one bogus
        // string token — real code mislabeled, not merely under-highlighted.
        // .plain correctly produces nothing at all instead.
        let asCFamilyWouldSee = kinds(text, .cFamily)
        #expect(asCFamilyWouldSee.contains { $0.1 == .string && $0.0.contains("(x: &") })
        #expect(SyntaxHighlighter.tokens(in: text, language: .plain).isEmpty)
    }

    @Test("every highlightable language tokenizes at least one of its own keywords")
    func everyLanguageHasAWorkingKeywordSet() {
        let sample: [SyntaxLanguage: String] = [
            .swift: "func f() {}",
            .javascript: "function f() {}",
            .python: "def f(): pass",
            .cFamily: "if (x) { return; }",
        ]
        for language in SyntaxLanguage.allCases where language != .plain {
            let text = sample[language] ?? ""
            #expect(!SyntaxHighlighter.tokens(in: text, language: language).isEmpty,
                    "\(language) produced no tokens for \"\(text)\"")
        }
    }

    @Test("JavaScript and C-family keywords, strings, and numbers are tokenized")
    func javascriptAndCFamilyTokens() {
        // A plain (non-raw) string here so `\n` is a real newline, not literal backslash-n.
        let js = kinds("const n = 3; // note\nlet s = \"hi\";", .javascript)
        #expect(js.contains { $0 == ("const", .keyword) })
        #expect(js.contains { $0 == ("3", .number) })
        #expect(js.contains { $0 == (#""hi""#, .string) })

        let c = kinds(#"int x = 1; if (x) { return x; } // c-family"#, .cFamily)
        #expect(c.contains { $0 == ("int", .keyword) })
        #expect(c.contains { $0 == ("if", .keyword) })
        #expect(c.contains { $0 == ("1", .number) })
    }

    @Test("an escaped quote inside a string does not end the string early")
    func escapedQuoteInsideString() {
        let text = #"let msg = "a \" b""#
        let found = kinds(text, .swift)
        #expect(found.contains { $0 == (#""a \" b""#, .string) })
    }

    @Test("decimal numbers are tokenized as one number, not split at the dot")
    func decimalNumbers() {
        let found = kinds("let pi = 3.14", .swift)
        #expect(found.contains { $0 == ("3.14", .number) })
    }

    @Test("a quote-like sequence inside a block comment is not split into a string")
    func blockCommentWinsOverQuoteLookAlike() {
        let found = kinds("/* \"x\" */\nlet y = 1", .swift)
        #expect(found.contains { $0 == (#"/* "x" */"#, .comment) })
        #expect(!found.contains { $0.1 == .string })
    }

    @Test("Swift keywords, strings, and numbers are tokenized")
    func swiftTokens() {
        let text = #"func greet() { let name = "world"; let n = 42 }"#
        let found = kinds(text, .swift)
        #expect(found.contains { $0 == ("func", .keyword) })
        #expect(found.contains { $0 == ("let", .keyword) })
        #expect(found.contains { $0 == (#""world""#, .string) })
        #expect(found.contains { $0 == ("42", .number) })
        // Identifiers that merely contain a keyword substring must not match.
        #expect(!found.contains { $0.0 == "name" })
    }

    @Test("line comment consumes to end of line, block comment spans lines")
    func comments() {
        let line = "let x = 1 // trailing note\nlet y = 2"
        let lineFound = kinds(line, .swift)
        #expect(lineFound.contains { $0 == ("// trailing note", .comment) })

        let block = "/* a\nmulti\nline */\nlet z = 3"
        let blockFound = kinds(block, .swift)
        #expect(blockFound.contains { $0.1 == .comment && $0.0.contains("multi") })
    }

    @Test("Python uses # comments and its own keyword set")
    func pythonTokens() {
        let text = "# note\ndef f(x):\n    return x"
        let found = kinds(text, .python)
        #expect(found.contains { $0 == ("# note", .comment) })
        #expect(found.contains { $0 == ("def", .keyword) })
        #expect(found.contains { $0 == ("return", .keyword) })
    }

    @Test("Python single/double-quoted string literals are tokenized")
    func pythonStringTokens() {
        let text = "name = 'world'\ngreeting = \"hi\""
        let found = kinds(text, .python)
        #expect(found.contains { $0 == ("'world'", .string) })
        #expect(found.contains { $0 == (#""hi""#, .string) })
    }

    @Test("a keyword-like sequence inside a string is not split out as a keyword")
    func stringWinsOverKeyword() {
        let text = #"let msg = "func // x""#
        let found = kinds(text, .swift)
        #expect(found.contains { $0 == (#""func // x""#, .string) })
        #expect(found.contains { $0 == ("let", .keyword) })
        #expect(!found.contains { $0 == ("func", .keyword) })
        #expect(!found.contains { $0.1 == .comment })
    }

    @Test("triple-quoted strings are a known, documented limitation (pinned, not silently broken)")
    func tripleQuotedStringsAreAKnownLimitation() {
        // A Swift """..."""/Python """docstring""" is NOT recognized as one
        // multiline string token — see the file header comment. This test
        // pins the actual (imperfect) current behavior so a change to it is a
        // deliberate, reviewed choice rather than an unnoticed regression.
        let text = "\"\"\"\nnot a comment: // still just text\n\"\"\"\nlet x = 1"
        let found = kinds(text, .swift)
        // The opening and closing `"""` each tokenize as an empty string,
        // and content in between (like a `//`-looking line) is scanned as
        // ordinary code rather than swallowed as string content.
        #expect(found.contains { $0.0 == "\"\"" && $0.1 == .string })
        #expect(found.contains { $0 == ("let", .keyword) })
    }

    @Test("Go backtick raw strings are a known, documented limitation (pinned, not silently broken)")
    func goBacktickRawStringsAreAKnownLimitation() {
        // Go's `...` raw string isn't a recognized delimiter (only '/") — see
        // the file header. Content inside one that merely looks like a
        // comment gets mislabeled as a real comment token: the same
        // "actively wrong" class as the Rust exclusion, just narrower.
        let text = "x := `see // not a real comment`"
        let found = kinds(text, .cFamily)
        #expect(found.contains { $0.1 == .comment && $0.0.contains("not a real comment") })
    }

    @Test("a string containing a comment-like sequence is not split into a comment")
    func stringWinsOverComment() {
        let text = #"let url = "http://example.com""#
        let found = kinds(text, .swift)
        #expect(found.contains { $0.1 == .string && $0.0.contains("http://example.com") })
        #expect(!found.contains { $0.1 == .comment })
    }

    @Test("a quote-like sequence inside a comment is not split into a string")
    func commentWinsOverQuoteLookAlike() {
        let text = #"// "not a string" is just commentary"#
        let found = kinds(text, .swift)
        #expect(found.count == 1)
        #expect(found[0] == (text, .comment))
    }

    @Test("raw output (no post-sorting) is already in document order and non-overlapping")
    func rawOutputIsOrderedAndNonOverlapping() {
        // A plain (non-raw) string here so `\n` is a real newline: it caps the
        // leading `//` comment so the rest of the line still yields distinct
        // string/number/keyword tokens to check ordering across kinds.
        let text = "// comment\nlet s = \"str\"; let n = 42; func f() {}"
        let raw = SyntaxHighlighter.tokens(in: text, language: .swift)
        #expect(raw.count > 1, "need at least 2 tokens to test ordering")
        for (a, b) in zip(raw, raw.dropFirst()) {
            #expect(a.range.location + a.range.length <= b.range.location,
                    "tokens overlap or are out of order: \(a.range) then \(b.range)")
        }
    }

    @Test("plain language (unknown extension) yields no tokens")
    func plainLanguageIsUntouched() {
        #expect(SyntaxHighlighter.tokens(in: "func let 42 // x", language: .plain).isEmpty)
    }

    @Test("oversized text is skipped for performance, even with obvious tokens")
    func oversizedTextSkipsHighlighting() {
        let huge = String(repeating: "a", count: SyntaxHighlighter.maxHighlightableLength) + " func 1"
        #expect(SyntaxHighlighter.tokens(in: huge, language: .swift).isEmpty)
    }

    @Test("text at exactly the size cap is still highlighted (cap is inclusive)")
    func exactCapSizeStillHighlights() {
        // "func " (with a trailing space, so "func" stays a distinct word) padded
        // out to exactly the cap.
        let prefix = "func "
        let padding = String(repeating: "a", count: SyntaxHighlighter.maxHighlightableLength - prefix.count)
        let text = prefix + padding
        #expect(text.utf16.count == SyntaxHighlighter.maxHighlightableLength)
        #expect(kinds(text, .swift).contains { $0 == ("func", .keyword) })
    }

    @Test("many unterminated block comments do not blow up tokenizing time")
    func unterminatedBlockCommentsStayFast() {
        // Regression guard: a naive `/\*.*?\*/` retries the lazy scan from every
        // "/*" that's never closed. Empirically (this test, run repeatedly) the
        // fixed pattern stays well under the budget on a monotonic clock (immune
        // to wall-clock jitter); a regression back to the naive pattern measures
        // in the seconds-to-minutes range on input this size, not milliseconds.
        let text = String(repeating: "/* ", count: SyntaxHighlighter.maxHighlightableLength / 3)
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = SyntaxHighlighter.tokens(in: text, language: .swift) }
        #expect(elapsed < .milliseconds(500))
    }

    @Test("one very long unterminated string still resolves in bounded time")
    func longUnterminatedStringStaysFast() {
        // Unlike the block-comment case, the string pattern excludes both `"`
        // and `\n` from its content class, so on a single line a run of `"`
        // characters always pairs up into disjoint, back-to-back matches
        // (each `"..."` closes at the very next quote) — there is no shape
        // that re-scans the same span from many independent starts, so this
        // is a plain "does one long linear scan stay fast" check, not a
        // regression guard for the same O(n²) class as the comment case.
        let text = "\"" + String(repeating: "a", count: SyntaxHighlighter.maxHighlightableLength - 1)
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = SyntaxHighlighter.tokens(in: text, language: .swift) }
        #expect(elapsed < .milliseconds(500))
    }

    @Test("canHighlight reports the same skip conditions tokens(in:language:) applies")
    func canHighlightMatchesTokensBehavior() {
        #expect(SyntaxHighlighter.canHighlight(utf16Length: 10, language: .swift))
        #expect(!SyntaxHighlighter.canHighlight(utf16Length: 10, language: .plain))
        #expect(!SyntaxHighlighter.canHighlight(
            utf16Length: SyntaxHighlighter.maxHighlightableLength + 1, language: .swift))
        #expect(SyntaxHighlighter.canHighlight(
            utf16Length: SyntaxHighlighter.maxHighlightableLength, language: .swift))
    }

    @Test("canHighlight(text:) uses UTF-16 length, not Character count, for non-ASCII text")
    func canHighlightTextUsesUTF16Length() {
        // Each "🚀" is 1 Character but 2 UTF-16 code units, so Character count
        // and UTF-16 length diverge — pin that the text-based overload uses
        // the same unit as tokens(in:language:) (UTF-16), not `.count`.
        let emoji = String(repeating: "🚀", count: SyntaxHighlighter.maxHighlightableLength / 2 + 1)
        #expect(emoji.count < SyntaxHighlighter.maxHighlightableLength)
        #expect(emoji.utf16.count > SyntaxHighlighter.maxHighlightableLength)
        #expect(!SyntaxHighlighter.canHighlight(text: emoji, language: .swift))
    }

    @Test("Python # inside a string literal is not split out as a comment")
    func pythonStringWinsOverHashComment() {
        let text = "x = \"a # b\""
        let found = kinds(text, .python)
        #expect(found.contains { $0 == ("\"a # b\"", .string) })
        #expect(!found.contains { $0.1 == .comment })
    }
}
